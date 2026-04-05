/**
 * Pay Runs — Smart Daily Supplier Payment Batching
 *
 * Flow: Draft → Submitted → Approved → Disbursed
 *
 * The Manager creates a run, adds suppliers (auto-populated from debt alerts),
 * adjusts approved amounts, then generates a WhatsApp deep link for the Owner to review.
 * Once approved (in-app by Manager after Owner confirmation), disburse zeroes the ledger.
 */

const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { query } = require('../db');

const router = express.Router();

// ── Helper ────────────────────────────────────────────────────────────────────

async function recalcTotals(payRunId) {
  await query(`
    UPDATE unix_pay_runs pr
    SET
      total_requested = (
        SELECT COALESCE(SUM(d.requested_amount), 0)
        FROM unix_pay_run_details d
        WHERE d.pay_run_id = pr.id AND d.status = 'Included'
      ),
      total_approved = (
        SELECT COALESCE(SUM(d.approved_amount), 0)
        FROM unix_pay_run_details d
        WHERE d.pay_run_id = pr.id AND d.status = 'Included'
      )
    WHERE pr.id = ?
  `, [payRunId]);
}

// ── Routes ────────────────────────────────────────────────────────────────────

// GET /api/pay-runs  – list all pay runs, newest first
router.get('/', async (req, res) => {
  try {
    const rows = await query(`
      SELECT pr.*,
             COUNT(d.id)                          AS supplier_count,
             SUM(d.status = 'Included')           AS included_count,
             SUM(d.status = 'Postponed')          AS postponed_count
      FROM unix_pay_runs pr
      LEFT JOIN unix_pay_run_details d ON d.pay_run_id = pr.id
      GROUP BY pr.id
      ORDER BY pr.run_date DESC, pr.created_at DESC
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/pay-runs/today  – today's run (create draft if none exists)
router.get('/today', async (req, res) => {
  const today = new Date().toISOString().slice(0, 10);
  try {
    let rows = await query(
      'SELECT * FROM unix_pay_runs WHERE run_date = ? AND status != "Disbursed" ORDER BY created_at DESC LIMIT 1',
      [today]
    );
    if (rows.length) return res.json(rows[0]);

    // Auto-create a draft run for today
    const id = uuidv4();
    const token = uuidv4();
    await query(
      `INSERT INTO unix_pay_runs (id, run_date, status, approval_token, total_requested, total_approved)
       VALUES (?, ?, 'Draft', ?, 0, 0)`,
      [id, today, token]
    );
    rows = await query('SELECT * FROM unix_pay_runs WHERE id = ?', [id]);
    res.json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/pay-runs/:id  – get a pay run with full detail rows + supplier info
router.get('/:id', async (req, res) => {
  try {
    const runs = await query('SELECT * FROM unix_pay_runs WHERE id = ?', [req.params.id]);
    if (!runs.length) return res.status(404).json({ error: 'Pay run not found' });

    const details = await query(`
      SELECT d.*, s.name AS supplier_name, s.phone AS supplier_phone, s.payment_day
      FROM unix_pay_run_details d
      JOIN unix_suppliers s ON s.id = d.supplier_id
      WHERE d.pay_run_id = ?
      ORDER BY d.status, s.name
    `, [req.params.id]);

    res.json({ ...runs[0], details });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// POST /api/pay-runs/:id/auto-populate
// Auto-adds all suppliers with outstanding debt to this run (skips already-added ones).
router.post('/:id/auto-populate', async (req, res) => {
  try {
    const run = await query('SELECT * FROM unix_pay_runs WHERE id = ?', [req.params.id]);
    if (!run.length) return res.status(404).json({ error: 'Pay run not found' });
    if (run[0].status !== 'Draft') {
      return res.status(400).json({ error: 'Only Draft runs can be modified' });
    }

    // Get all suppliers with positive balance, excluding already-added ones
    const debtors = await query(`
      SELECT
        s.id,
        COALESCE(SUM(CASE WHEN l.transaction_type = 'PURCHASE' THEN l.amount ELSE 0 END), 0)
          - COALESCE(SUM(CASE WHEN l.transaction_type = 'PAYMENT'  THEN l.amount ELSE 0 END), 0)
          AS balance_due
      FROM unix_suppliers s
      LEFT JOIN unix_supplier_ledger l ON l.supplier_id = s.id
      WHERE s.id NOT IN (
        SELECT supplier_id FROM unix_pay_run_details WHERE pay_run_id = ?
      )
      GROUP BY s.id
      HAVING balance_due > 0
    `, [req.params.id]);

    for (const d of debtors) {
      await query(
        `INSERT INTO unix_pay_run_details (id, pay_run_id, supplier_id, requested_amount, approved_amount, status)
         VALUES (?, ?, ?, ?, ?, 'Included')`,
        [uuidv4(), req.params.id, d.id, d.balance_due, d.balance_due]
      );
    }
    await recalcTotals(req.params.id);
    res.json({ added: debtors.length });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// POST /api/pay-runs/:id/details  – manually add a supplier to the run
router.post('/:id/details', async (req, res) => {
  const { supplier_id, requested_amount, approved_amount, notes } = req.body;
  if (!supplier_id || requested_amount == null) {
    return res.status(400).json({ error: 'supplier_id and requested_amount are required' });
  }
  try {
    const run = await query('SELECT status FROM unix_pay_runs WHERE id = ?', [req.params.id]);
    if (!run.length) return res.status(404).json({ error: 'Pay run not found' });
    if (run[0].status !== 'Draft') {
      return res.status(400).json({ error: 'Only Draft runs can be modified' });
    }

    const id = uuidv4();
    const approved = approved_amount ?? requested_amount;
    await query(
      `INSERT INTO unix_pay_run_details (id, pay_run_id, supplier_id, requested_amount, approved_amount, notes, status)
       VALUES (?, ?, ?, ?, ?, ?, 'Included')`,
      [id, req.params.id, supplier_id, requested_amount, approved, notes || null]
    );
    await recalcTotals(req.params.id);
    res.status(201).json({ id });
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') {
      return res.status(409).json({ error: 'Supplier already in this pay run' });
    }
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/pay-runs/:id/details/:detailId  – update approved_amount or status
router.put('/:id/details/:detailId', async (req, res) => {
  const { approved_amount, status, notes } = req.body;
  try {
    const run = await query('SELECT status FROM unix_pay_runs WHERE id = ?', [req.params.id]);
    if (!run.length) return res.status(404).json({ error: 'Pay run not found' });
    if (run[0].status === 'Disbursed') {
      return res.status(400).json({ error: 'Disbursed runs cannot be modified' });
    }

    await query(
      `UPDATE unix_pay_run_details
       SET approved_amount = COALESCE(?, approved_amount),
           status = COALESCE(?, status),
           notes  = COALESCE(?, notes)
       WHERE id = ? AND pay_run_id = ?`,
      [approved_amount ?? null, status ?? null, notes ?? null, req.params.detailId, req.params.id]
    );
    await recalcTotals(req.params.id);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /api/pay-runs/:id/details/:detailId  – remove a supplier from the run
router.delete('/:id/details/:detailId', async (req, res) => {
  try {
    await query(
      'DELETE FROM unix_pay_run_details WHERE id = ? AND pay_run_id = ?',
      [req.params.detailId, req.params.id]
    );
    await recalcTotals(req.params.id);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /api/pay-runs/:id/submit  – submit for owner approval (Draft → Submitted)
router.patch('/:id/submit', async (req, res) => {
  const { created_by } = req.body;
  try {
    await query(
      `UPDATE unix_pay_runs SET status = 'Submitted', created_by = COALESCE(?, created_by)
       WHERE id = ? AND status = 'Draft'`,
      [created_by || null, req.params.id]
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /api/pay-runs/:id/approve  – owner-approved (Submitted → Approved)
router.patch('/:id/approve', async (req, res) => {
  try {
    await query(
      `UPDATE unix_pay_runs SET status = 'Approved' WHERE id = ? AND status = 'Submitted'`,
      [req.params.id]
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /api/pay-runs/:id/disburse
// Marks run as Disbursed, marks included details as Paid,
// and zeroes out the approved_amount from each supplier's ledger balance
// by inserting PAYMENT ledger entries.
router.patch('/:id/disburse', async (req, res) => {
  const { disbursed_by } = req.body;
  try {
    const run = await query('SELECT * FROM unix_pay_runs WHERE id = ?', [req.params.id]);
    if (!run.length) return res.status(404).json({ error: 'Pay run not found' });
    if (run[0].status !== 'Approved') {
      return res.status(400).json({ error: 'Only Approved runs can be disbursed' });
    }

    const details = await query(
      `SELECT d.*, s.name AS supplier_name
       FROM unix_pay_run_details d
       JOIN unix_suppliers s ON s.id = d.supplier_id
       WHERE d.pay_run_id = ? AND d.status = 'Included'`,
      [req.params.id]
    );

    const today = new Date().toISOString().slice(0, 10);

    for (const d of details) {
      // Post a PAYMENT to the supplier ledger
      await query(
        `INSERT INTO unix_supplier_ledger
           (id, supplier_id, transaction_type, amount, description, transaction_date)
         VALUES (?, ?, 'PAYMENT', ?, ?, ?)`,
        [uuidv4(), d.supplier_id, d.approved_amount,
         `Pay Run disbursement${disbursed_by ? ' by ' + disbursed_by : ''}`,
         today]
      );
      // Mark detail as Paid
      await query(
        `UPDATE unix_pay_run_details SET status = 'Paid' WHERE id = ?`,
        [d.id]
      );
    }

    await query(
      `UPDATE unix_pay_runs SET status = 'Disbursed' WHERE id = ?`,
      [req.params.id]
    );
    await recalcTotals(req.params.id);

    res.json({ ok: true, suppliers_paid: details.length });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/pay-runs/:id/whatsapp
// Generates a WhatsApp deep-link message for the Owner to review and approve the pay run.
router.get('/:id/whatsapp', async (req, res) => {
  try {
    const runs = await query('SELECT * FROM unix_pay_runs WHERE id = ?', [req.params.id]);
    if (!runs.length) return res.status(404).json({ error: 'Pay run not found' });
    const run = runs[0];

    const details = await query(`
      SELECT d.approved_amount, s.name AS supplier_name
      FROM unix_pay_run_details d
      JOIN unix_suppliers s ON s.id = d.supplier_id
      WHERE d.pay_run_id = ? AND d.status = 'Included'
      ORDER BY s.name
    `, [req.params.id]);

    const storeUrl = process.env.PUBLIC_URL || 'https://store-dev.unixpos.com';
    const total = details.reduce((sum, d) => sum + Number(d.approved_amount), 0);

    const lines = details.map(d =>
      `  • ${d.supplier_name}: KES ${Number(d.approved_amount).toFixed(2)}`
    ).join('\n');

    const message = [
      `*PAYMENT RUN APPROVAL – Yunix Store*`,
      `Date: ${run.run_date}`,
      ``,
      `Please review the following supplier payments:`,
      ``,
      lines,
      ``,
      `*Total: KES ${total.toFixed(2)}*`,
      ``,
      `To approve, open the store controller:`,
      `${storeUrl}`,
      ``,
      `Reply *APPROVED* to confirm, or call to discuss changes.`,
      `_Sent via Yunix Store Controller_`
    ].join('\n');

    const ownerPhone = req.query.phone;
    const whatsappUrl = ownerPhone
      ? `https://wa.me/${ownerPhone.replace(/[^0-9]/g, '')}?text=${encodeURIComponent(message)}`
      : `https://wa.me/?text=${encodeURIComponent(message)}`;

    res.json({ ok: true, message, whatsapp_url: whatsappUrl, total });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
