import assert from "node:assert/strict";
import crypto from "node:crypto";
import http from "node:http";
import net from "node:net";
import test from "node:test";
import { EventBus } from "../src/core/event-bus.js";
import { WebSocketHub } from "../src/adapters/ws-hub.js";

// Spin up an http server with the hub attached on an ephemeral port.
async function startHub() {
    const eventBus = new EventBus();
    const server = http.createServer((_req, res) => res.end("ok"));
    const hub = new WebSocketHub({ eventBus }).attach(server);
    await new Promise((resolve) => server.listen(0, resolve));
    const { port } = server.address();
    return { eventBus, server, hub, port };
}

// Perform a raw WebSocket handshake over a TCP socket and return the socket
// once the server's 101 response is received.
function connect(port, query = "") {
    return new Promise((resolve, reject) => {
        const socket = net.connect(port, "127.0.0.1");
        const key = crypto.randomBytes(16).toString("base64");
        socket.once("error", reject);
        socket.on("connect", () => {
            socket.write(
                `GET /ws${query} HTTP/1.1\r\n` +
                "Host: 127.0.0.1\r\n" +
                "Upgrade: websocket\r\n" +
                "Connection: Upgrade\r\n" +
                `Sec-WebSocket-Key: ${key}\r\n` +
                "Sec-WebSocket-Version: 13\r\n\r\n"
            );
        });
        const onData = (buf) => {
            const text = buf.toString("latin1");
            if (text.includes("101 Switching Protocols")) {
                socket.removeListener("data", onData);
                resolve(socket);
            }
        };
        socket.on("data", onData);
    });
}

// Decode server→client text frames (unmasked). Returns array of parsed JSON.
function decodeFrames(buf) {
    const messages = [];
    let offset = 0;
    while (offset + 2 <= buf.length) {
        const opcode = buf[offset] & 0x0f;
        let len = buf[offset + 1] & 0x7f;
        let headerLen = 2;
        if (len === 126) {
            len = buf.readUInt16BE(offset + 2);
            headerLen = 4;
        } else if (len === 127) {
            len = Number(buf.readBigUInt64BE(offset + 2));
            headerLen = 10;
        }
        if (offset + headerLen + len > buf.length) break;
        const payload = buf.slice(offset + headerLen, offset + headerLen + len);
        if (opcode === 0x1) messages.push(JSON.parse(payload.toString("utf8")));
        offset += headerLen + len;
    }
    return messages;
}

// Collect the next `count` text messages from a socket.
function collect(socket, count) {
    return new Promise((resolve) => {
        let acc = Buffer.alloc(0);
        const messages = [];
        const onData = (buf) => {
            acc = Buffer.concat([acc, buf]);
            for (const msg of decodeFrames(acc)) messages.push(msg);
            acc = Buffer.alloc(0);
            if (messages.length >= count) {
                socket.removeListener("data", onData);
                resolve(messages);
            }
        };
        socket.on("data", onData);
    });
}

test("completes the handshake and sends a ws.connected greeting", async () => {
    const { server, hub, port } = await startHub();
    const socket = await connect(port);
    const [greeting] = await collect(socket, 1);
    assert.equal(greeting.type, "ws.connected");
    socket.destroy();
    hub.close();
    server.close();
});

test("relays allowlisted events and skips internal ones", async () => {
    const { eventBus, server, hub, port } = await startHub();
    const socket = await connect(port);
    await collect(socket, 1); // consume greeting

    const received = collect(socket, 1);
    eventBus.publish("session.reconciliation_needed", { sessionId: "sess_x" }); // not allowlisted
    eventBus.publish("session.meter_tick", { sessionId: "sess_x", billedMinutes: 3 });

    const [msg] = await received;
    assert.equal(msg.type, "session.meter_tick");
    assert.equal(msg.payload.billedMinutes, 3);
    socket.destroy();
    hub.close();
    server.close();
});

test("sessionId filter only delivers matching events", async () => {
    const { eventBus, server, hub, port } = await startHub();
    const socket = await connect(port, "?sessionId=sess_target");
    await collect(socket, 1); // greeting

    const received = collect(socket, 1);
    eventBus.publish("session.settled", { sessionId: "sess_other" });   // filtered out
    eventBus.publish("session.settled", { sessionId: "sess_target" });  // delivered

    const [msg] = await received;
    assert.equal(msg.payload.sessionId, "sess_target");
    socket.destroy();
    hub.close();
    server.close();
});

test("hostId filter scopes the stream to one host", async () => {
    const { eventBus, server, hub, port } = await startHub();
    const socket = await connect(port, "?hostId=host_1");
    await collect(socket, 1); // greeting

    const received = collect(socket, 1);
    eventBus.publish("session.activated", { sessionId: "s1", hostId: "host_2" }); // filtered
    eventBus.publish("session.activated", { sessionId: "s2", hostId: "host_1" }); // delivered

    const [msg] = await received;
    assert.equal(msg.payload.hostId, "host_1");
    socket.destroy();
    hub.close();
    server.close();
});
