'use strict';

const test = require('node:test');
const assert = require('node:assert');
const request = require('supertest');

// Point db.js at a host that will simply fail fast in CI - we only
// exercise routes/validation logic here, not real DB connectivity.
process.env.DB_HOST = '127.0.0.1';
process.env.DB_USER = 'test';
process.env.DB_PASSWORD = 'test';
process.env.DB_NAME = 'test';

const app = require('../src/index');

test('GET /healthz returns 200 without touching the DB', async () => {
  const res = await request(app).get('/healthz');
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.status, 'ok');
});

test('POST /items rejects missing name', async () => {
  const res = await request(app).post('/items').send({});
  assert.strictEqual(res.status, 400);
});

test('POST /items rejects overly long name', async () => {
  const res = await request(app)
    .post('/items')
    .send({ name: 'a'.repeat(300) });
  assert.strictEqual(res.status, 400);
});

test('GET /items/:id rejects non-numeric id', async () => {
  const res = await request(app).get('/items/not-a-number');
  assert.strictEqual(res.status, 400);
});
