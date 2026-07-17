import { DomainError } from "../core/errors.js";

export class SecretManager {
  constructor(env = process.env) {
    this.env = env;
  }

  require(name) {
    const value = this.env[name];

    if (!value) {
      throw new DomainError("MISSING_SECRET", `Missing required secret: ${name}`, { name });
    }

    return value;
  }
}
