const crypto = require('crypto');

class EventGenerator {
    constructor({
        eventOptions,
        availableSessions = 15,
    }) {
        this.events = eventOptions;
        this.generateAvailableSessions(availableSessions);
    }

    generateAvailableSessions(count) {
        const sessions = [];
        for (let i = 0; i < count; i++) {
            sessions.push(crypto.randomUUID());
        }
        this.sessions = sessions;
    }

    randomRecord(timestamp) {
        const sessionIndex = Math.floor(Math.random() * this.sessions.length);
        const session_id = this.sessions[sessionIndex];
        const eventIndex = Math.floor(Math.random() * this.events.length);
        const event = this.events[eventIndex];
        const eventData = {
            type: event.type,
            name: event.name,
            value: event.value(),
            timestamp,
        };

        return {
            ...eventData,
            meta: { session_id },
        };
    }
}

exports.EventGenerator = EventGenerator;
