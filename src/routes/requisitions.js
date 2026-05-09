const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { query } = require('../db');

const router = express.Router();

// ── Timeline helper ────────────────────────────────────────────────────────────
// Logs a system event or user comment to store_requisition_timeline.
// Fire-and-forget: errors are only warned so they never block the main action.
async function logTimelineEvent(requisitionId, message, actorName = null, entryType = 'system') {
  try {
    await query(
      `INSERT INTO store_requisition_timeline (id, requisition_id, entry_type, actor_name, message)
       VALUES (?, ?, ?, ?, ?)`,
      [uuidv4(), requisitionId, entryType, actorName, message]
    );
  } catch (err) {
    console.warn('[timeline] failed to log event:', err.message);
  }
}

// ── Shared column fragment ─────────────────────────────────────────────────────
const REQ_COLS = `
  r.*,
  i.name               AS item_name,
  i.unit_of_measure    AS item_uom,
  COALESCE((
    SELECT COUNT(*) FROM store_requisition_timeline t
    WHERE t.requisition_id = r.id
  ), 0)                AS timeline_count
`;

// GET /api/requisitions  – list all (optionally filter by status / purpose)
router.get('/', async (req, res) => {
  const { status, purpose } = req.query;
  let sql = `
    SELECT ${REQ_COLS}
    FROM store_requisitions r
    LEFT JOIN store_inventory i ON i.id = r.inventory_item_id
    WHERE 1=1
  `;
  const params = [];
  if (status)  { sql += ' AND r.status = ?';  params.push(status); }
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

// GET /api/requisitions/pending  – shortcut for kitchen tablet
router.get('/pending', async (req, res) => {
  try {
    const rows = await query(`
      SELECT ${REQ_COLS}
      FROM store_requisitions r
      LEFT JOIN store_inventory i ON i.id = r.inventory_item_id
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
      `SELECT ${REQ_COLS}
       FROM store_requisitions r
       LEFT JOIN store_inventory i ON i.id = r.inventory_item_id
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
// Normal:    { inventory_item_id, quantity, unit_of_measure, requested_by, purpose, notes }
// New item:  { item_name, unit, quantity, requested_by, purpose?, notes? }
router.post('/', async (req, res) => {
  const { inventory_item_id, item_name, quantity, unit, unit_of_measure, requested_by, purpose, notes, requester_location } = req.body;

  if (!quantity || !requested_by) {
    return res.status(400).json({ error: 'quantity and requested_by are required' });
  }

  const isNewItem = !inventory_item_id && !!item_name;
  if (!isNewItem && !inventory_item_id) {
    return res.status(400).json({ error: 'inventory_item_id is required (or provide item_name for a new item request)' });
  }

  let resolvedNotes = notes || null;
  let resolvedUom   = unit_of_measure || unit || null;
  if (isNewItem) {
    const qtyUnit  = unit || unit_of_measure || 'pcs';
    const extra    = notes ? notes.trim() : '';
    resolvedNotes  = `[NEW ITEM REQUEST] Name: ${item_name.trim()} | Qty: ${quantity} ${qtyUnit}${extra ? ` | Notes: ${extra}` : ''}`;
    resolvedUom    = qtyUnit;
  }

  const id = uuidv4();
  try {
    await query(
      `INSERT INTO store_requisitions
         (id, inventory_item_id, quantity, unit_of_measure, requested_by, requester_location, purpose, notes)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [id, isNewItem ? null : inventory_item_id, quantity, resolvedUom,
       requested_by, requester_location || null, purpose || 'Sales', resolvedNotes]
    );

    // Log creation event
    const label = isNewItem ? `"${item_name.trim()}" (new item)` : `item`;
    await logTimelineEvent(id, `Requisition submitted by ${requested_by}.`, requested_by);

    res.status(201).json({ id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /api/requisitions/:id/issue
// Body: { issued_by, issued_quantity?, issue_notes? }
router.patch('/:id/issue', async (req, res) => {
  const { issued_by, issued_quantity, issue_notes } = req.body;
  if (!issued_by) return res.status(400).json({ error: 'issued_by is required' });

  const conn = (await require('../db').pool.getConnection());
  try {
    await conn.beginTransaction();

    const [[req_row]] = await conn.execute(
      'SELECT * FROM store_requisitions WHERE id = ? FOR UPDATE',
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

    const qtyToIssue = issued_quantity != null
      ? Number(issued_quantity)
      : Number(req_row.quantity);

    if (qtyToIssue <= 0) {
      await conn.rollback();
      return res.status(400).json({ error: 'issued_quantity must be greater than zero' });
    }

    // For new-item requests (inventory_item_id is NULL) skip stock check and deduction.
    if (req_row.inventory_item_id !== null) {
      const [[item]] = await conn.execute(
        'SELECT quantity_in_stock FROM store_inventory WHERE id = ?',
        [req_row.inventory_item_id]
      );
      if (Number(item.quantity_in_stock) < qtyToIssue) {
        await conn.rollback();
        return res.status(409).json({
          error: 'Insufficient stock',
          available: item.quantity_in_stock,
          requested: qtyToIssue,
        });
      }
      await conn.execute(
        'UPDATE store_inventory SET quantity_in_stock = quantity_in_stock - ? WHERE id = ?',
        [qtyToIssue, req_row.inventory_item_id]
      );
    }

    await conn.execute(
      `UPDATE store_requisitions
         SET status='Issued', issued_by=?, issued_at=NOW(),
             issued_quantity=?, issue_notes=?
       WHERE id=?`,
      [issued_by, qtyToIssue, issue_notes || null, req.params.id]
    );

    await conn.commit();

    // Log issue event (after commit — fire and forget)
    const uom = req_row.unit_of_measure || '';
    let eventMsg = `Issued by ${issued_by}. Quantity: ${qtyToIssue} ${uom}`.trim() + '.';
    if (issue_notes) eventMsg += ` Note: ${issue_notes}`;
    await logTimelineEvent(req.params.id, eventMsg, issued_by);

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
// Body: { reject_reason?, rejected_by? }
router.patch('/:id/reject', async (req, res) => {
  const { reject_reason, rejected_by } = req.body;
  try {
    const result = await query(
      `UPDATE store_requisitions SET status='Rejected', issue_notes=?
       WHERE id=? AND status='Pending'`,
      [reject_reason || null, req.params.id]
    );

    // Log rejection event
    const actor = rejected_by || 'Storekeeper';
    let eventMsg = `Rejected by ${actor}.`;
    if (reject_reason) eventMsg += ` Reason: ${reject_reason}`;
    await logTimelineEvent(req.params.id, eventMsg, actor || null);

    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Timeline endpoints ─────────────────────────────────────────────────────────

// GET /api/requisitions/:id/timeline  – fetch all entries (immutable audit log)
router.get('/:id/timeline', async (req, res) => {
  try {
    const rows = await query(
      `SELECT id, requisition_id, entry_type, actor_name, message, created_at
       FROM store_requisition_timeline
       WHERE requisition_id = ?
       ORDER BY created_at ASC`,
      [req.params.id]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/requisitions/:id/timeline  – add a user comment
// Body: { actor_name, message }
// No edit or delete endpoint — the timeline is immutable by design.
router.post('/:id/timeline', async (req, res) => {
  const { actor_name, message } = req.body;
  if (!message || !message.trim()) {
    return res.status(400).json({ error: 'message is required' });
  }
  if (!actor_name || !actor_name.trim()) {
    return res.status(400).json({ error: 'actor_name is required' });
  }

  // Verify the requisition exists
  try {
    const rows = await query('SELECT id FROM store_requisitions WHERE id = ?', [req.params.id]);
    if (!rows.length) return res.status(404).json({ error: 'Requisition not found' });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }

  const id = uuidv4();
  try {
    await query(
      `INSERT INTO store_requisition_timeline (id, requisition_id, entry_type, actor_name, message)
       VALUES (?, ?, 'comment', ?, ?)`,
      [id, req.params.id, actor_name.trim(), message.trim()]
    );
    res.status(201).json({ id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
