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
  // The CA cert is Cloud SQL's own server CA (fetched via `gcloud sql
  // instances describe`, stored in Secret Manager, injected as DB_SSL_CA
  // just like the other credentials - see terraform/modules/secrets and
  // the DB_SSL_CA env block on the Cloud Run service). Passing it lets
  // Node verify it's actually talking to our Cloud SQL instance, not
  // just trusting whatever certificate is presented on the private IP.
  //
  // checkServerIdentity is overridden to skip hostname/SAN matching
  // specifically: Cloud SQL's server cert SAN is the instance's managed
  // *.sql.goog DNS name, never the private IP we actually connect to -
  // connecting by IP will always fail Node's default hostname check
  // against a DNS-only SAN, regardless of how correct the CA is. This
  // is the standard, documented workaround for raw TLS connections to
  // Cloud SQL (as opposed to using the Cloud SQL Auth Proxy or the
  // official connector library, which handle this internally). CA
  // verification still happens via the `ca` option above - we're only
  // skipping the hostname match, not certificate trust.
  ssl:
    process.env.DB_SSL === 'true'
      ? {
          rejectUnauthorized: true,
          ca: process.env.DB_SSL_CA,
          checkServerIdentity: () => undefined,
        }
      : false,
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