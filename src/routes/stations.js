const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { query } = require('../db');

const router = express.Router();

// GET /api/stations  – list all stations (active first)
router.get('/', async (req, res) => {
  try {
    const rows = await query(
      `SELECT * FROM store_stations ORDER BY is_active DESC, name ASC`
    );
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/stations/:id
router.get('/:id', async (req, res) => {
  try {
    const rows = await query(
      `SELECT * FROM store_stations WHERE id = ?`,
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ error: 'Station not found' });
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/stations  – create a station
// body: { name, description? }
router.post('/', async (req, res) => {
  const { name, description } = req.body;
  if (!name || !name.trim()) return res.status(400).json({ error: 'name is required' });
  const id = uuidv4();
  try {
    await query(
      `INSERT INTO store_stations (id, name, description) VALUES (?, ?, ?)`,
      [id, name.trim(), description || null]
    );
    res.status(201).json({ id });
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ error: `A station named "${name.trim()}" already exists` });
    }
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/stations/:id  – update name / description
router.put('/:id', async (req, res) => {
  const { name, description } = req.body;
  if (!name || !name.trim()) return res.status(400).json({ error: 'name is required' });
  try {
    await query(
      `UPDATE store_stations SET name = ?, description = ? WHERE id = ?`,
      [name.trim(), description || null, req.params.id]
    );
    res.json({ ok: true });
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ error: `A station named "${name.trim()}" already exists` });
    }
    res.status(500).json({ error: err.message });
  }
});

// PATCH /api/stations/:id/toggle  – activate / deactivate
router.patch('/:id/toggle', async (req, res) => {
  try {
    await query(
      `UPDATE store_stations SET is_active = NOT is_active WHERE id = ?`,
      [req.params.id]
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /api/stations/:id
router.delete('/:id', async (req, res) => {
  try {
    await query(`DELETE FROM store_stations WHERE id = ?`, [req.params.id]);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
