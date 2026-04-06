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

// GET /api/inventory/draft-po
// Auto-generates a draft purchase order for items needing restocking soon.
// Triggered when: quantity_in_stock <= reorder_level + (daily_usage * lead_time_days)
// daily_usage = average daily issues from last 30 days of requisitions
router.get('/draft-po', async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        i.id,
        i.name,
        i.category,
        i.unit_of_measure,
        i.quantity_in_stock,
        i.reorder_level,
        i.cost_per_unit,
        i.lead_time_days,
        s.id    AS supplier_id,
        s.name  AS supplier_name,
        s.phone AS supplier_phone,
        COALESCE(rs_usage.daily_avg, 0) AS daily_usage,
        ROUND(
          COALESCE(i.reorder_level, 0)
          + (COALESCE(rs_usage.daily_avg, 0) * COALESCE(i.lead_time_days, 1)),
          3
        ) AS reorder_threshold,
        GREATEST(0,
          ROUND(
            (COALESCE(i.reorder_level, 0) * 2)
            - i.quantity_in_stock
            + (COALESCE(rs_usage.daily_avg, 0) * COALESCE(i.lead_time_days, 1)),
            3
          )
        ) AS suggested_order_qty
      FROM unix_store_inventory i
      LEFT JOIN unix_suppliers s ON s.id = i.supplier_id
      LEFT JOIN (
        SELECT inventory_item_id,
               ROUND(SUM(quantity) / 30, 3) AS daily_avg
        FROM unix_requisitions
        WHERE status = 'Issued'
          AND requested_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
        GROUP BY inventory_item_id
      ) AS rs_usage ON rs_usage.inventory_item_id = i.id
      WHERE i.quantity_in_stock <=
        COALESCE(i.reorder_level, 0)
        + (COALESCE(rs_usage.daily_avg, 0) * COALESCE(i.lead_time_days, 1))
      ORDER BY i.category, i.name
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/inventory/cost-history/:id  – cost change history for an item
router.get('/cost-history/:id', async (req, res) => {
  try {
    const rows = await query(
      `SELECT * FROM unix_cost_history WHERE inventory_item_id = ? ORDER BY changed_at DESC LIMIT 50`,
      [req.params.id]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/inventory/inflation-summary  – recent cost changes across all items (for heatmap)
// Returns items whose cost changed in the last 30 days, with weekly usage for KES impact calc.
router.get('/inflation-summary', async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        i.id,
        i.name,
        i.unit_of_measure,
        i.cost_per_unit AS current_cost,
        ch.old_cost,
        ch.new_cost,
        ch.changed_at,
        ROUND(COALESCE(weekly.qty, 0), 3) AS weekly_usage,
        ROUND((ch.new_cost - COALESCE(ch.old_cost, ch.new_cost)) * COALESCE(weekly.qty, 0), 2) AS weekly_impact_kes
      FROM unix_cost_history ch
      JOIN unix_store_inventory i ON i.id = ch.inventory_item_id
      JOIN (
        SELECT inventory_item_id, changed_at,
               ROW_NUMBER() OVER (PARTITION BY inventory_item_id ORDER BY changed_at DESC) AS rn
        FROM unix_cost_history
        WHERE changed_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
      ) latest ON latest.inventory_item_id = ch.inventory_item_id AND latest.changed_at = ch.changed_at
      LEFT JOIN (
        SELECT inventory_item_id, ROUND(SUM(quantity) / 4, 3) AS qty
        FROM unix_requisitions
        WHERE status = 'Issued'
          AND requested_at >= DATE_SUB(CURDATE(), INTERVAL 28 DAY)
        GROUP BY inventory_item_id
      ) weekly ON weekly.inventory_item_id = i.id
      WHERE latest.rn = 1
      ORDER BY ABS(weekly_impact_kes) DESC
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
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
  const { name, category, unit_of_measure, quantity_in_stock, reorder_level,
          cost_per_unit, supplier_id, notes, lead_time_days } = req.body;
  if (!name) return res.status(400).json({ error: 'name is required' });
  if (!unit_of_measure) return res.status(400).json({ error: 'unit_of_measure is required' });
  const id = uuidv4();
  try {
    await query(
      `INSERT INTO unix_store_inventory
         (id, name, category, unit_of_measure, quantity_in_stock, reorder_level,
          cost_per_unit, supplier_id, notes, lead_time_days)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [id, name, category || null, unit_of_measure, quantity_in_stock || 0,
       reorder_level || null, cost_per_unit || null, supplier_id || null,
       notes || null, lead_time_days || null]
    );
    res.status(201).json({ id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/inventory/:id  – full update
router.put('/:id', async (req, res) => {
  const { name, category, unit_of_measure, quantity_in_stock, reorder_level,
          cost_per_unit, supplier_id, notes, lead_time_days } = req.body;
  try {
    await query(
      `UPDATE unix_store_inventory
       SET name=?, category=?, unit_of_measure=?, quantity_in_stock=?,
           reorder_level=?, cost_per_unit=?, supplier_id=?, notes=?, lead_time_days=?
       WHERE id=?`,
      [name, category || null, unit_of_measure, quantity_in_stock,
       reorder_level || null, cost_per_unit || null, supplier_id || null,
       notes || null, lead_time_days || null, req.params.id]
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /api/inventory/:id/adjust  – adjust stock quantity
// body: { delta, reason?, new_cost_per_unit?, changed_by?, supplier_id?, total_cost? }
// • If new_cost_per_unit differs from current cost, logs to unix_cost_history.
// • If delta > 0 AND supplier_id + total_cost provided (delivery), automatically posts a
//   PURCHASE entry to unix_supplier_ledger so the debt is linked on the spot.
router.patch('/:id/adjust', async (req, res) => {
  const { delta, reason, new_cost_per_unit, changed_by, supplier_id, total_cost } = req.body;
  if (delta === undefined) return res.status(400).json({ error: 'delta is required' });
  try {
    // Fetch current item
    const current = await query(
      'SELECT cost_per_unit FROM unix_store_inventory WHERE id = ?',
      [req.params.id]
    );
    if (!current.length) return res.status(404).json({ error: 'Item not found' });

    const oldCost = current[0].cost_per_unit ? Number(current[0].cost_per_unit) : null;
    const newCost = new_cost_per_unit != null ? Number(new_cost_per_unit) : null;

    // Update stock (and cost if provided)
    if (newCost != null) {
      await query(
        `UPDATE unix_store_inventory
         SET quantity_in_stock = quantity_in_stock + ?, cost_per_unit = ?
         WHERE id = ?`,
        [delta, newCost, req.params.id]
      );
      // Log cost change if different from old cost
      if (oldCost !== newCost) {
        await query(
          `INSERT INTO unix_cost_history (id, inventory_item_id, old_cost, new_cost, changed_by)
           VALUES (?, ?, ?, ?, ?)`,
          [uuidv4(), req.params.id, oldCost, newCost, changed_by || null]
        );
      }
    } else {
      await query(
        `UPDATE unix_store_inventory
         SET quantity_in_stock = quantity_in_stock + ?
         WHERE id = ?`,
        [delta, req.params.id]
      );
    }

    // ── Link delivery to supplier ledger ────────────────────────────────────
    // When a positive delivery is tagged with a supplier + invoice cost,
    // automatically post a PURCHASE transaction to increase the supplier's debt.
    if (Number(delta) > 0 && supplier_id && total_cost && Number(total_cost) > 0) {
      const desc = reason && reason.trim()
        ? `Stock delivery — ${reason.trim()}`
        : 'Stock delivery (auto-linked from inventory receive)';
      await query(
        `INSERT INTO unix_supplier_ledger
           (id, supplier_id, transaction_type, amount, description, transaction_date)
         VALUES (?, ?, 'PURCHASE', ?, ?, CURDATE())`,
        [uuidv4(), supplier_id, Number(total_cost), desc]
      );
    }

    res.json({ ok: true, note: reason || null });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/inventory/waste  – log kitchen spoilage / wastage directly
// Creates an immediately-Issued requisition with purpose='Wastage'. No approval required.
// body: { inventory_item_id, quantity, notes, logged_by, requester_location? }
router.post('/waste', async (req, res) => {
  const { inventory_item_id, quantity, notes, logged_by, requester_location } = req.body;
  if (!inventory_item_id || !quantity || !logged_by) {
    return res.status(400).json({ error: 'inventory_item_id, quantity, and logged_by are required' });
  }
  if (Number(quantity) <= 0) {
    return res.status(400).json({ error: 'quantity must be positive' });
  }
  try {
    // Fetch item for UOM
    const items = await query(
      'SELECT id, name, unit_of_measure, quantity_in_stock FROM unix_store_inventory WHERE id = ?',
      [inventory_item_id]
    );
    if (!items.length) return res.status(404).json({ error: 'Inventory item not found' });
    const item = items[0];

    const id = uuidv4();
    const now = new Date();
    const isoNow = now.toISOString().slice(0, 19).replace('T', ' ');

    // Insert as an Issued requisition with purpose=Wastage
    await query(
      `INSERT INTO unix_requisitions
         (id, inventory_item_id, quantity, unit_of_measure, requested_by, purpose, status,
          notes, requester_location, issued_at, issued_by)
       VALUES (?, ?, ?, ?, ?, 'Wastage', 'Issued', ?, ?, ?, ?)`,
      [id, inventory_item_id, quantity, item.unit_of_measure,
       logged_by, notes || null, requester_location || null, isoNow, logged_by]
    );

    // Deduct stock immediately
    await query(
      'UPDATE unix_store_inventory SET quantity_in_stock = quantity_in_stock - ? WHERE id = ?',
      [quantity, inventory_item_id]
    );

    res.status(201).json({ id, item_name: item.name });
  } catch (err) {
    console.error(err);
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
