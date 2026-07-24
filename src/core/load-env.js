import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

// Loads a .env file into process.env at startup, if one exists.
//
// Why this exists: the app reads process.env (via loadConfig) the moment
// createApp is called, and PrismaClient historically loaded .env as an import
// side-effect. That coupling is fragile (order-dependent, and dropped in newer
// Prisma). Loading .env explicitly here makes DATABASE_URL and the real-adapter
// credentials available regardless of import order.
//
// Precedence: variables already present in process.env win. This keeps
// container/production env injection (Docker, systemd, CI secrets) authoritative
// over any committed-adjacent .env file.
export function loadEnv(envPath) {
  const target = envPath ?? path.resolve(process.cwd(), ".env");

  if (!fs.existsSync(target)) {
    return { loaded: false, path: target };
  }

  // Node >= 20.12 / 24 ships a native loader, but it OVERRIDES existing env
  // vars, which we don't want. So we always parse manually for predictable
  // precedence.
  const contents = fs.readFileSync(target, "utf8");
  let count = 0;

  for (const rawLine of contents.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;

    const eq = line.indexOf("=");
    if (eq === -1) continue;

    const key = line.slice(0, eq).trim();
    if (!key) continue;

    let value = line.slice(eq + 1).trim();
    // Strip a single layer of matching surrounding quotes.
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    if (process.env[key] === undefined) {
      process.env[key] = value;
      count += 1;
    }
  }

  return { loaded: true, path: target, count };
}

// Convenience for `import "./core/load-env.js"` at the top of an entrypoint.
if (import.meta.url === `file://${process.argv[1]}` || fileURLToPath(import.meta.url) === process.argv[1]) {
  loadEnv();
}
