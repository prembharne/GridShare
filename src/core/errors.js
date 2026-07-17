export class DomainError extends Error {
  constructor(code, message, details = {}) {
    super(message);
    this.name = "DomainError";
    this.code = code;
    this.details = details;
  }
}

export function invariant(condition, code, message, details = {}) {
  if (!condition) {
    throw new DomainError(code, message, details);
  }
}

export function toErrorResponse(error) {
  if (error instanceof DomainError) {
    return {
      ok: false,
      error: {
        code: error.code,
        message: error.message,
        details: error.details
      }
    };
  }

  return {
    ok: false,
    error: {
      code: "INTERNAL_ERROR",
      message: error?.message ?? "Unexpected error"
    }
  };
}
