'use strict';

const { Pool } = require('pg');

/**
 * Connection strategy
 * -------------------
 * Cloud Run connects to Cloud SQL over PRIVATE IP through the Serverless
 * VPC Access connector (VPC_CONNECTOR). This keeps all DB traffic inside
 * the VPC and off the public internet - no Cloud SQL Auth Proxy / public
 * IP is required.
 *
 * All secret values (DB_USER, DB_PASSWORD, DB_NAME) are injected as
 * environment variables by Cloud Run, which pulls them directly from
 * Secret Manager at container start time (configured in Terraform via
 * `secret` blocks on the Cloud Run service, not baked into the image).
 *
 * DB_HOST is the Cloud SQL instance's PRIVATE IP address (set as a
 * regular, non-secret env var since it's not sensitive on its own).
 */
const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  max: Number(process.env.DB_POOL_MAX || 5),
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
});

pool.on('error', (err) => {
  // Never log err.message blindly if it could contain connection strings;
  // pg errors here are safe (no creds embedded), but we still avoid
  // logging the full error object to keep logs clean.
  // eslint-disable-next-line no-console
  console.error('Unexpected error on idle DB client', { code: err.code });
});

async function query(text, params) {
  const start = Date.now();
  const result = await pool.query(text, params);
  const duration = Date.now() - start;
  return { result, duration };
}

async function healthCheck() {
  await pool.query('SELECT 1');
}

module.exports = { pool, query, healthCheck };
