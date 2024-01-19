class Timeline {
    constructor({
        startTime, 
        endTime, 
        minStep = 1000, 
        maxStep = 5000, 
    }) {
        this.currentTime = startTime;
        this.endTime = endTime;
        this.minStep = minStep;
        this.maxStep = maxStep;
    }

    tick() {
        const stepTime = Math.floor(Math.random() * this.maxStep) + this.minStep;
        this.currentTime += stepTime;
        return (this.currentTime > this.endTime)
            ? null
            : this.currentTime;
    }
}

exports.Timeline = Timeline;
