import http from "node:http";
import { URL } from "node:url";
import { DomainError, invariant, toErrorResponse } from "./core/errors.js";
import { verifyRazorpayWebhook, verifyRazorpaySignature } from "./security/razorpay-webhook.js";
import { OUTLET_CATALOG, toNearbyPayload, findOutlet } from "./domain/outlet-catalog.js";


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
    // Global CORS Configuration
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, x-admin-key, x-razorpay-signature");

    if (req.method === "OPTIONS") {
      res.writeHead(200);
      res.end();
      return;
    }

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

      if (req.method === "POST" && url.pathname === "/api/auth/send-otp") {
        const body = await readJson(req, bodyLimitBytes);
        console.log(`[HTTP] POST /api/auth/send-otp -> phone: "${body.phone}"`);
        const result = await app.otp.requestOtp(body.phone);
        return sendJson(res, 200, {
          otpSent: true,
          message: result.viaSms ? "OTP sent via SMS." : "OTP generated (dev mode).",
          expiresInSeconds: result.expiresInSeconds,
          // Present only when SMS is not configured (dev fallback).
          ...(result.devCode ? { devCode: result.devCode } : {})
        });
      }

      if (req.method === "POST" && url.pathname === "/api/auth/verify-otp") {
        const body = await readJson(req, bodyLimitBytes);

        // Real verification: the code must match the one issued for this phone.
        app.otp.verifyOtp(body.phone, body.otp);

        // On success, persist a real user keyed by phone so the same phone always
        // resolves to the same account (and the admin dashboard sees who signed in).
        const role = body.role === "host" ? "host" : "rider";
        const user = await app.users.upsertUser({
          phoneE164: body.phone,
          role,
          displayName: body.name ?? null
        });

        const balance = await app.saga.getWalletBalance(user.id).catch(() => ({ balanceCredits: 0 }));

        return sendJson(res, 200, {
          accessToken: "mock_jwt_token_for_" + user.id,
          refreshToken: "mock_refresh_token_for_" + user.id,
          user: {
            id: user.id,
            name: user.displayName ?? "Rider",
            phone: user.phoneE164 ?? body.phone,
            role: user.role,
            walletBalanceCredits: balance.balanceCredits ?? 0
          }
        });
      }

      if (req.method === "POST" && url.pathname === "/api/auth/clerk/exchange") {
        const body = await readJson(req, bodyLimitBytes);
        const role = body.role === "host" ? "host" : "rider";
        const user = await app.users.upsertUser({
          id: body.userId || undefined,
          phoneE164: body.phone ?? null,
          role,
          displayName: body.name ?? null
        });

        const balance = await app.saga.getWalletBalance(user.id).catch(() => ({ balanceCredits: 0 }));

        return sendJson(res, 200, {
          accessToken: "mock_jwt_token_for_" + user.id,
          refreshToken: "mock_refresh_token_for_" + user.id,
          user: {
            id: user.id,
            name: user.displayName ?? body.name ?? "Rider",
            phone: user.phoneE164 ?? body.phone ?? null,
            role: user.role,
            walletBalanceCredits: balance.balanceCredits ?? 0
          }
        });
      }

      if (req.method === "POST" && url.pathname === "/api/auth/google") {
        const body = await readJson(req, bodyLimitBytes);
        const { googleId, email, name } = body;
        const user = await app.users.upsertUser({
          id: googleId ? `google_${googleId}` : undefined,
          phoneE164: email ?? null,
          role: "rider",
          displayName: name ?? email ?? "Google User"
        });

        const balance = await app.saga.getWalletBalance(user.id).catch(() => ({ balanceCredits: 0 }));

        return sendJson(res, 200, {
          accessToken: "jwt_token_google_" + user.id,
          refreshToken: "refresh_token_google_" + user.id,
          user: {
            id: user.id,
            name: user.displayName ?? "Google User",
            phone: user.phoneE164 ?? "",
            role: user.role,
            walletBalanceCredits: balance.balanceCredits ?? 0
          }
        });
      }

      if (req.method === "GET" && url.pathname === "/outlets/nearby") {
        console.log(`[MOCK API] Fetching nearby outlets`);
        return sendJson(res, 200, {
          ok: true,
          outlets: OUTLET_CATALOG.map(toNearbyPayload)
        });
      }

      // Live per-outlet telemetry snapshot (switch state, power, current,
      // voltage, energy) for the rider/host dashboards. Routes to the outlet's
      // own Tuya device via the hardware bridge; works in mock mode too.
      const liveOutletMatch = url.pathname.match(/^\/outlets\/([^/]+)\/live$/);
      if (req.method === "GET" && liveOutletMatch) {
        const outletId = decodeURIComponent(liveOutletMatch[1]);
        const outlet = findOutlet(outletId);
        invariant(outlet, "OUTLET_NOT_FOUND", "Outlet was not found.");
        if (typeof app.hardware?.getLiveStatus !== "function") {
          return sendJson(res, 501, {
            ok: false,
            error: { code: "NOT_IMPLEMENTED", message: "Live status not available for this hardware bridge." }
          });
        }
        const live = await app.hardware.getLiveStatus(outletId);
        return sendJson(res, 200, {
          ok: true,
          data: { outlet: toNearbyPayload(outlet), live }
        });
      }


      if (req.method === "POST" && url.pathname === "/outlets") {
        const body = await readJson(req, bodyLimitBytes);
        invariant(body.name, "INVALID_NAME", "Device name is required.");
        invariant(body.providerDeviceId, "INVALID_DEVICE", "Tuya Device ID is required.");

        const newOutlet = {
          id: `outlet_${Date.now()}`,
          name: body.name,
          host_name: body.hostName ?? "Host Prosumer",
          hostId: body.hostId ?? "host_1",
          providerDeviceId: body.providerDeviceId,
          lat: Number(body.lat ?? 19.0760),
          lng: Number(body.lng ?? 72.8777),
          distance_km: 0.1,
          rate_per_kwh: Number(body.ratePerKwh ?? 12.5),
          available: true,
          connector_type: body.connectorType ?? "16A Socket",
          rating: 5.0,
          address: body.address ?? "Host Registered Station"
        };

        OUTLET_CATALOG.push(newOutlet);
        console.log(`[HOST API] Registered new IoT Smart Plug outlet: ${newOutlet.name} (${newOutlet.providerDeviceId})`);
        return sendJson(res, 201, { ok: true, data: { outlet: toNearbyPayload(newOutlet) } });
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

      if (req.method === "POST" && url.pathname === "/wallet/topup/instamojo") {
        const body = await readJson(req, bodyLimitBytes);
        invariant(body.userId, "INVALID_USER", "userId is required.");
        const amountCredits = Math.floor(Number(body.amountCredits));
        invariant(Number.isInteger(amountCredits) && amountCredits > 0, "INVALID_AMOUNT", "amountCredits must be > 0.");

        const result = await app.instamojoAdapter.createPaymentRequest({
          userId: body.userId,
          amountCredits,
          phone: body.phone ?? "",
          name: body.name ?? "GridShare Rider",
          email: body.email ?? ""
        });

        return sendJson(res, 200, {
          ok: true,
          data: {
            paymentUrl: result.paymentUrl,
            requestId: result.requestId,
            amountCredits
          }
        });
      }

      if (req.method === "POST" && url.pathname === "/wallet/topup/instamojo/verify") {
        const body = await readJson(req, bodyLimitBytes);
        const { paymentRequestId, paymentId, userId, amountCredits } = body;

        const result = await app.instamojoAdapter.verifyPayment(paymentRequestId, paymentId);
        if (result.paid) {
          const creditsToMint = amountCredits ?? Math.floor(result.amount);
          await app.saga.topUpWallet({
            userId: userId ?? "user_1",
            amountCredits: creditsToMint,
            paymentId,
            source: "instamojo_upi"
          });
          const balance = await app.saga.getWalletBalance(userId ?? "user_1");
          return sendJson(res, 200, {
            ok: true,
            data: { verified: true, balanceCredits: balance.balanceCredits }
          });
        } else {
          throw new DomainError("VERIFICATION_FAILED", "Instamojo payment verification failed.");
        }
      }

      if (req.method === "GET" && url.pathname === "/wallet/topup/instamojo/redirect") {
        const paymentId = url.searchParams.get("payment_id");
        const paymentRequestId = url.searchParams.get("payment_request_id");
        const paymentStatus = url.searchParams.get("payment_status");

        const html = `<!DOCTYPE html>
<html>
<head><title>GridShare Payment</title><meta name="viewport" content="width=device-width, initial-scale=1"></head>
<body style="font-family:sans-serif; text-align:center; padding:40px; background:#0B132B; color:#fff;">
  <h2 style="color:#00F5D4;">Payment ${paymentStatus === 'Credit' ? 'Successful!' : 'Processing'}</h2>
  <p>Status: ${paymentStatus}</p>
  <p>Payment ID: ${paymentId}</p>
  <p>Request ID: ${paymentRequestId}</p>
  <p style="margin-top:30px; color:#A0AEC0;">You can close this window and return to the GridShare app.</p>
</body>
</html>`;
        res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
        res.end(html);
        return;
      }

      if (req.method === "POST" && url.pathname === "/wallet/topup") {
        const body = await readJson(req, bodyLimitBytes);
        const amountCredits = Math.floor(Number(body.amountCredits));
        invariant(Number.isInteger(amountCredits) && amountCredits > 0, "INVALID_AMOUNT", "amountCredits must be a positive integer.");
        const order = await app.paymentAdapter?.createOrder({
          amountPaise: amountCredits * 100, // 1 credit = INR 1 -> paise for Razorpay
          receipt: `topup_${body.userId}_${Date.now()}`,
          notes: { user_id: body.userId }
        });
        // Shape the response to exactly what mobile Razorpay Checkout needs:
        // { orderId, amountCredits, currency, keyId }. keyId is the PUBLIC key
        // (safe to expose); the secret is never sent to the client.
        return sendJson(res, 200, {
          ok: true,
          data: {
            orderId: order.id,
            amountCredits,
            currency: order.currency ?? "INR",
            keyId: app.config?.razorpayKeyId ?? ""
          }
        });
      }

      if (req.method === "POST" && url.pathname === "/wallet/topup/verify") {
        const body = await readJson(req, bodyLimitBytes);
        const { razorpay_order_id, razorpay_payment_id, razorpay_signature, userId } = body;

        const isValid = verifyRazorpaySignature(
          razorpay_order_id,
          razorpay_payment_id,
          razorpay_signature,
          app.config?.razorpayKeySecret
        );

        if (!isValid) {
          throw new DomainError("VERIFICATION_FAILED", "Signature mismatch");
        }

        // Signature is authentic -> the payment genuinely happened on Razorpay.
        // Mint credits NOW. Previously this endpoint verified the signature but
        // never called topUpWallet, so it returned { verified:true } without
        // ever crediting the wallet. That is why "money went but no credits
        // appeared" on the Razorpay path. Amount is taken authoritatively from
        // Razorpay (re-fetch the payment) rather than trusting the client.
        let amountCredits = Math.floor(Number(body.amountCredits ?? 0));
        try {
          const payment = await app.paymentAdapter?.getPayment?.(razorpay_payment_id);
          if (payment?.amount) amountCredits = Math.floor(payment.amount / 100);
        } catch {
          // Fall back to client-supplied amountCredits if the fetch fails.
        }
        invariant(amountCredits > 0, "INVALID_AMOUNT", "Could not determine a positive credit amount for this payment.");

        // paymentId = Razorpay payment id -> idempotent: replaying this verify
        // (or a later webhook for the same payment) will not double-credit.
        await app.saga.topUpWallet({
          userId: userId ?? "user_1",
          amountCredits,
          paymentId: razorpay_payment_id,
          source: "razorpay_upi"
        });

        const balance = await app.saga
          .getWalletBalance(userId ?? "user_1")
          .catch(() => ({ balanceCredits: null }));
        return sendJson(res, 200, {
          ok: true,
          data: { verified: true, amountCredits, balanceCredits: balance.balanceCredits }
        });
      }


      if (req.method === "GET" && url.pathname.startsWith("/wallet/") && url.pathname.endsWith("/balance")) {
        const userId = url.pathname.split("/")[2];
        const data = await app.saga.getWalletBalance(userId);
        return sendJson(res, 200, { ok: true, data });
      }

      // ── Source ledger: UPI vs USDC funding provenance ──
      // Used by mobile host earnings screen to show separate UPI / USDC buckets.
      if (req.method === "GET" && url.pathname.startsWith("/wallet/") && url.pathname.endsWith("/source-ledger")) {
        const userId = url.pathname.split("/")[2];
        const data = await app.store.getSourceLedger(userId);
        return sendJson(res, 200, { ok: true, data });
      }

      // ── Live USD→INR exchange rate (for USDC top-up quoting) ──
      if (req.method === "GET" && url.pathname === "/fx/usd-inr") {
        const data = await app.fxRate.getUsdInr();
        return sendJson(res, 200, { ok: true, data });
      }

      // ── USDC top-up: create a deposit intent (address + memo + QR) ──
      // Quotes credits at the live USD→INR rate and LOCKS that rate into the
      // intent, so what the rider sees is exactly what gets minted.
      if (req.method === "POST" && url.pathname === "/wallet/topup/usdc") {
        if (!app.usdcAdapter) {
          throw new DomainError("USDC_DISABLED", "USDC top-up is not enabled on this server.");
        }
        const body = await readJson(req, bodyLimitBytes);
        invariant(body.userId, "INVALID_USER", "userId is required.");
        const amountCredits = Math.floor(Number(body.amountCredits));
        invariant(Number.isInteger(amountCredits) && amountCredits > 0, "INVALID_AMOUNT", "amountCredits must be a positive integer.");
        const asset = String(body.asset ?? body.assetCode ?? "USDC").toUpperCase() === "XLM" ? "XLM" : "USDC";

        const { rate } = await app.fxRate.getUsdInr();
        // Testnet XLM support uses the same quote pipeline; production should
        // replace this with a real XLM/INR quote before enabling mainnet XLM.
        const expectedUsdc = Math.ceil((amountCredits / rate) * 1e7) / 1e7; // round up to stroop
        const intent = app.usdcAdapter.buildIntent({ amountCredits, expectedUsdc, asset });

        await app.store.createUsdcIntent({
          memo: intent.memo,
          userId: body.userId,
          amountCredits,
          expectedUsdc,
          assetCode: intent.assetCode,
          assetType: intent.assetType,
          lockedRate: rate,
          status: "pending",
          expiresAt: new Date(Date.now() + app.config.usdcIntentTtlSeconds * 1000).toISOString()
        });

        return sendJson(res, 200, {
          ok: true,
          data: {
            memo: intent.memo,
            depositAddress: intent.depositAddress,
            assetCode: intent.assetCode,
            assetIssuer: intent.assetIssuer,
            assetType: intent.assetType,
            expectedUsdc,
            amountCredits,
            lockedRate: rate,
            qrUri: intent.qrUri,
            expiresInSeconds: app.config.usdcIntentTtlSeconds
          }
        });
      }

      // ── USDC top-up: verify/confirm intent manually or after payment ──
      if (req.method === "POST" && url.pathname.startsWith("/wallet/topup/usdc/") && url.pathname.endsWith("/verify")) {
        const parts = url.pathname.split("/");
        const memo = decodeURIComponent(parts[4] ?? "");
        let intent = await app.store.getUsdcIntentByMemo(memo);
        if (!intent) {
          throw new DomainError("USDC_INTENT_NOT_FOUND", "No USDC intent for this memo.", { memo });
        }

        if (intent.status === "pending") {
          const payment = app.usdcAdapter ? await app.usdcAdapter.checkRecentPayments({ memo, asset: intent.assetCode }) : null;
          if (!payment) {
            return sendJson(res, 200, {
              ok: true,
              data: {
                memo: intent.memo,
                status: intent.status,
                amountCredits: intent.amountCredits,
                expectedUsdc: intent.expectedUsdc,
                assetCode: intent.assetCode ?? "USDC",
                txHash: intent.txHash,
                pendingVerification: true
              }
            });
          }

          if (payment.amountUsdc + 1e-7 < intent.expectedUsdc) {
            return sendJson(res, 200, {
              ok: true,
              data: {
                memo: intent.memo,
                status: intent.status,
                amountCredits: intent.amountCredits,
                expectedUsdc: intent.expectedUsdc,
                assetCode: intent.assetCode ?? "USDC",
                txHash: intent.txHash,
                underpaid: true,
                receivedAmount: payment.amountUsdc
              }
            });
          }

          // Use memo+txHash as idempotency key so different intents paying
          // to the same deposit address never conflict.
          const intentPaymentId = `${memo}:${payment.txHash}`;
          app.config?.logger?.info?.(`[usdc:verify] minting ${intent.amountCredits} credits → userId=${intent.userId} tx=${payment.txHash} paymentId=${intentPaymentId}`);
          await app.saga.topUpWallet({
            userId: intent.userId,
            amountCredits: intent.amountCredits,
            paymentId: intentPaymentId,
            source: "usdc"
          });
          await app.store.updateUsdcIntent(memo, { status: "confirmed", txHash: payment.txHash, paidAssetCode: payment.assetCode });
          intent = await app.store.getUsdcIntentByMemo(memo);
        }

        return sendJson(res, 200, {
          ok: true,
          data: {
            memo: intent.memo,
            status: intent.status,
            amountCredits: intent.amountCredits,
            expectedUsdc: intent.expectedUsdc,
            assetCode: intent.assetCode ?? "USDC",
            txHash: intent.txHash
          }
        });
      }

      // ── USDC top-up: poll intent status ──
      if (req.method === "GET" && url.pathname.startsWith("/wallet/topup/usdc/")) {
        const memo = decodeURIComponent(url.pathname.split("/")[4] ?? "");
        invariant(memo, "INVALID_MEMO", "memo is required.");
        let intent = await app.store.getUsdcIntentByMemo(memo);
        if (!intent) {
          throw new DomainError("USDC_INTENT_NOT_FOUND", "No USDC intent for this memo.", { memo });
        }

        // Active verification if intent is still pending
        if (intent.status === "pending" && app.usdcAdapter) {
          const payment = await app.usdcAdapter.checkRecentPayments({ memo, asset: intent.assetCode });
          if (payment) {
            if (payment.amountUsdc + 1e-7 >= intent.expectedUsdc) {
              await app.saga.topUpWallet({
                userId: intent.userId,
                amountCredits: intent.amountCredits,
                paymentId: payment.txHash,
                source: "usdc"
              });
              await app.store.updateUsdcIntent(memo, { status: "confirmed", txHash: payment.txHash, paidAssetCode: payment.assetCode });
              intent = await app.store.getUsdcIntentByMemo(memo);
            }
          }
        }

        return sendJson(res, 200, {
          ok: true,
          data: {
            memo: intent.memo,
            status: intent.status,       // pending | confirmed | expired
            amountCredits: intent.amountCredits,
            expectedUsdc: intent.expectedUsdc,
            assetCode: intent.assetCode ?? "USDC",
            txHash: intent.txHash
          }
        });
      }


      // ============================ ADMIN ============================

      // Overview metrics: total users/hosts/riders, active sessions, credits in circulation.
      if (req.method === "GET" && url.pathname === "/admin/overview") {
        requireAdmin(req, adminApiKey);
        const counts = await app.users.countByRole();
        const sessions = await app.store.listSessions();
        const activeStatuses = new Set(["created", "active", "lock_failed", "stopping"]);
        const activeSessions = sessions.filter((s) => activeStatuses.has(s.status)).length;
        let creditsInCirculation = null;
        try {
          creditsInCirculation = await app.chain.totalSupply();
        } catch {
          creditsInCirculation = null;
        }
        return sendJson(res, 200, {
          ok: true,
          data: {
            totalUsers: counts.total,
            riders: counts.rider,
            hosts: counts.host,
            admins: counts.admin,
            totalSessions: sessions.length,
            activeSessions,
            creditsInCirculation
          }
        });
      }

      // Users directory: every registered user with wallet balance + session count.
      if (req.method === "GET" && url.pathname === "/admin/users") {
        requireAdmin(req, adminApiKey);
        const roleFilter = url.searchParams.get("role") ?? undefined;
        const users = await app.users.listUsers({ role: roleFilter });
        const sessions = await app.store.listSessions();
        const sessionCount = new Map();
        for (const s of sessions) {
          sessionCount.set(s.riderId, (sessionCount.get(s.riderId) ?? 0) + 1);
        }
        const rows = [];
        for (const u of users) {
          const balance = await app.saga.getWalletBalance(u.id).catch(() => ({ balanceCredits: 0 }));
          rows.push({
            id: u.id,
            name: u.displayName,
            phone: u.phoneE164,
            role: u.role,
            balanceCredits: balance.balanceCredits ?? 0,
            sessionCount: sessionCount.get(u.id) ?? 0,
            joinedAt: u.createdAt
          });
        }
        return sendJson(res, 200, { ok: true, data: rows });
      }

      // Hosts directory: hosts with earned credits + hosted-session count.
      if (req.method === "GET" && url.pathname === "/admin/hosts") {
        requireAdmin(req, adminApiKey);
        const hosts = await app.users.listHosts();
        const sessions = await app.store.listSessions();
        const hostedCount = new Map();
        for (const s of sessions) {
          hostedCount.set(s.hostId, (hostedCount.get(s.hostId) ?? 0) + 1);
        }
        const rows = [];
        for (const host of hosts) {
          const e = await app.saga.getHostEarnings(host.id).catch(() => ({ earnedCredits: 0 }));
          rows.push({
            id: host.id,
            name: host.displayName,
            phone: host.phoneE164,
            earnedCredits: e.earnedCredits ?? 0,
            hostedSessions: hostedCount.get(host.id) ?? 0,
            joinedAt: host.createdAt
          });
        }
        return sendJson(res, 200, { ok: true, data: rows });
      }

      // Sessions / activity feed across all users.
      if (req.method === "GET" && url.pathname === "/admin/sessions") {
        requireAdmin(req, adminApiKey);
        const statusesParam = url.searchParams.get("status");
        const statuses = statusesParam ? statusesParam.split(",") : undefined;
        const sessions = await app.store.listSessions({ statuses });
        const rows = sessions
          .map((s) => ({
            id: s.id,
            riderId: s.riderId,
            hostId: s.hostId,
            outletId: s.outletId,
            status: s.status,
            depositCredits: s.depositCredits,
            settlement: s.settlement ?? null,
            stopReason: s.stopReason ?? null,
            createdAt: s.createdAt,
            updatedAt: s.updatedAt
          }))
          .sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
        return sendJson(res, 200, { ok: true, data: rows });
      }

      // ============================ ADMIN OFF-RAMP ============================

      // Legacy shape kept for the existing dashboard: [{ hostId, earnedCredits }].
      if (req.method === "GET" && url.pathname === "/admin/hosts/earnings") {
        requireAdmin(req, adminApiKey);
        const hosts = await app.users.listHosts();
        const earnings = [];
        for (const host of hosts) {
          const e = await app.saga.getHostEarnings(host.id).catch(() => ({ earnedCredits: 0 }));
          earnings.push({
            hostId: host.id,
            name: host.displayName,
            phone: host.phoneE164,
            earnedCredits: e.earnedCredits ?? 0
          });
        }
        return sendJson(res, 200, { ok: true, data: earnings });
      }

      if (req.method === "POST" && url.pathname.startsWith("/admin/hosts/") && url.pathname.endsWith("/payout")) {
        requireAdmin(req, adminApiKey);
        const hostId = url.pathname.split("/")[3];
        const body = await readJson(req, bodyLimitBytes);
        const credits = body.credits;
        // createHostPayout lives on the store (records a pending off-ramp), not
        // the saga. Credits are 1:1 INR.
        const data = await app.store.createHostPayout({
          hostId,
          credits,
          inrAmount: credits,
          method: body.method ?? "upi"
        });
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
        // Register the parties BEFORE creating the session. When persistence is
        // on, sessions have a foreign key to users, so the rider/host rows must
        // exist first. This also ensures the admin dashboard sees hosts (and any
        // rider that reached the app via a path other than OTP login).
        if (body.hostId) {
          await app.users.upsertUser({ id: body.hostId, role: "host" }).catch(() => { });
        }
        if (body.riderId) {
          await app.users.upsertUser({ id: body.riderId, role: "rider" }).catch(() => { });
        }
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