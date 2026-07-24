import { DomainError } from "../core/errors.js";

/**
 * Derive a stable, human-readable user id from a phone number so repeated
 * logins with the same phone resolve to the same id (and therefore the same
 * wallet balance / session history). Falls back to a random id when no phone
 * is available.
 */
export function deriveUserId(role, phoneE164) {
  const prefix = role === "host" ? "host" : role === "admin" ? "admin" : "rider";
  if (phoneE164) {
    const digits = String(phoneE164).replace(/\D/g, "");
    if (digits) return `${prefix}_${digits}`;
  }
  return `${prefix}_${crypto.randomUUID().replaceAll("-", "").slice(0, 18)}`;
}

/**
 * Prisma-backed registry of users (riders/hosts/admins). Persists identity
 * details so the admin dashboard can list real users and hosts. This is wired
 * whenever DATABASE_URL is configured, independent of the mock/real adapter
 * flag, so the demo can keep running on mock chain/hardware while identity
 * data still flows to Postgres.
 */
export class PrismaUserRepository {
  constructor({ prisma }) {
    if (!prisma) {
      throw new DomainError("INVALID_CONFIG", "PrismaUserRepository requires a prisma client.");
    }
    this.prisma = prisma;
  }

  /**
   * Insert or update a user. When `id` is supplied it is the natural key
   * (used for hosts captured from sessions); otherwise the id is derived from
   * the phone number so logins are idempotent.
   */
  async upsertUser({ id, phoneE164 = null, role = "rider", displayName = null }) {
    const userId = id ?? deriveUserId(role, phoneE164);

    const created = {
      id: userId,
      role,
      phoneE164: phoneE164 || null,
      displayName: displayName || null
    };

    const update = { role };
    if (phoneE164) update.phoneE164 = phoneE164;
    if (displayName) update.displayName = displayName;

    try {
      const user = await this.prisma.user.upsert({
        where: { id: userId },
        create: created,
        update
      });
      return this._serialize(user);
    } catch (err) {
      console.warn("[PrismaUserRepository] DB upsert failed, returning in-memory fallback:", err?.message || err);
      return {
        id: userId,
        role,
        phoneE164: phoneE164 || null,
        displayName: displayName || "GridShare User",
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      };
    }
  }

  async getUser(id) {
    if (!id) return null;
    try {
      const user = await this.prisma.user.findUnique({ where: { id } });
      return user ? this._serialize(user) : { id, role: "rider", displayName: "GridShare User", phoneE164: null };
    } catch (err) {
      console.warn("[PrismaUserRepository] DB getUser failed, returning in-memory fallback:", err?.message || err);
      return { id, role: "rider", displayName: "GridShare User", phoneE164: null };
    }
  }

  async listUsers({ role } = {}) {
    const users = await this.prisma.user.findMany({
      where: role ? { role } : undefined,
      orderBy: { createdAt: "desc" }
    });
    return users.map((u) => this._serialize(u));
  }

  async listHosts() {
    return this.listUsers({ role: "host" });
  }

  async countByRole() {
    const rows = await this.prisma.user.groupBy({ by: ["role"], _count: { _all: true } });
    const counts = { rider: 0, host: 0, admin: 0, service: 0, total: 0 };
    for (const row of rows) {
      counts[row.role] = row._count._all;
      counts.total += row._count._all;
    }
    return counts;
  }

  _serialize(user) {
    return {
      id: user.id,
      role: user.role,
      phoneE164: user.phoneE164 ?? null,
      displayName: user.displayName ?? null,
      createdAt: user.createdAt instanceof Date ? user.createdAt.toISOString() : user.createdAt,
      updatedAt: user.updatedAt instanceof Date ? user.updatedAt.toISOString() : user.updatedAt
    };
  }
}
