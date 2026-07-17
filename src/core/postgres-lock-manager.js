export class PostgresLockManager {
  constructor({ prismaClient } = {}) {
    this.prisma = prismaClient;
  }

  async runExclusive(lockKey, handler) {
    if (!this.prisma) {
      return handler();
    }
    const lockId = this.hashLockKey(lockKey);
    await this.prisma.$executeRaw`SELECT pg_advisory_xact_lock(${lockId})`;
    return handler();
  }

  hashLockKey(lockKey) {
    let hash = 0;
    for (let i = 0; i < lockKey.length; i++) {
      const char = lockKey.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash |= 0;
    }
    return Math.abs(hash);
  }
}