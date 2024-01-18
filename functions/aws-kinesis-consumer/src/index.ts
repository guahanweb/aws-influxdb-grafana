import { SSM } from 'aws-sdk';
import { InfluxDB, Point, WriteApi } from '@influxdata/influxdb-client';
import { config } from './config';

interface IEventRecordType {
    event: {
        type: string;
        name: string;
        value: string|boolean|number;
        timestamp: number;
        meta?: { [key: string]: string }
    };
}

interface IEventWildcardType {
    [key: string]: string|number|boolean;
}

type EventRecord = IEventRecordType & IEventWildcardType;

exports.handler = async function(event: any, context: any, callback: any) {
    const client = new InfluxDB({
        url: config.influxdb.url,
        token: config.influxdb.token
    });

    const api = client.getWriteApi(
        config.influxdb.org,
        config.influxdb.bucket,
        config.data.precision
    );

    // List of promises for all our writes
    const promises = event.Records.map((record: any) => {
        // Kinesis data is base64 encoded, so decode it here
        const payload: string = Buffer.from(record.kinesis.data, 'base64').toString('ascii');

        // We need to trap errors during validation and write it to Influx
        try {
            const json = JSON.parse(payload);
            console.log('payload:', json);
            return writeRecord(json, api);
        } catch (err: any) {
            console.error('error:', err);

            const record = new Point('Bad_Record')
                .stringField("Data", payload)
                .tag("Error", err.toString());

            api.writePoint(record);
            return api.flush();
        }
    });

    // now, we will attempt to await all the records
    try {
        await Promise.all(promises);
        console.log('completed all promises');
    } catch (err: any) {
        console.error('at least one promise failed:', err);
        throw err;
    }
}

// once we use SSM to store the token, this will replace environment variables
async function loadTokenFromSSM(parameter: string): Promise<any> {
    const ssm = new SSM();
    const options: SSM.Types.GetParameterRequest = {
        Name: parameter,
        WithDecryption: true,
    };
    const response = await ssm.getParameter(options).promise();
    const value = response.Parameter?.Value;

    return value;
}

function writeRecord(payload: EventRecord, api: WriteApi) {
    const { event, meta } = payload;
    if (!event) throw new Error('no event specified');

    const record = new Point(event.type)
        .stringField(event.name, event.value)
        .timestamp(event.timestamp);

    // Add any fields from the top level payload - excluding "event"
    const attributes: string[] = Object.keys(payload)
        .filter((value: string) => value !== "event");

    attributes.forEach((attr: string) => createField(record, attr, payload[attr]));

    // add any fields from meta
    if (!!meta) {
        const tagNames = ["session_id"];
        const metadata: [string, string|boolean|number][] = Object.entries(meta);

        metadata.forEach(([tagName, tagValue]) => {
            // any exceptions can be handled here
            if (tagNames.includes(tagName)) {
                record.tag(tagName, tagValue as string);
            } else {
                createField(record, tagName, tagValue);
            }
        });
    }

    api.writePoint(record);
    return api.flush();
}

function createField(record: Point, field: string, value: string|boolean|number): Point {
    switch (typeof value) {
        case "string":
            record.stringField(field, value);
            break;

        case "number": 
            if (Number.isInteger(value)) {
                record.intField(field, value);
            } else {
                record.floatField(field, value);
            }
            break;

        case "boolean":
            record.booleanField(field, value);
            break;
    }

    return record;
}
