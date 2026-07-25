#!/usr/bin/env node
/**
 * Phase 6 — End-to-end verification against a REAL Wipro/Tuya smart plug.
 *
 * Drives the complete per-minute charging lifecycle through the live HTTP +
 * WebSocket API exactly as the mobile app would, and asserts the physical plug
 * actually switches on/off and reports telemetry:
 *
 *   1. health check                     → server is up
 *   2. GET /outlets/:id/live            → plug reachable, switch state read
 *   3. POST /sessions/intent            → per-minute intent (rate + duration)
 *   4. POST /sessions/:id/start         → deposit locked, Tuya switch_1 = ON
 *   5. GET /outlets/:id/live (poll)     → confirms switchOn === true + power
 *   6. WebSocket /ws?sessionId=...      → observes live meter ticks/telemetry
 *   7. POST /sessions/:id/stop          → Tuya switch_1 = OFF, settlement
 *   8. GET /outlets/:id/live            → confirms switchOn === false
 *   9. GET /sessions/:id/audit          → settlement conservation invariant
 *
 * This script talks ONLY to the public API — no internal imports — so it works
 * against a local dev server, a staging box, or production. It is intentionally
 * NOT part of `npm test` (which must run hardware-free); run it manually when a
 * plug is connected. See docs/phase6-real-plug-e2e.md for the runbook.
 *
 * Usage:
 *   node scripts/e2e-real-plug.js
 *
 * Env (all optional; sensible defaults for a local run):
 *   E2E_BASE_URL        default http://localhost:8080
 *   E2E_OUTLET_ID       outlet to charge (must map to a real Tuya device id)
 *   E2E_RIDER_ID        default e2e_rider
 *   E2E_HOST_ID         default e2e_host
 *   E2E_DURATION_MIN    selected duration minutes (default 1 — fast run)
 *   E2E_RATE_PER_MIN    credits/minute (default 2)
 *   E2E_DEPOSIT         locked deposit credits (default rate*duration)
 *   E2E_OBSERVE_SEC     seconds to keep the plug ON and observe (default 75)
 *   E2E_SKIP_WS         "true" to skip the WebSocket observation step
 */

const BASE_URL = (process.env.E2E_BASE_URL || "http://localhost:8080").replace(/\/$/, "");
const OUTLET_ID = process.env.E2E_OUTLET_ID || "outlet_1";
const RIDER_ID = process.env.E2E_RIDER_ID || "e2e_rider";
const HOST_ID = process.env.E2E_HOST_ID || "e2e_host";
const DURATION_MIN = intEnv("E2E_DURATION_MIN", 1);
const RATE_PER_MIN = intEnv("E2E_RATE_PER_MIN", 2);
const DEPOSIT = intEnv("E2E_DEPOSIT", RATE_PER_MIN * DURATION_MIN);
const OBSERVE_SEC = intEnv("E2E_OBSERVE_SEC", 75);
const SKIP_WS = String(process.env.E2E_SKIP_WS || "").toLowerCase() === "true";

let passed = 0;
let failed = 0;

function intEnv(name, fallback) {
    const raw = process.env[name];
    const n = raw === undefined || raw === "" ? fallback : Number(raw);
    if (!Number.isFinite(n)) throw new Error(`${name} must be a number`);
    return Math.floor(n);
}

function log(msg) {
    process.stdout.write(`${msg}\n`);
}

function step(name) {
    log(`\n▶ ${name}`);
}

function ok(msg) {
    passed += 1;
    log(`  ✔ ${msg}`);
}

function fail(msg) {
    failed += 1;
    log(`  x FAIL: ${msg}`);

}

