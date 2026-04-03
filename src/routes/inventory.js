const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { query } = require('../db');

const router = express.Router();

// GET /api/inventory  – list all items with supplier name and reorder alert flag
router.get('/', async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        i.*,
        s.name AS supplier_name,
        s.payment_day AS supplier_payment_day,
        s.lead_time_days AS supplier_lead_time_days,
        (i.reorder_level IS NOT NULL AND i.quantity_in_stock <= i.reorder_level) AS needs_reorder
      FROM unix_store_inventory i
      LEFT JOIN unix_suppliers s ON s.id = i.supplier_id
      ORDER BY i.category, i.name
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/inventory/alerts/reorder  – only items that have hit their reorder level
router.get('/alerts/reorder', async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        i.*,
        s.name AS supplier_name,
        s.phone AS supplier_phone,
        s.lead_time_days AS supplier_lead_time_days
      FROM unix_store_inventory i
      LEFT JOIN unix_suppliers s ON s.id = i.supplier_id
      WHERE i.reorder_level IS NOT NULL
        AND i.quantity_in_stock <= i.reorder_level
      ORDER BY (i.quantity_in_stock / NULLIF(i.reorder_level, 0)) ASC
    `);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/inventory/:id
router.get('/:id', async (req, res) => {
  try {
    const rows = await query(
      `SELECT i.*, s.name AS supplier_name
       FROM unix_store_inventory i
       LEFT JOIN unix_suppliers s ON s.id = i.supplier_id
       WHERE i.id = ?`,
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ error: 'Item not found' });
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/inventory  – add a new store item
router.post('/', async (req, res) => {
  const { name, category, unit_of_measure, quantity_in_stock, reorder_level, cost_per_unit, supplier_id, notes } = req.body;
  if (!name) return res.status(400).json({ error: 'name is required' });
  if (!unit_of_measure) return res.status(400).json({ error: 'unit_of_measure is required' });
  const id = uuidv4();
  try {
    await query(
      `INSERT INTO unix_store_inventory
         (id, name, category, unit_of_measure, quantity_in_stock, reorder_level, cost_per_unit, supplier_id, notes)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [id, name, category || null, unit_of_measure, quantity_in_stock || 0, reorder_level || null,
       cost_per_unit || null, supplier_id || null, notes || null]
    );
    res.status(201).json({ id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/inventory/:id  – full update
router.put('/:id', async (req, res) => {
  const { name, category, unit_of_measure, quantity_in_stock, reorder_level, cost_per_unit, supplier_id, notes } = req.body;
  try {
    await query(
      `UPDATE unix_store_inventory
       SET name=?, category=?, unit_of_measure=?, quantity_in_stock=?,
           reorder_level=?, cost_per_unit=?, supplier_id=?, notes=?
       WHERE id=?`,
      [name, category || null, unit_of_measure, quantity_in_stock, reorder_level || null,
       cost_per_unit || null, supplier_id || null, notes || null, req.params.id]
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /api/inventory/:id/adjust  – adjust stock quantity (receive delivery or manual correction)
// body: { delta: number, reason: string }
router.patch('/:id/adjust', async (req, res) => {
  const { delta, reason } = req.body;
  if (delta === undefined) return res.status(400).json({ error: 'delta is required' });
  try {
    await query(
      `UPDATE unix_store_inventory
       SET quantity_in_stock = quantity_in_stock + ?
       WHERE id = ?`,
      [delta, req.params.id]
    );
    res.json({ ok: true, note: reason || null });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /api/inventory/:id
router.delete('/:id', async (req, res) => {
  try {
    await query('DELETE FROM unix_store_inventory WHERE id = ?', [req.params.id]);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
