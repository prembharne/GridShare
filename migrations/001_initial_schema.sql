-- GridShare difficult-core production schema target.
-- PostgreSQL 15+ with PostGIS and TimescaleDB extensions.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS timescaledb;

DO $$ BEGIN
  CREATE TYPE session_status AS ENUM (
    'pending_payment',
    'paid',
    'escrow_lock_failed',
    'active',
    'stopping',
    'settled',
    'refunded_after_activation_failure'
  );
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  role TEXT NOT NULL CHECK (role IN ('rider', 'host', 'admin', 'service')),
  phone_e164 TEXT UNIQUE,
  display_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS outlets (
  id TEXT PRIMARY KEY,
  host_id TEXT NOT NULL REFERENCES users(id),
  display_name TEXT NOT NULL,
  device_provider TEXT NOT NULL DEFAULT 'tuya',
  provider_device_id TEXT NOT NULL UNIQUE,
  location GEOGRAPHY(POINT, 4326) NOT NULL,
  address TEXT,
  max_current_amp NUMERIC(8, 3) NOT NULL DEFAULT 16,
  status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'busy', 'offline', 'maintenance')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS outlets_location_gix ON outlets USING GIST (location);
CREATE INDEX IF NOT EXISTS outlets_host_idx ON outlets(host_id);

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  rider_id TEXT NOT NULL REFERENCES users(id),
  host_id TEXT NOT NULL REFERENCES users(id),
  outlet_id TEXT NOT NULL REFERENCES outlets(id),
  status session_status NOT NULL,
  deposit_paise INTEGER NOT NULL CHECK (deposit_paise > 0),
  payment_id TEXT,
  paid_at TIMESTAMPTZ,
  escrow_lock_tx_hash TEXT,
  hardware_on_command_id TEXT,
  hardware_off_command_id TEXT,
  active_at TIMESTAMPTZ,
  stopped_at TIMESTAMPTZ,
  stop_reason TEXT,
  stop_kind TEXT,
  pending_settlement JSONB,
  pending_oracle_report JSONB,
  settlement JSONB,
  settlement_tx_hash TEXT,
  refund_tx_hash TEXT,
  invoice_description TEXT,
  failure_code TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS sessions_payment_id_uidx ON sessions(payment_id) WHERE payment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS sessions_status_idx ON sessions(status);
CREATE INDEX IF NOT EXISTS sessions_outlet_status_idx ON sessions(outlet_id, status);
CREATE INDEX IF NOT EXISTS sessions_reconcile_idx ON sessions(status) WHERE status IN ('paid', 'escrow_lock_failed', 'stopping');

CREATE TABLE IF NOT EXISTS idempotency_keys (
  scope TEXT NOT NULL,
  key TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  response_json JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (scope, key)
);

CREATE TABLE IF NOT EXISTS hardware_commands (
  id TEXT PRIMARY KEY,
  session_id TEXT REFERENCES sessions(id),
  outlet_id TEXT NOT NULL REFERENCES outlets(id),
  desired_state BOOLEAN NOT NULL,
  reason TEXT NOT NULL,
  provider_command_id TEXT,
  status TEXT NOT NULL DEFAULT 'issued' CHECK (status IN ('issued', 'acknowledged', 'failed')),
  issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  acknowledged_at TIMESTAMPTZ,
  failure_code TEXT,
  raw_provider_response JSONB
);

CREATE INDEX IF NOT EXISTS hardware_commands_session_idx ON hardware_commands(session_id);
CREATE INDEX IF NOT EXISTS hardware_commands_outlet_idx ON hardware_commands(outlet_id, issued_at DESC);

CREATE TABLE IF NOT EXISTS telemetry_samples (
  session_id TEXT NOT NULL REFERENCES sessions(id),
  outlet_id TEXT NOT NULL REFERENCES outlets(id),
  sampled_at TIMESTAMPTZ NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  energy_wh NUMERIC(14, 3) NOT NULL CHECK (energy_wh >= 0),
  current_amp NUMERIC(10, 3) NOT NULL CHECK (current_amp >= 0),
  voltage_v NUMERIC(10, 3) NOT NULL CHECK (voltage_v > 0),
  temp_c NUMERIC(10, 3) NOT NULL,
  raw_provider_payload JSONB,
  PRIMARY KEY (session_id, sampled_at)
);

SELECT create_hypertable('telemetry_samples', 'sampled_at', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS telemetry_samples_session_time_idx ON telemetry_samples(session_id, sampled_at DESC);
CREATE INDEX IF NOT EXISTS telemetry_samples_outlet_time_idx ON telemetry_samples(outlet_id, sampled_at DESC);

CREATE TABLE IF NOT EXISTS ledger_events (
  id BIGSERIAL PRIMARY KEY,
  event_type TEXT NOT NULL,
  session_id TEXT REFERENCES sessions(id),
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ledger_events_session_idx ON ledger_events(session_id, id);
CREATE INDEX IF NOT EXISTS ledger_events_type_idx ON ledger_events(event_type, id);

CREATE TABLE IF NOT EXISTS outbox_events (
  id BIGSERIAL PRIMARY KEY,
  event_type TEXT NOT NULL,
  session_id TEXT REFERENCES sessions(id),
  payload JSONB NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'sent', 'failed')),
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS outbox_pending_idx ON outbox_events(status, next_attempt_at, id);

CREATE TABLE IF NOT EXISTS reconciliation_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at TIMESTAMPTZ,
  scanned INTEGER NOT NULL DEFAULT 0,
  recovered INTEGER NOT NULL DEFAULT 0,
  failed INTEGER NOT NULL DEFAULT 0,
  details JSONB NOT NULL DEFAULT '{}'::jsonb
);
