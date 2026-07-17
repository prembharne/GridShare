import fs from "node:fs";

const requiredFiles = [
  "migrations/001_initial_schema.sql",
  "docker-compose.yml",
  "ops/local_stack.md",
  "ops/security_checklist.md",
  "docs/inputs_needed.md",
  "docs/production_readiness.md",
  "docs/demo_runbook.md",
  "docs/frontend_handoff.md",
  "docs/integration_contract.md",
  "markdown_files/INDEX.md",
  "markdown_files/root/README.md",
  "markdown_files/root/gridshare_masterplan.md",
  "markdown_files/root/gridshare_difficulty_split.md"
];

const requiredSqlTerms = [
  "CREATE EXTENSION IF NOT EXISTS postgis",
  "CREATE EXTENSION IF NOT EXISTS timescaledb",
  "CREATE TABLE IF NOT EXISTS sessions",
  "CREATE TABLE IF NOT EXISTS idempotency_keys",
  "CREATE TABLE IF NOT EXISTS telemetry_samples",
  "CREATE TABLE IF NOT EXISTS outbox_events",
  "CREATE TABLE IF NOT EXISTS reconciliation_runs",
  "sessions_reconcile_idx"
];

const requiredContractTerms = [
  "POST /sessions/{sessionId}/reconcile",
  "POST /reconcile",
  "GET /sessions/{sessionId}/audit",
  "POST /demo/judge-flow",
  "x-razorpay-signature"
];

const requiredBundleTerms = [
  "docs/frontend_handoff.md",
  "docs/demo_runbook.md",
  "gridshare_masterplan.md",
  "README.md"
];

function fail(message) {
  console.error(message);
  process.exitCode = 1;
}

for (const file of requiredFiles) {
  if (!fs.existsSync(file)) {
    fail(`Missing required production artifact: ${file}`);
  }
}

if (process.exitCode) {
  process.exit();
}

const schema = fs.readFileSync("migrations/001_initial_schema.sql", "utf8");
for (const term of requiredSqlTerms) {
  if (!schema.includes(term)) {
    fail(`Schema missing required term: ${term}`);
  }
}

const contract = fs.readFileSync("docs/integration_contract.md", "utf8");
for (const term of requiredContractTerms) {
  if (!contract.includes(term)) {
    fail(`Integration contract missing required term: ${term}`);
  }
}

const bundleIndex = fs.readFileSync("markdown_files/INDEX.md", "utf8");
for (const term of requiredBundleTerms) {
  if (!bundleIndex.includes(term)) {
    fail(`Markdown bundle index missing required term: ${term}`);
  }
}

if (!process.exitCode) {
  console.log("Production artifacts check passed.");
}
