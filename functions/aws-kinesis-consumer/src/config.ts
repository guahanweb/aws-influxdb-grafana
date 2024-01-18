import { WritePrecisionType } from "@influxdata/influxdb-client";

interface IConsumerConfig {
    data: {
        precision: WritePrecisionType;
    },
    influxdb: {
        url: string;
        org: string;
        bucket: string;
        token: string;
    }
}

export const config: IConsumerConfig = {
    data: {
        precision: loadFromEnv('TIMESTAMP_PRECISION', 'ms') as WritePrecisionType,
    },

    influxdb: {
        url: loadFromEnv('INFLUXDB_URL', 'http://localhost:8086') as string,
        org: loadFromEnv('INFLUXDB_ORG', 'vrlabs') as string,
        bucket: loadFromEnv('INFLUXDB_BUCKET', 'telemetry') as string,
        token: loadFromEnv('INFLUXDB_TOKEN', '') as string,
    }
};

function loadFromEnv(variable: string, defaultValue: string|number|null|undefined = undefined) {
    const value = process.env && process.env[variable];

    return value || defaultValue;
}
