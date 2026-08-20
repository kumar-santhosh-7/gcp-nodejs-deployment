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
    req.log.error({ err: err.code }, 'readiness check failed');
    res.status(503).json({ status: 'not-ready' });
  }
});

app.use('/items', itemsRouter);

// --- Error handling (no stack traces / internals leaked to clients) -----
app.use((err, req, res, next) => { // eslint-disable-line no-unused-vars
  req.log.error({ err: err.message }, 'unhandled request error');
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
