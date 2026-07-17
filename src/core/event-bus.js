export class EventBus {
  constructor({ sinks = [] } = {}) {
    this.events = [];
    this.listeners = new Set();
    this.sinks = sinks;
    this.nextId = 1;
  }

  publish(type, payload) {
    const event = {
      id: this.nextId++,
      type,
      payload,
      timestamp: new Date().toISOString()
    };

    for (const sink of this.sinks) {
      sink.write(event);
    }

    this.events.push(event);

    for (const listener of this.listeners) {
      listener(event);
    }

    return event;
  }

  subscribe(listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  list({ sinceId = 0, type } = {}) {
    return this.events.filter((event) => {
      if (event.id <= Number(sinceId)) return false;
      if (type && event.type !== type) return false;
      return true;
    });
  }
}
