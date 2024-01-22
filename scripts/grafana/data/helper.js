#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const http = require('http');
const { URL } = require('url');
const { EventGenerator } = require('./lib/event-generator');
const { Timeline } = require('./lib/timeline');
const { Timer } = require('./lib/timer');

// kick off the script execution
init();

function init() {
    // allow for handling both generation and processing
    const [
        cmd = "generate",
        modifier,
    ] = process.argv.slice(2);
    const logFile = path.join(__dirname, 'sample-data.log');

    if (cmd === "generate") {
        const timer = new Timer('generate');
        if (Number.isInteger(parseInt(modifier))) {
            generateLogFile(logFile, parseInt(modifier));
        } else {
            generateLogFile(logFile, Infinity);
        }
        timer.stop();
        timer.report();
    } else if (cmd === "hydrate") {
        const timer = new Timer('hydrate');
        syncLogsToInflux(logFile, modifier)
            .then(({ batches, lineCount}) => {
                timer.stop();
                console.log('processed', batches, 'batches totalling', lineCount, 'lines');
                timer.report();
            });
    } else {
        console.error('unknown command:', cmd);
    }
}

/**
 * Send an individual event record to the API provided
 * @param {object} payload the JSON payload to be sent
 * @param {string} endpoint the API endpoint to target
 * @returns {Promise}
 */
function sendEventRecord(payload, endpoint) {
    return new Promise((resolve, reject) => {
        // here is where we send the payload to InfluxDB
        const myUrl = new URL(endpoint);
        const postData = JSON.stringify(payload);
        const options = {
            host: myUrl.hostname,
            port: myUrl.port, // we are defaulting to localstack here
            path: myUrl.pathname,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(postData),
            }
        };

        // we resolve the promise as soon as the response is received
        const req = http.request(options, () => resolve());

        req.on('error', (e) => reject(e));
        req.write(postData);
        req.end();
    });
}

/**
 * Process a log file line-by-line and send each line as a record
 * through the API provided. Since this is designed to run in a
 * local environment, we will batch requests in order to avoid
 * saturating our I/O.
 * @param {string} filename the log file to process and hydrate into Influx
 * @param {string} endpoint the API endpoint to target
 * @returns {Promise}
 */
function syncLogsToInflux(filename, endpoint) {
    const BATCH_SIZE = 10;

    return new Promise((resolve, reject) => {
        const fileStream = fs.createReadStream(filename);
        const lineReader = readline.createInterface({
            input: fileStream,
        });

        let batches = 0;
        let lineCount = 0;
        let queue = [];

        lineReader.on('line', (line) => {
            queue.push(line);
            lineCount++;
        });

        lineReader.on('close', () => batchIt(BATCH_SIZE));

        function batchIt(batchSize) {
            batches++;
            Promise.all(
                queue.splice(0, batchSize)
                    .map((line) => {
                        const payload = JSON.parse(line);
                        return sendEventRecord(payload, endpoint);
                    })
            ).then(() => {
                if (queue.length) {
                    batchIt(batchSize);
                } else {
                    resolve({ batches, lineCount });
                }
            })
        }
    });
}

/**
 * Generates random data for the last 3 hours of time. The resulting
 * file will contain events able to hydrate InfluxDB for testing.
 * @param {string} filename the log file to be generated
 * @param {number} limit optional limit of records to be generated
 */
function generateLogFile(filename, limit = Infinity) {
    // be sure the file is empty to start with
    fs.writeFileSync(filename, '');
    const logger = fs.createWriteStream(filename, { flags: 'a' }); // append flag

    const timeline = new Timeline({
        startTime: (new Date()).getTime() - (1000 * 60 * 60 * 3), // 3 hours ago
        endTime: (new Date()).getTime(),
        minStep: 200,
        maxStep: 2000,
    });

    // we are setting ourselves up with controlled options for events
    const events = new EventGenerator({
        eventOptions: [
            // init range between 2000 - 3500
            { type: 'latency', name: 'init', value: () => (Math.floor(Math.random() * 3500) + 2000) },
            // load:a range between 1800 - 2200
            { type: 'latency', name: 'load:a', value: () => (Math.floor(Math.random() * 2200) + 1800) },
            // load:b range between 1600 - 2100
            { type: 'latency', name: 'load:b', value: () => (Math.floor(Math.random() * 2100) + 1600) },
            // message count between 2 - 10
            { type: 'count', name: 'messages', value: () => (Math.floor(Math.random() * 10) + 2) },
            // error count between 0 - 12
            { type: 'count', name: 'errors', value: () => (Math.floor(Math.random() * 12)) },
        ],
        availableSessions: 15,
    });

    // step through the defined timeline
    let timestamp = timeline.tick();
    let eventCount = 0;

    while (timestamp !== null && eventCount < limit) {
        const event = events.randomRecord(timestamp);
        logger.write(JSON.stringify({ event }) + "\n");
        timestamp = timeline.tick();
        eventCount++;
    }

    logger.end();
    console.log('logfile generated at:', filename);
}