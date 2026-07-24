import { deriveUserId } from "./prisma-user-repository.js";

function clone(value) {
  return value === undefined ? value : JSON.parse(JSON.stringify(value));
}

/**
 * In-memory registry of users, used when DATABASE_URL is not configured (the
 * default demo/test path). API-compatible with PrismaUserRepository so the
 * admin endpoints behave identically regardless of backing store.
 */
export class InMemoryUserRepository {
  constructor() {
    this.users = new Map(); // id -> user record
  }

  async upsertUser({ id, phoneE164 = null, role = "rider", displayName = null }) {
    const userId = id ?? deriveUserId(role, phoneE164);
    const existing = this.users.get(userId);
    const nowIso = new Date().toISOString();

    const record = {
      id: userId,
      role,
      // Preserve previously captured details when this upsert is sparse.
      phoneE164: phoneE164 || existing?.phoneE164 || null,
      displayName: displayName || existing?.displayName || null,
      createdAt: existing?.createdAt ?? nowIso,
      updatedAt: nowIso
    };

    this.users.set(userId, record);
    return clone(record);
  }

  async getUser(id) {
    return id ? clone(this.users.get(id)) ?? null : null;
  }

  async listUsers({ role } = {}) {
    return Array.from(this.users.values())
      .filter((u) => !role || u.role === role)
      .sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1))
      .map((u) => clone(u));
  }

  async listHosts() {
    return this.listUsers({ role: "host" });
  }

  async countByRole() {
    const counts = { rider: 0, host: 0, admin: 0, service: 0, total: 0 };
    for (const u of this.users.values()) {
      counts[u.role] = (counts[u.role] ?? 0) + 1;
      counts.total += 1;
    }
    return counts;
  }
}
