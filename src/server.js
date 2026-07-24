import { loadEnv } from "./core/load-env.js";

// Load .env before anything reads process.env (loadConfig in app.js does so at
// import/instantiation time). Env vars already set by the runtime take priority.
const envResult = loadEnv();

import { createApp } from "./app.js";
import { createHttpServer } from "./http-server.js";
import { seedOutletCatalog } from "./domain/outlet-catalog.js";

const app = createApp();

// When persistence is on, seed the demo outlets (and their host users) so
// sessions can satisfy their foreign keys. Idempotent; safe on every boot.
if (app.config.persist) {
  try {
    const { seeded } = await seedOutletCatalog({ store: app.store, users: app.users });
    console.log(`Seeded ${seeded} outlet(s) into persistent store.`);
  } catch (error) {
    console.error("Outlet catalog seed failed:", error.message);
  }
}

// Start the Stellar USDC deposit watcher when the optional USDC on-ramp is
// enabled. Non-fatal: a watcher failure must not stop the HTTP server from
// serving UPI top-ups and the rest of the app.
if (app.startUsdcWatcher) {
  Promise.resolve()
    .then(() => app.startUsdcWatcher())
    .then(() => console.log("  USDC watcher: streaming Horizon payments"))
    .catch((error) => console.error("USDC watcher failed to start:", error.message));
}

const server = createHttpServer(app);

server.listen(app.config.port, () => {
  console.log(`GridShare difficult core listening on http://localhost:${app.config.port}`);
  console.log(`  persistence: ${app.config.persist ? "postgres" : "in-memory"} | real adapters: ${app.config.useRealAdapters}`);
  if (app.config.usdcEnabled) {
    console.log(`  USDC on-ramp: enabled (testnet) | receive ${app.config.usdcReceivePublic || "(unset)"}`);
  }
  if (envResult.loaded) {
    console.log(`  loaded ${envResult.count} var(s) from ${envResult.path}`);
  }
});
