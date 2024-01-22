class Timer {
    constructor(label) {
        this.label = label;
        this.origin = new Date();
        this.start = this.origin;
        this.duration = 0;
    }

    start() {
        this.start = new Date();
    }

    stop() {
        const dt = new Date();
        const diff = dt.getTime() - this.start.getTime();
        this.duration += diff;
    }

    report() {
        console.info(`[${this.label}] total time:`, this.duration, 'ms');
    }
}

exports.Timer = Timer;
