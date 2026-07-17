# Security Checklist Before Live Pilot

- Rotate all local/dev secrets before deployment.
- Use a managed secrets store for Razorpay, Tuya, Stellar, database, and JWT secrets.
- Require Razorpay webhook signatures in every non-local environment.
- Add Tuya webhook signature verification when Tuya webhooks are enabled.
- Keep Stellar signing keys out of app logs and out of frontend builds.
- Restrict admin reconciliation endpoints to admin/service roles only.
- Add rate limits to payment, telemetry, and reconcile endpoints.
- Enforce CORS allowlist for web dashboard origins.
- Turn on TLS at the ingress layer.
- Add audit logging for every admin action.
