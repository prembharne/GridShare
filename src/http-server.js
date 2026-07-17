import http from "node:http";
import { URL } from "node:url";
import { DomainError, toErrorResponse } from "./core/errors.js";
import { verifyRazorpayWebhook } from "./security/razorpay-webhook.js";

async function readRaw(req, limitBytes) {
  const chunks = [];
  let totalBytes = 0;

  for await (const chunk of req) {
    totalBytes += chunk.length;
    if (totalBytes > limitBytes) {
      throw new DomainError("PAYLOAD_TOO_LARGE", "Request body is too large.", { limitBytes });
    }
    chunks.push(chunk);
  }

  return Buffer.concat(chunks).toString("utf8");
}

function parseJson(rawBody) {
  if (!rawBody) return {};

  try {
    return JSON.parse(rawBody);
  } catch {
    throw new DomainError("INVALID_JSON", "Request body must be valid JSON.");
  }
}

async function readJson(req, limitBytes) {
  return parseJson(await readRaw(req, limitBytes));
}

function sendJson(res, statusCode, body) {
  const payload = JSON.stringify(body, null, 2);
  res.writeHead(statusCode, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(payload)
  });
  res.end(payload);
}

function extractSessionId(pathname, suffix) {
  const match = pathname.match(/^\/sessions\/([^/]+)(?:\/([^/]+))?$/);
  if (!match) return null;
  if (suffix && match[2] !== suffix) return null;
  return decodeURIComponent(match[1]);
}

function statusForError(code) {
  switch (code) {
    case "NOT_FOUND":
      return 404;
    case "PAYLOAD_TOO_LARGE":
      return 413;
    case "WEBHOOK_SIGNATURE_MISSING":
    case "WEBHOOK_SIGNATURE_INVALID":
      return 401;
    case "DEMO_MODE_DISABLED":
    case "UNAUTHORIZED":
      return 403;
    case "INTERNAL_ERROR":
      return 500;
    default:
      return 400;
  }
}

function requireAdmin(req, adminApiKey) {
  if (!adminApiKey) return; // open in dev
  const provided = req.headers["x-admin-key"] ?? req.headers["authorization"]?.replace(/^Bearer\s+/i, "");
  if (provided !== adminApiKey) {
    throw new DomainError("UNAUTHORIZED", "Invalid admin API key.", { code: "UNAUTHORIZED" });
  }
}

