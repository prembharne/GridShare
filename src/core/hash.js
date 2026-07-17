import crypto from "node:crypto";

export function stableStringify(value) {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }

  if (Array.isArray(value)) {
    return `[${value.map((item) => stableStringify(item)).join(",")}]`;
  }

  return `{${Object.keys(value)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${stableStringify(value[key])}`)
    .join(",")}}`;
}

export function hashPayload(value) {
  return crypto.createHash("sha256").update(stableStringify(value)).digest("hex");
}

export function fakeTxHash(prefix, payload) {
  const digest = hashPayload({ prefix, payload, nonce: crypto.randomUUID() });
  return `${prefix}_${digest.slice(0, 24)}`;
}