function assert(cond, msg) {
    if (cond) ok(msg);
    else fail(msg);
    return Boolean(cond);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function api(method, path, body) {
    const url = `${BASE_URL}${path}`;
    const res = await fetch(url, {
        method,
        headers: body ? { "content-type": "application/json" } : undefined,
        body: body ? JSON.stringify(body) : undefined
    });
    let json;
    try {
        json = await res.json();
    } catch {
        json = null;
    }
    return { status: res.status, json };
}

/**
 * Minimal RFC 6455 client for the /ws live stream. Uses only Node built-ins so
 * the script has zero dependencies. Collects the first `maxEvents` messages (or
 * until `timeoutMs`) matching our sessionId, then resolves.
 */
async function observeWebSocket({ sessionId, timeoutMs }) {
    if (SKIP_WS) {
        log("  (skipped — E2E_SKIP_WS=true)");
        return [];
    }
    const net = await import("node:net");
    const crypto = await import("node:crypto");
    const u = new URL(BASE_URL);
    const isTls = u.protocol === "https:";
    const port = u.port || (isTls ? 443 : 80);
    const path = `/ws?sessionId=${encodeURIComponent(sessionId)}`;
    const key = crypto.randomBytes(16).toString("base64");

    if (isTls) {
        log("  (skipped — wss/TLS not supported by the built-in observer; use E2E_SKIP_WS)");
        return [];
    }

    return await new Promise((resolve) => {
        const events = [];
        const socket = net.connect(Number(port), u.hostname, () => {
            const req =
                `GET ${path} HTTP/1.1\r\n` +
                `Host: ${u.hostname}:${port}\r\n` +
                "Upgrade: websocket\r\n" +
                "Connection: Upgrade\r\n" +
                `Sec-WebSocket-Key: ${key}\r\n` +
                "Sec-WebSocket-Version: 13\r\n\r\n";
            socket.write(req);
        });

        let handshakeDone = false;
        let buffer = Buffer.alloc(0);
        const timer = setTimeout(() => {
            try { socket.destroy(); } catch { }
            resolve(events);
        }, timeoutMs);

        socket.on("data", (chunk) => {
            buffer = Buffer.concat([buffer, chunk]);
            if (!handshakeDone) {
                const headerEnd = buffer.indexOf("\r\n\r\n");
                if (headerEnd === -1) return;
                handshakeDone = true;
                buffer = buffer.subarray(headerEnd + 4);
            }
            // Parse as many complete server frames as are buffered.
            let framePayload;
            while ((framePayload = decodeFrame(buffer)) !== null) {
                buffer = buffer.subarray(framePayload.consumed);
                if (framePayload.text) {
                    try {
                        events.push(JSON.parse(framePayload.text));
                    } catch {
                        /* ignore non-JSON frames */
                    }
                }
            }
        });

        socket.on("error", () => {
            clearTimeout(timer);
            resolve(events);
        });
        socket.on("close", () => {
            clearTimeout(timer);
            resolve(events);
        });
    });
}

/** Decode a single unmasked server->client text frame. Returns null if incomplete. */
function decodeFrame(buf) {
    if (buf.length < 2) return null;
    const opcode = buf[0] & 0x0f;
    const masked = (buf[1] & 0x80) !== 0;
    let len = buf[1] & 0x7f;
    let offset = 2;
    if (len === 126) {
        if (buf.length < 4) return null;
        len = buf.readUInt16BE(2);
        offset = 4;
    } else if (len === 127) {
        if (buf.length < 10) return null;
        len = Number(buf.readBigUInt64BE(2));
        offset = 10;
    }
    let maskKey;
    if (masked) {
        if (buf.length < offset + 4) return null;
        maskKey = buf.subarray(offset, offset + 4);
        offset += 4;
    }
    if (buf.length < offset + len) return null;
    let payload = buf.subarray(offset, offset + len);
    if (masked && maskKey) {
        payload = Buffer.from(payload);
        for (let i = 0; i < payload.length; i += 1) payload[i] ^= maskKey[i % 4];
    }
    const consumed = offset + len;
    // opcode 1 = text, 8 = close
    return { consumed, text: opcode === 1 ? payload.toString("utf8") : null };
}

async function main() {
    log("GridShare — Phase 6 real-plug E2E");
    log(`  base:     ${BASE_URL}`);
    log(`  outlet:   ${OUTLET_ID}`);
    log(`  billing:  ${RATE_PER_MIN} credits/min × ${DURATION_MIN} min → deposit ${DEPOSIT}`);
    log(`  observe:  ${OBSERVE_SEC}s`);

    // 1) Health
    step("1. Health check");
    {
        const { status, json } = await api("GET", "/health");
        assert(status === 200 && json?.ok, `server healthy (status ${status})`);
    }

    // 2) Live status (plug reachable)
    step("2. Read live plug status (pre-charge)");
    {
        const { status, json } = await api("GET", `/outlets/${encodeURIComponent(OUTLET_ID)}/live`);
        if (status === 501) {
            fail("hardware bridge has no live status — are you running with real Tuya adapters? (GRIDSHARE_USE_REAL_ADAPTERS=true)");
        } else if (assert(status === 200 && json?.ok, `live status reachable (status ${status})`)) {
            const live = json.data?.live ?? {};
            log(`     switchOn=${live.switchOn} powerW=${live.powerW} voltageV=${live.voltageV} energyWh=${live.energyWh}`);
            assert(live.switchOn === false, "plug starts OFF (if ON, stop any active session first)");
        }
    }

    // 3) Create per-minute intent
    step("3. Create per-minute session intent");
    let sessionId;
    {
        const { status, json } = await api("POST", "/sessions/intent", {
            riderId: RIDER_ID,
            hostId: HOST_ID,
            outletId: OUTLET_ID,
            depositCredits: DEPOSIT,
            ratePerMinuteCredits: RATE_PER_MIN,
            selectedDurationMinutes: DURATION_MIN,
            idempotencyKey: `e2e_intent_${Date.now()}`
        });
        if (assert(status === 201 && json?.ok, `intent created (status ${status})`)) {
            sessionId = json.data?.id;
            assert(Boolean(sessionId), `session id returned: ${sessionId}`);
            assert(json.data?.ratePerMinuteCredits === RATE_PER_MIN, "rate recorded on session");
        }
    }
    if (!sessionId) return finish();

    // 4) Start — locks deposit + turns the plug ON
    step("4. Start session (locks deposit, switches plug ON)");
    {
        const { status, json } = await api("POST", `/sessions/${encodeURIComponent(sessionId)}/start`, {
            idempotencyKey: `e2e_start_${sessionId}`
        });
        assert(status === 200 && json?.ok, `session started (status ${status})`);
        assert(json?.data?.status === "active", `session active (status=${json?.data?.status})`);
    }

    // 5) Confirm the physical plug is ON
    step("5. Confirm plug switched ON + drawing power");
    {
        let confirmed = false;
        for (let i = 0; i < 6 && !confirmed; i += 1) {
            await sleep(2000);
            const { json } = await api("GET", `/outlets/${encodeURIComponent(OUTLET_ID)}/live`);
            const live = json?.data?.live ?? {};
            log(`     [${i}] switchOn=${live.switchOn} powerW=${live.powerW}`);
            if (live.switchOn === true) confirmed = true;
        }
        assert(confirmed, "plug reports switchOn === true after start");
    }

    // 6) Observe live stream while charging
    step(`6. Observe live WebSocket stream (~${OBSERVE_SEC}s)`);
    {
        const events = await observeWebSocket({
            sessionId,
            timeoutMs: OBSERVE_SEC * 1000
        });
        if (!SKIP_WS) {
            const types = new Set(events.map((e) => e.type));
            log(`     received ${events.length} event(s): ${[...types].join(", ") || "(none)"}`);
            assert(events.length > 0, "received at least one live event during charging");
        }
    }

    // 7) Stop — turns the plug OFF + settles by minutes
    step("7. Stop session (switches plug OFF, settles by minutes)");
    let settlement;
    {
        const { status, json } = await api("POST", `/sessions/${encodeURIComponent(sessionId)}/stop`, {
            reason: "user_stop",
            idempotencyKey: `e2e_stop_${sessionId}`
        });
        assert(status === 200 && json?.ok, `session stopped (status ${status})`);
        settlement = json?.data?.settlement ?? json?.data;
        log(`     settlement: ${JSON.stringify(settlement)}`);
    }

    // 8) Confirm the plug is OFF again
    step("8. Confirm plug switched OFF");
    {
        let off = false;
        for (let i = 0; i < 6 && !off; i += 1) {
            await sleep(2000);
            const { json } = await api("GET", `/outlets/${encodeURIComponent(OUTLET_ID)}/live`);
            const live = json?.data?.live ?? {};
            log(`     [${i}] switchOn=${live.switchOn} powerW=${live.powerW}`);
            if (live.switchOn === false) off = true;
        }
        assert(off, "plug reports switchOn === false after stop");
    }

    // 9) Audit — settlement conservation invariant
    step("9. Audit settlement (conservation invariant)");
    {
        const { status, json } = await api("GET", `/sessions/${encodeURIComponent(sessionId)}/audit`);
        if (assert(status === 200 && json?.ok, `audit reachable (status ${status})`)) {
            const s = json.data?.settlement ?? settlement ?? {};
            const hostShare = Number(s.hostShareCredits ?? s.hostShare ?? 0);
            const serviceFee = Number(s.serviceFeeCredits ?? s.serviceFee ?? 0);
            const refund = Number(s.refundCredits ?? s.refund ?? 0);
            const sum = hostShare + serviceFee + refund;
            log(`     host=${hostShare} fee=${serviceFee} refund=${refund} sum=${sum} deposit=${DEPOSIT}`);
            assert(sum === DEPOSIT, `hostShare + serviceFee + refund === deposit (${sum} === ${DEPOSIT})`);
        }
    }

    finish();
}

function finish() {
    log("\n────────────────────────────────────────");
    log(`  Phase 6 E2E: ${passed} passed, ${failed} failed`);
    log("────────────────────────────────────────");
    process.exit(failed === 0 ? 0 : 1);
}

main().catch((err) => {
    fail(`unexpected error: ${err?.stack || err?.message || err}`);
    finish();
});
