import { config } from './config';

/* eslint-disable-next-line @typescript-eslint/no-explicit-any */
exports.handler = async function(event: any) {
    console.log('config:', config);
}
