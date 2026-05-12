-- Migration 005: Add furniture_items table for syncing furniture across devices
CREATE TABLE IF NOT EXISTS furniture_items (
  id            SERIAL PRIMARY KEY,
  project_id    INTEGER NOT NULL REFERENCES projects(id),
  shape_index   INTEGER NOT NULL DEFAULT 0,
  furniture_id  TEXT NOT NULL,
  type          TEXT NOT NULL,
  position_x    DOUBLE PRECISION NOT NULL,
  position_y    DOUBLE PRECISION NOT NULL,
  rotation_deg  DOUBLE PRECISION NOT NULL DEFAULT 0,
  width_mm      DOUBLE PRECISION NOT NULL,
  depth_mm      DOUBLE PRECISION NOT NULL
);
