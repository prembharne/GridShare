import { DomainError } from "../core/errors.js";

export const INVOICE_DESCRIPTION = "Infrastructure Facility & Leasing Service Fee";

const FORBIDDEN_COPY_PATTERNS = [
  /electricity\s+resale/i,
  /resale\s+of\s+electricity/i,
  /electricity\s+sale/i,
  /selling\s+electricity/i,
  /power\s+sale/i,
  /energy\s+sale/i
];

export function assertComplianceCopy(text) {
  if (!text) {
    throw new DomainError(
      "COMPLIANCE_COPY_MISSING",
      "Invoice description is required.",
      { text }
    );
  }

  const match = FORBIDDEN_COPY_PATTERNS.find((pattern) => pattern.test(text));

  if (match) {
    throw new DomainError(
      "COMPLIANCE_COPY_VIOLATION",
      "Copy contains forbidden electricity-resale wording.",
      { text, pattern: String(match) }
    );
  }

  return true;
}
