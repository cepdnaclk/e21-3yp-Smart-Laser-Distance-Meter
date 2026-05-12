-- Migration 006: Add can_edit flag to project_collaborators
-- Owner can grant a collaborator full edit access (upload changes).
ALTER TABLE project_collaborators
  ADD COLUMN IF NOT EXISTS can_edit BOOLEAN NOT NULL DEFAULT FALSE;
