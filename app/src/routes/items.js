'use strict';

const express = require('express');
const { query } = require('../db');

const router = express.Router();

// Basic input validation helper (kept dependency-free on purpose)
function isValidItem(body) {
  return (
    body &&
    typeof body.name === 'string' &&
    body.name.trim().length > 0 &&
    body.name.length <= 255
  );
}

// GET /items - list items
router.get('/', async (req, res, next) => {
  try {
    const { result } = await query(
      'SELECT id, name, created_at FROM items ORDER BY id DESC LIMIT 100'
    );
    res.json(result.rows);
  } catch (err) {
    next(err);
  }
});

// GET /items/:id
router.get('/:id', async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) {
      return res.status(400).json({ error: 'invalid id' });
    }
    const { result } = await query(
      'SELECT id, name, created_at FROM items WHERE id = $1',
      [id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'not found' });
    }
    res.json(result.rows[0]);
  } catch (err) {
    next(err);
  }
});

// POST /items - create item (parameterized query prevents SQL injection)
router.post('/', async (req, res, next) => {
  try {
    if (!isValidItem(req.body)) {
      return res.status(400).json({ error: 'name is required (string, <=255 chars)' });
    }
    const { result } = await query(
      'INSERT INTO items (name) VALUES ($1) RETURNING id, name, created_at',
      [req.body.name.trim()]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
