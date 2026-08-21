'use strict';

/**
 * One-shot schema migration script.
 *
 * Runs as a Cloud Run Job (see terraform/modules/cloudrun's
 * google_cloud_run_v2_job.migrate), triggered by cd.yml right after the
 * image is built/pushed and before the main service is updated - so a
 * new revision never serves traffic against a schema it doesn't expect.
 *
 * Uses the exact same env vars / connection settings as the main app
 * (DB_HOST, DB_USER, DB_PASSWORD, DB_NAME, DB_SSL, DB_SSL_CA), so it
 * exercises the identical VPC connector + private IP + TLS path as
 * production traffic - if this job fails, the app would have failed to
 * connect too, which is exactly the signal you want before deploying.
 *
 * Idempotent by design (CREATE TABLE IF NOT EXISTS) - safe to run on
 * every single deploy, not just the first one. As the schema grows,
 * add new statements below rather than editing existing ones, the same
 * way you'd write any migration.
 */

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  connectionTimeoutMillis: 10000,
  // See app/src/db.js for the full explanation - checkServerIdentity is
  // overridden because Cloud SQL's server cert SAN is a managed DNS
  // name, never the private IP we connect by, so hostname verification
  // would always fail otherwise even with the correct CA.
  ssl:
    process.env.DB_SSL === 'true'
      ? {
          rejectUnauthorized: true,
          ca: process.env.DB_SSL_CA,
          checkServerIdentity: () => undefined,
        }
      : false,
});

async function migrate() {
  const sqlPath = path.join(__dirname, 'init.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8');

  console.log('Running migration:', sqlPath);
  await pool.query(sql);
  console.log('Migration complete.');
}

migrate()
  .then(() => pool.end())
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Migration failed:', { code: err.code, message: err.message });
    pool.end().finally(() => process.exit(1));
  });