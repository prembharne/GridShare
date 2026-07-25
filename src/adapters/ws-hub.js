import crypto from "node:crypto";

// RFC 6455 GUID used to compute the Sec-WebSocket-Accept handshake response.
const WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

// Event types worth pushing to live dashboards. Everything else stays on the
// existing SSE /events feed. Keeping this allowlist small avoids flooding
// mobile clients with internal reconciliation/idempotency chatter.
const BROADCAST_TYPES = new Set([
    "telemetry.received",
    "session.activated",
    "session.meter_tick",
    "session.auto_stop",
    "session.settled",
    "hardware.switch_changed"
]);

function computeAcceptKey(secWebSocketKey) {
    return crypto
        .createHash("sha1")
        .update(secWebSocketKey + WS_GUID)
        .digest("base64");
}

/**
 * Encode a text payload as a single (unfragmented, unmasked) server WebSocket
 * frame. Server→client frames must NOT be masked (RFC 6455 §5.1). Handles the
 * three length encodings (7-bit, 16-bit, 64-bit).
 */
function encodeTextFrame(text) {
    const payload = Buffer.from(text, "utf8");
    const len = payload.length;
    let header;

    if (len < 126) {
        header = Buffer.alloc(2);
        header[1] = len;
    } else if (len < 65536) {
        header = Buffer.alloc(4);
        header[1] = 126;
        header.writeUInt16BE(len, 2);
    } else {
        header = Buffer.alloc(10);
        header[1] = 127;
        header.writeBigUInt64BE(BigInt(len), 2);
    }

    header[0] = 0x81; // FIN + opcode 0x1 (text)
    return Buffer.concat([header, payload]);
}

// A minimal close frame (opcode 0x8) so clients disconnect cleanly.
function encodeCloseFrame() {
    return Buffer.from([0x88, 0x00]);
}

/**
 * WebSocketHub — a tiny, dependency-free live broadcast layer.
 *
 * It upgrades HTTP connections on `/ws`, then relays a curated allowlist of
 * eventBus events to connected clients. Clients can scope the firehose with
 * query params: `/ws?hostId=host_1` or `/ws?sessionId=sess_abc`. A client with
 * no filter receives every broadcast event (useful for the admin console).
 *
 * We intentionally avoid the `ws` npm package: the server only ever SENDS text
 * frames and responds to ping/close, so a ~100-line built-in implementation
 * keeps the dependency surface (and audit burden) minimal.
 */
export class WebSocketHub {
    constructor({ eventBus, path = "/ws", logger = console } = {}) {
        this.eventBus = eventBus;
        this.path = path;
        this.logger = logger;
        this.clients = new Set();
        this.unsubscribe = null;
    }

    /** Attach to an http.Server: handle upgrades and start relaying events. */
    attach(server) {
        server.on("upgrade", (req, socket) => this.handleUpgrade(req, socket));
        this.unsubscribe = this.eventBus.subscribe((event) => this.broadcast(event));
        return this;
    }

    handleUpgrade(req, socket) {
        let url;
        try {
            url = new URL(req.url, "http://localhost");
        } catch {
            socket.destroy();
            return;
        }

        if (url.pathname !== this.path) {
            // Not our endpoint — let other upgrade handlers (if any) deal with it.
            return;
        }

        const key = req.headers["sec-websocket-key"];
        if (req.headers.upgrade?.toLowerCase() !== "websocket" || !key) {
            socket.write("HTTP/1.1 400 Bad Request\r\n\r\n");
            socket.destroy();
            return;
        }

        const acceptKey = computeAcceptKey(key);
        socket.write(
            "HTTP/1.1 101 Switching Protocols\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            `Sec-WebSocket-Accept: ${acceptKey}\r\n\r\n`
        );

        const client = {
            socket,
            hostId: url.searchParams.get("hostId"),
            sessionId: url.searchParams.get("sessionId")
        };
        this.clients.add(client);

        socket.on("data", (buf) => this.handleFrame(client, buf));
        const cleanup = () => this.clients.delete(client);
        socket.on("close", cleanup);
        socket.on("error", cleanup);

        // Greet the client so it can confirm the stream is live.
        this.send(client, { type: "ws.connected", payload: { hostId: client.hostId, sessionId: client.sessionId } });
    }

    /**
     * Handle inbound client frames. We only care about control frames: reply to
     * ping with pong and honor close. Client data frames are masked; we don't
     * need their payloads, so we just detect the opcode.
     */
    handleFrame(client, buf) {
        if (buf.length < 2) return;
        const opcode = buf[0] & 0x0f;

        if (opcode === 0x8) {
            // Close: echo a close frame and drop the client.
            try { client.socket.write(encodeCloseFrame()); } catch { /* ignore */ }
            client.socket.destroy();
            this.clients.delete(client);
            return;
        }

        if (opcode === 0x9) {
            // Ping → Pong (opcode 0xA), empty payload is fine for keepalive.
            try { client.socket.write(Buffer.from([0x8a, 0x00])); } catch { /* ignore */ }
        }
    }

    /** True when `event` should reach `client` given its hostId/sessionId filter. */
    matches(client, event) {
        if (client.sessionId) {
            return event.payload?.sessionId === client.sessionId;
        }
        if (client.hostId) {
            return event.payload?.hostId === client.hostId;
        }
        return true; // unfiltered subscriber (e.g. admin dashboard)
    }

    broadcast(event) {
        if (!BROADCAST_TYPES.has(event.type)) return;
        for (const client of this.clients) {
            if (this.matches(client, event)) {
                this.send(client, event);
            }
        }
    }

    send(client, event) {
        try {
            client.socket.write(encodeTextFrame(JSON.stringify(event)));
        } catch {
            // Broken pipe etc. — drop the client.
            this.clients.delete(client);
            try { client.socket.destroy(); } catch { /* ignore */ }
        }
    }

    close() {
        if (this.unsubscribe) this.unsubscribe();
        for (const client of this.clients) {
            try { client.socket.destroy(); } catch { /* ignore */ }
        }
        this.clients.clear();
    }
}
