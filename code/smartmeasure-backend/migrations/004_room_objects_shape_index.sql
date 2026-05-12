-- Migration 004: Add shape_index to room_objects so each door/window
-- knows which room (shape) it belongs to in multi-room projects.
-- Run once against your Railway PostgreSQL database:
--   psql $DATABASE_URL -f migrations/004_room_objects_shape_index.sql

ALTER TABLE room_objects
  ADD COLUMN IF NOT EXISTS shape_index INTEGER NOT NULL DEFAULT 0;
