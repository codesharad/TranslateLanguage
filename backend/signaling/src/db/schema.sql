-- TranslateLanguage identity store
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_e164    TEXT NOT NULL UNIQUE,
  display_name  TEXT NOT NULL DEFAULT '',
  default_lang  TEXT NOT NULL DEFAULT 'ta-IN',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS otp_challenges (
  phone_e164    TEXT PRIMARY KEY,
  code_hash     TEXT NOT NULL,
  expires_at    TIMESTAMPTZ NOT NULL,
  attempts      INT NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS devices (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id     TEXT NOT NULL,
  platform      TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
  voip_token    TEXT,
  fcm_token     TEXT,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, device_id)
);

CREATE TABLE IF NOT EXISTS calls (
  id            UUID PRIMARY KEY,
  caller_id     UUID NOT NULL REFERENCES users(id),
  callee_id     UUID NOT NULL REFERENCES users(id),
  caller_lang   TEXT NOT NULL,
  callee_lang   TEXT NOT NULL,
  state         TEXT NOT NULL DEFAULT 'ringing',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at      TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS otp_sends (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_e164    TEXT NOT NULL,
  sent_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS users_phone_idx ON users (phone_e164);
CREATE INDEX IF NOT EXISTS otp_sends_phone_idx ON otp_sends (phone_e164, sent_at);
CREATE INDEX IF NOT EXISTS devices_user_idx ON devices (user_id);
