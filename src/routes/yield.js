const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { query } = require('../db');

const router = express.Router();

// GET /api/yield  – list all yield configs with store item + product names
router.get('/', async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        y.*,
        i.name AS inventory_item_name,
        i.unit_of_measure,
        p.name AS pos_product_name,
        p.pricesell AS pos_product_price
      FROM unix_yield_config y
      JOIN unix_store_inventory i ON i.id = y.inventory_item_id
      LEFT JOIN products p ON p.id = y.unicenta_product_id
      ORDER BY i.name
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/yield/:id
router.get('/:id', async (req, res) => {
  try {
    const rows = await query(
      `SELECT y.*, i.name AS inventory_item_name, p.name AS pos_product_name
       FROM unix_yield_config y
       JOIN unix_store_inventory i ON i.id = y.inventory_item_id
       LEFT JOIN products p ON p.id = y.unicenta_product_id
       WHERE y.id = ?`,
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ error: 'Yield config not found' });
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/yield  – create a new yield mapping
router.post('/', async (req, res) => {
  const { inventory_item_id, unicenta_product_id, portions_per_unit, notes } = req.body;
  if (!inventory_item_id || !unicenta_product_id || !portions_per_unit) {
    return res.status(400).json({ error: 'inventory_item_id, unicenta_product_id, and portions_per_unit are required' });
  }
  const id = uuidv4();
  try {
    await query(
      `INSERT INTO unix_yield_config (id, inventory_item_id, unicenta_product_id, portions_per_unit, notes)
       VALUES (?, ?, ?, ?, ?)`,
      [id, inventory_item_id, unicenta_product_id, portions_per_unit, notes || null]
    );
    res.status(201).json({ id });
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ error: 'A yield config for this item/product pair already exists' });
    }
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/yield/:id
router.put('/:id', async (req, res) => {
  const { portions_per_unit, notes } = req.body;
  try {
    await query(
      'UPDATE unix_yield_config SET portions_per_unit=?, notes=? WHERE id=?',
      [portions_per_unit, notes || null, req.params.id]
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /api/yield/:id
router.delete('/:id', async (req, res) => {
  try {
    await query('DELETE FROM unix_yield_config WHERE id = ?', [req.params.id]);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
