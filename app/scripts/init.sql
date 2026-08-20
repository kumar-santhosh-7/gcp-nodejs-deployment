-- Minimal schema for the demo /items API.
-- Run this once against the Cloud SQL instance, e.g. via a one-off
-- Cloud Run Job or `psql` from a bastion inside the VPC (never expose
-- the instance publicly to run this).

CREATE TABLE IF NOT EXISTS items (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(255) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
