-- Migration 003: Add project_presence table for real-time collaborator presence
-- Run this once against your Railway PostgreSQL database:
--   psql $DATABASE_URL -f migrations/003_project_presence.sql

CREATE TABLE IF NOT EXISTS project_presence (
  project_id   INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  user_id      INTEGER NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
  last_seen_at TIMESTAMP NOT NULL DEFAULT NOW(),
  PRIMARY KEY (project_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_presence_project_seen
  ON project_presence (project_id, last_seen_at DESC);
