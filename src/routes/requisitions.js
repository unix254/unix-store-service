const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { query } = require('../db');

const router = express.Router();

// GET /api/requisitions  – list all (optionally filter by status)
router.get('/', async (req, res) => {
  const { status, purpose } = req.query;
  let sql = `
    SELECT r.*, i.name AS item_name, i.unit_of_measure AS item_uom
    FROM unix_requisitions r
    LEFT JOIN unix_store_inventory i ON i.id = r.inventory_item_id
    WHERE 1=1
  `;
  const params = [];
  if (status) { sql += ' AND r.status = ?'; params.push(status); }
  if (purpose) { sql += ' AND r.purpose = ?'; params.push(purpose); }
  sql += ' ORDER BY r.requested_at DESC';

  try {
    const rows = await query(sql, params);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/requisitions/pending  – shortcut for kitchen tablet display
router.get('/pending', async (req, res) => {
  try {
    const rows = await query(`
      SELECT r.*, i.name AS item_name, i.unit_of_measure AS item_uom
      FROM unix_requisitions r
      LEFT JOIN unix_store_inventory i ON i.id = r.inventory_item_id
      WHERE r.status = 'Pending'
      ORDER BY r.requested_at ASC
    `);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/requisitions/:id
router.get('/:id', async (req, res) => {
  try {
    const rows = await query(
      `SELECT r.*, i.name AS item_name, i.unit_of_measure AS item_uom
       FROM unix_requisitions r
       LEFT JOIN unix_store_inventory i ON i.id = r.inventory_item_id
       WHERE r.id = ?`,
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ error: 'Requisition not found' });
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/requisitions  – kitchen raises a request
// Normal request: { inventory_item_id, quantity, unit_of_measure, requested_by, purpose, notes }
// New item request: { item_name, unit, quantity, requested_by, purpose?, notes? }
//   → inventory_item_id is stored as NULL; notes is prefixed with [NEW ITEM REQUEST].
router.post('/', async (req, res) => {
  const { inventory_item_id, item_name, quantity, unit, unit_of_measure, requested_by, purpose, notes } = req.body;

  if (!quantity || !requested_by) {
    return res.status(400).json({ error: 'quantity and requested_by are required' });
  }

  // Determine if this is a new-item request
  const isNewItem = !inventory_item_id && !!item_name;
  if (!isNewItem && !inventory_item_id) {
    return res.status(400).json({ error: 'inventory_item_id is required (or provide item_name for a new item request)' });
  }

  // Build structured notes for new-item requests
  let resolvedNotes = notes || null;
  let resolvedUom = unit_of_measure || unit || null;
  if (isNewItem) {
    const qtyUnit = unit || unit_of_measure || 'pcs';
    const extra = notes ? notes.trim() : '';
    resolvedNotes = `[NEW ITEM REQUEST] Name: ${item_name.trim()} | Qty: ${quantity} ${qtyUnit}${extra ? ` | Notes: ${extra}` : ''}`;
    resolvedUom = qtyUnit;
  }

  const id = uuidv4();
  try {
    await query(
      `INSERT INTO unix_requisitions
         (id, inventory_item_id, quantity, unit_of_measure, requested_by, purpose, notes)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [id, isNewItem ? null : inventory_item_id, quantity, resolvedUom,
       requested_by, purpose || 'Sales', resolvedNotes]
    );
    res.status(201).json({ id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /api/requisitions/:id/issue
// Store keeper issues (approves + deducts stock) in one action.
// Body: { issued_by, issued_quantity?, issue_notes? }
//   issued_quantity: optional override — allows issuing less (or more) than requested.
//                   If omitted, the full requested quantity is used.
//   issue_notes:    optional reason/explanation (e.g. "Only 2kg left in store").
router.patch('/:id/issue', async (req, res) => {
  const { issued_by, issued_quantity, issue_notes } = req.body;
  if (!issued_by) return res.status(400).json({ error: 'issued_by is required' });

  const conn = (await require('../db').pool.getConnection());
  try {
    await conn.beginTransaction();

    const [[req_row]] = await conn.execute(
      'SELECT * FROM unix_requisitions WHERE id = ? FOR UPDATE',
      [req.params.id]
    );
    if (!req_row) {
      await conn.rollback();
      return res.status(404).json({ error: 'Requisition not found' });
    }
    if (req_row.status !== 'Pending') {
      await conn.rollback();
      return res.status(409).json({ error: `Cannot issue a requisition with status '${req_row.status}'` });
    }

    // Resolve the actual quantity to record (override or full request)
    const qtyToIssue = issued_quantity != null
      ? Number(issued_quantity)
      : Number(req_row.quantity);

    if (qtyToIssue <= 0) {
      await conn.rollback();
      return res.status(400).json({ error: 'issued_quantity must be greater than zero' });
    }

    // For new-item requests (inventory_item_id is NULL), skip stock check and deduction.
    // The storekeeper is simply acknowledging the request and will add the item manually.
    if (req_row.inventory_item_id !== null) {
      // Check available stock
      const [[item]] = await conn.execute(
        'SELECT quantity_in_stock FROM unix_store_inventory WHERE id = ?',
        [req_row.inventory_item_id]
      );
      if (Number(item.quantity_in_stock) < qtyToIssue) {
        await conn.rollback();
        return res.status(409).json({
          error: 'Insufficient stock',
          available: item.quantity_in_stock,
          requested: qtyToIssue
        });
      }

      // Deduct stock
      await conn.execute(
        'UPDATE unix_store_inventory SET quantity_in_stock = quantity_in_stock - ? WHERE id = ?',
        [qtyToIssue, req_row.inventory_item_id]
      );
    }

    // Mark requisition as Issued, saving the actual issued quantity and any notes
    await conn.execute(
      `UPDATE unix_requisitions
         SET status='Issued', issued_by=?, issued_at=NOW(),
             issued_quantity=?, issue_notes=?
       WHERE id=?`,
      [issued_by, qtyToIssue, issue_notes || null, req.params.id]
    );

    await conn.commit();
    res.json({ ok: true, issued_quantity: qtyToIssue });
  } catch (err) {
    await conn.rollback();
    console.error(err);
    res.status(500).json({ error: err.message });
  } finally {
    conn.release();
  }
});

// PATCH /api/requisitions/:id/reject
// Body: { reject_reason? }  – optional explanation stored in issue_notes.
router.patch('/:id/reject', async (req, res) => {
  const { reject_reason } = req.body;
  try {
    await query(
      `UPDATE unix_requisitions SET status='Rejected', issue_notes=?
       WHERE id=? AND status='Pending'`,
      [reject_reason || null, req.params.id]
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