export function createHttpServer(app) {
  const bodyLimitBytes = app.config?.requestBodyLimitBytes ?? 1_048_576;
  const adminApiKey = app.config?.adminApiKey ?? "";

  return http.createServer(async (req, res) => {
    const url = new URL(req.url, "http://localhost");

    try {
      if (req.method === "GET" && url.pathname === "/health") {
        return sendJson(res, 200, {
          ok: true,
          data: {
            service: "gridshare-difficult-core",
            status: "ready",
            checks: {
              config: "ok",
              store: "in-memory",
              chainAdapter: "mock",
              hardwareAdapter: "mock"
            }
          }
        });
      }

      if (req.method === "GET" && url.pathname === "/events") {
        return sendJson(res, 200, {
          ok: true,
          data: {
            events: app.eventBus.list({
              sinceId: url.searchParams.get("sinceId") ?? 0,
              type: url.searchParams.get("type") ?? undefined
            })
          }
        });
      }

      if (req.method === "GET" && url.pathname === "/events/stream") {
        res.writeHead(200, {
          "content-type": "text/event-stream; charset=utf-8",
          "cache-control": "no-cache",
          connection: "keep-alive"
        });

        for (const event of app.eventBus.list()) {
          res.write(`id: ${event.id}\nevent: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
        }

        const unsubscribe = app.eventBus.subscribe((event) => {
          res.write(`id: ${event.id}\nevent: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`);
        });

        req.on("close", unsubscribe);
        return;
      }

      if (req.method === "POST" && url.pathname === "/demo/judge-flow") {
        const body = await readJson(req, bodyLimitBytes);
        const data = await app.demo.run(body);
        return sendJson(res, 200, { ok: true, data });
      }

      // ============================ WALLET ============================

      if (req.method === "POST" && url.pathname === "/wallet/topup") {
        const body = await readJson(req, bodyLimitBytes);
        const order = await app.paymentAdapter?.createOrder({
          amountPaise: body.amountCredits * 100, // convert credits to paise for Razorpay
          receipt: `topup_${body.userId}_${Date.now()}`,
          notes: { user_id: body.userId }
        });
        return sendJson(res, 200, { ok: true, data: order });
      }

      if (req.method === "GET" && url.pathname.startsWith("/wallet/") && url.pathname.endsWith("/balance")) {
        const userId = url.pathname.split("/")[2];
        const data = await app.saga.getWalletBalance(userId);
        return sendJson(res, 200, { ok: true, data });
      }

      // ============================ ADMIN OFF-RAMP ============================

      if (req.method === "GET" && url.pathname === "/admin/hosts/earnings") {
        requireAdmin(req, adminApiKey);
        const hosts = await app.store.listHosts?.() ?? [];
        const earnings = [];
        for (const host of hosts) {
          const e = await app.saga.getHostEarnings(host.id);
          earnings.push({ hostId: host.id, earnedCredits: e.earnedCredits });
        }
        return sendJson(res, 200, { ok: true, data: earnings });
      }

      if (req.method === "POST" && url.pathname.startsWith("/admin/hosts/") && url.pathname.endsWith("/payout")) {
        requireAdmin(req, adminApiKey);
        const hostId = url.pathname.split("/")[3];
        const body = await readJson(req, bodyLimitBytes);
        const data = await app.saga.createHostPayout({ hostId, credits: body.credits, method: body.method ?? "upi" });
        return sendJson(res, 200, { ok: true, data });
      }

      if (req.method === "POST" && url.pathname.startsWith("/admin/payouts/") && url.pathname.endsWith("/confirm")) {
        requireAdmin(req, adminApiKey);
        const payoutId = url.pathname.split("/")[3];
        const body = await readJson(req, bodyLimitBytes);
        const data = await app.saga.redeemHostCredits({ hostId: body.hostId, amountCredits: body.amountCredits, payoutId, reference: body.reference });
        return sendJson(res, 200, { ok: true, data });
      }

      // ============================ SESSIONS ============================

      if (req.method === "POST" && url.pathname === "/sessions/intent") {
        const body = await readJson(req, bodyLimitBytes);
        const data = await app.saga.createIntent(body);
        return sendJson(res, 201, { ok: true, data });
      }

      if (req.method === "POST" && url.pathname.startsWith("/sessions/") && url.pathname.endsWith("/start")) {
        const sessionId = url.pathname.split("/")[2];
        const body = await readJson(req, bodyLimitBytes);
        const data = await app.saga.startSession({ sessionId, idempotencyKey: body.idempotencyKey });
        return sendJson(res, 200, { ok: true, data });
      }

      if (req.method === "POST" && url.pathname === "/payments/webhook/razorpay") {
        const rawBody = await readRaw(req, bodyLimitBytes);
        verifyRazorpayWebhook({
          rawBody,
          signature: req.headers["x-razorpay-signature"],
          secret: app.config?.razorpayWebhookSecret
        });

        const body = parseJson(rawBody);
        // Route based on notes: session_id -> legacy flow; user_id -> wallet top-up
        if (body.payment?.entity?.notes?.user_id) {
          const data = await app.saga.topUpWallet({
            userId: body.payment.entity.notes.user_id,
            amountCredits: Math.floor(body.payment.entity.amount / 100),
            paymentId: body.payment.entity.id,
            idempotencyKey: body.idempotencyKey ?? req.headers["idempotency-key"]
          });
          return sendJson(res, 200, { ok: true, data });
        }
        const data = await app.saga.handlePaymentCaptured({
          ...body,
          idempotencyKey: body.idempotencyKey ?? req.headers["idempotency-key"]
        });
        return sendJson(res, 200, { ok: true, data });
      }

      if (req.method === "POST" && url.pathname === "/iot/webhook/tuya") {
        if (!app.hardware?.handleTelemetryWebhook) {
          return sendJson(res, 501, {
            ok: false,
            error: { code: "NOT_IMPLEMENTED", message: "Tuya webhook not available in mock mode." }
          });
        }
        const rawBody = await readRaw(req, bodyLimitBytes);
        const body = parseJson(rawBody);
        const signature = req.headers["x-tuya-signature"] ?? req.headers["tuya-signature"];
        const telemetry = await app.hardware.handleTelemetryWebhook(body, signature);
        return sendJson(res, 200, { ok: true, data: telemetry });
      }

      const telemetrySessionId = extractSessionId(url.pathname, "telemetry");
      if (req.method === "POST" && telemetrySessionId) {
        const body = await readJson(req, bodyLimitBytes);
        const data = await app.saga.ingestTelemetry(telemetrySessionId, body);
        return sendJson(res, 200, { ok: true, data });
      }

      const stopSessionId = extractSessionId(url.pathname, "stop");
      if (req.method === "POST" && stopSessionId) {
        const body = await readJson(req, bodyLimitBytes);
        const data = await app.saga.stopSession({
          sessionId: stopSessionId,
          reason: body.reason,
          idempotencyKey: body.idempotencyKey ?? req.headers["idempotency-key"]
        });
        return sendJson(res, 200, { ok: true, data });
      }

      const reconcileSessionId = extractSessionId(url.pathname, "reconcile");
      if (req.method === "POST" && reconcileSessionId) {
        const data = await app.saga.reconcileSession(reconcileSessionId);
        return sendJson(res, 200, { ok: true, data });
      }

      if (req.method === "POST" && url.pathname === "/reconcile") {
        const data = await app.saga.reconcileAll();
        return sendJson(res, 200, { ok: true, data });
      }

      const auditSessionId = extractSessionId(url.pathname, "audit");
      if (req.method === "GET" && auditSessionId) {
        const data = await app.saga.getSessionAudit(auditSessionId);
        return sendJson(res, 200, { ok: true, data });
      }

      const getSessionId = extractSessionId(url.pathname);
      if (req.method === "GET" && getSessionId) {
        const data = await app.saga.getSession(getSessionId);
        return sendJson(res, 200, { ok: true, data });
      }

      return sendJson(res, 404, {
        ok: false,
        error: {
          code: "NOT_FOUND",
          message: "Route not found."
        }
      });
    } catch (error) {
      const response = toErrorResponse(error);
      return sendJson(res, statusForError(response.error.code), response);
    }
  });
}