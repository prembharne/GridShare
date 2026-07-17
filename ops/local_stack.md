# Local Production-Like Stack

Use this when you are ready to replace the in-memory store with real persistence.

```powershell
docker compose up -d
```

This starts:

- PostgreSQL with TimescaleDB and PostGIS
- Redis for future cache/pubsub/queue work

The migration in `migrations/001_initial_schema.sql` is mounted into the database init directory.

Connection string for local development:

```text
postgres://gridshare:gridshare_dev_password@localhost:5432/gridshare
```

Do not use the dev password in any hosted environment.
