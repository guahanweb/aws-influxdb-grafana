#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const readline = require('readline');
const http = require('http');
const { URL } = require('url');
const { EventGenerator } = require('./lib/event-generator');
const { Timeline } = require('./lib/timeline');

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
        if (Number.isInteger(parseInt(modifier))) {
            generateLogFile(logFile, parseInt(modifier));
        } else {
            generateLogFile(logFile, Infinity);
        }
    } else if (cmd === "hydrate") {
        // syncLogsToInflux(logFile, modifier);
        batchedLinereader(logFile, modifier);
    } else {
        console.error('unknown command:', cmd);
    }
}

async function syncLogsToInflux(filename, endpoint) {
    const result = await processLogFile(filename, (payload) => {
        return new Promise((resolve, rejct) => {
        });
    });

    console.log('result:', result);
}

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

        const req = http.request(options, (res) => {
            resolve();
        });

        req.on('error', (e) => reject(e));
        req.write(postData);
        req.end();
    });
}

function batchedLinereader(filename, endpoint) {
    const fileStream = fs.createReadStream(filename);
    const lineReader = readline.createInterface({
        input: fileStream,
    });

    let queue = [];
    lineReader.on('line', (line) => queue.push(line));
    lineReader.on('close', () => {
        // start processing
        batchIt(10);
    });

    function batchIt(batchSize) {
        console.log('processing:', batchSize);

        Promise.all(
            queue.splice(0, batchSize)
                .map((line) => {
                    const payload = JSON.parse(line);
                    return sendEventRecord(payload, endpoint);
                })
        ).then(() => {
            console.log('queue:', queue.length);

            if (queue.length) {
                batchIt(batchSize);
            }
        })
    }
}

function processLogFile(filename, lineHandler) {
    // TODO: batch requests to the API to keep from 
    // killing LocalStack I/O
    const maxLines = 10;
    let queue = 0;
    let paused = false;
    let successCount = 0;
    let errorCount = 0;

    return new Promise((resolve, reject) => {
        const fileStream = fs.createReadStream(filename);
        const lineReader = readline.createInterface({
            input: fileStream,
        });

        let lineCount = 0;
        lineReader.on('line', function (line) {
            const data = JSON.parse(line.trim());
            lineHandler(data)
                .then(() => {
                    successCount++;
                    queue--;
                    if (queue < maxLines && paused) {
                        console.log('resuming...');
                        lineReader.resume();
                    }
                })
                .catch(() => errorCount++);

            if (queue >= maxLines && !paused) {
                console.log('pausing...');
                lineReader.pause();
            }

            queue++;
            lineCount++;
        });

        lineReader.on('pause', () => paused = true);
        lineReader.on('resume', () => paused = false);

        lineReader.on('close', function () {
            resolve({
                lineCount,
                successCount,
                errorCount,
            });
        });
    });
}

function generateLogFile(filename, limit = Infinity) {
    const eventTemplate = {
        event: {
            // required fields
            type: "sample",
            name: "",
            timestamp: 0,
            value: 0,

            // tags are in the meta field
            meta: {
                session_id: "",
            },

            // any extras should be allowed
            customData: "foobar",
        }
    };

    // empty the file first
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
            { type: 'latency', name: 'init', value: () => Math.ceil(Math.random() * 1500) },
            { type: 'latency', name: 'load:a', value: () => Math.ceil(Math.random() * 2000) },
            { type: 'latency', name: 'load:b', value: () => Math.ceil(Math.random() * 2000) },
            { type: 'count', name: 'messages', value: () => Math.ceil(Math.random() * 5) },
            { type: 'count', name: 'errors', value: () => Math.ceil(Math.random() * 5) },
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