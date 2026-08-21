'use strict';

const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const pino = require('pino');
const pinoHttp = require('pino-http');

const itemsRouter = require('./routes/items');
const { healthCheck } = require('./db');

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  // Redact anything that could accidentally end up in a log line.
  redact: ['req.headers.authorization', 'req.headers.cookie'],
});

const app = express();

// --- Security hardening -----------------------------------------------
app.disable('x-powered-by');
app.use(helmet());
app.use(express.json({ limit: '100kb' }));
app.use(
  rateLimit({
    windowMs: 60 * 1000,
    limit: 100,
    standardHeaders: true,
    legacyHeaders: false,
  })
);
app.use(pinoHttp({ logger }));

// --- Routes --------------------------------------------------------------

// Landing page - lists available routes so hitting the bare service URL
// doesn't just 404. Kept as JSON since this is a REST API, not a website.
app.get('/', (req, res) => {
  res.status(200).json({
    service: 'secure-node-cloudrun-api',
    routes: {
      'GET /healthz': 'Liveness check - process is up, does not touch the DB',
      'GET /readyz': 'Readiness check - confirms DB connectivity via the VPC connector',
      'GET /items': 'List up to 100 most recent items',
      'GET /items/:id': 'Get a single item by numeric id',
      'POST /items': 'Create an item - JSON body: { "name": "string, 1-255 chars" }',
    },
  });
});

app.get('/healthz', (req, res) => {
  // Liveness: process is up. Does NOT touch the DB so Cloud Run doesn't
  // kill healthy instances during transient DB blips.
  res.status(200).json({ status: 'ok' });
});

app.get('/readyz', async (req, res) => {
  // Readiness: confirms DB connectivity through the VPC connector.
  try {
    await healthCheck();
    res.status(200).json({ status: 'ready' });
  } catch (err) {
    // Log everything useful server-side (code, message, and - for
    // connection-level failures - the address/port pg attempted) so
    // `gcloud logging read` / Cloud Logging actually shows something
    // actionable. None of this is sent back to the client below -
    // clients only ever see the generic 503, on purpose.
    req.log.error(
      {
        err: {
          code: err.code,
          message: err.message,
          address: err.address,
          port: err.port,
        },
      },
      'readiness check failed'
    );
    res.status(503).json({ status: 'not-ready' });
  }
});

app.use('/items', itemsRouter);

// 404 handler - so unmatched routes return a helpful body instead of
// Express's bare-bones default 404 page.
app.use((req, res) => {
  res.status(404).json({
    error: 'not found',
    hint: 'GET / for a list of available routes',
  });
});

// --- Error handling (no stack traces / internals leaked to clients) -----
app.use((err, req, res, next) => { // eslint-disable-line no-unused-vars
  // Full detail server-side only - err.stack in particular is invaluable
  // for actually debugging from Cloud Logging, and never reaches the
  // client response below.
  req.log.error(
    { err: { message: err.message, code: err.code, stack: err.stack } },
    'unhandled request error'
  );
  res.status(500).json({ error: 'internal server error' });
});

const port = process.env.PORT || 8080;

if (require.main === module) {
  const server = app.listen(port, () => {
    logger.info(`listening on port ${port}`);
  });

  // Graceful shutdown - important on Cloud Run, which sends SIGTERM
  // before killing the container on scale-down / deploys.
  process.on('SIGTERM', () => {
    logger.info('SIGTERM received, shutting down gracefully');
    server.close(() => process.exit(0));
  });
}

module.exports = app;