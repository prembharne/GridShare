# Database Migrations

`001_initial_schema.sql` is the production target schema for the difficult core.

It expects PostgreSQL with:

- `pgcrypto`
- `postgis`
- `timescaledb`

The current local app still uses `InMemoryStore`. The real database adapter should map the same saga contract onto these tables without changing the HTTP integration contract.
