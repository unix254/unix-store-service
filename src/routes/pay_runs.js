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
    UPDATE store_pay_runs pr
    SET
      total_requested = (
        SELECT COALESCE(SUM(d.requested_amount), 0)
        FROM store_pay_run_details d
        WHERE d.pay_run_id = pr.id AND d.status = 'Included'
      ),
      total_approved = (
        SELECT COALESCE(SUM(d.approved_amount), 0)
        FROM store_pay_run_details d
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
      FROM store_pay_runs pr
      LEFT JOIN store_pay_run_details d ON d.pay_run_id = pr.id
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
      'SELECT * FROM store_pay_runs WHERE run_date = ? AND status != "Disbursed" ORDER BY created_at DESC LIMIT 1',
      [today]
    );
    if (rows.length) return res.json(rows[0]);

    // Auto-create a draft run for today
    const id = uuidv4();
    const token = uuidv4();
    await query(
      `INSERT INTO store_pay_runs (id, run_date, status, approval_token, total_requested, total_approved)
       VALUES (?, ?, 'Draft', ?, 0, 0)`,
      [id, today, token]
    );
    rows = await query('SELECT * FROM store_pay_runs WHERE id = ?', [id]);
    res.json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/pay-runs/:id  – get a pay run with full detail rows + supplier info
router.get('/:id', async (req, res) => {
  try {
    const runs = await query('SELECT * FROM store_pay_runs WHERE id = ?', [req.params.id]);
    if (!runs.length) return res.status(404).json({ error: 'Pay run not found' });

    const details = await query(`
      SELECT d.*, s.name AS supplier_name, s.phone AS supplier_phone, s.payment_day
      FROM store_pay_run_details d
      JOIN store_suppliers s ON s.id = d.supplier_id
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
    const run = await query('SELECT * FROM store_pay_runs WHERE id = ?', [req.params.id]);
    if (!run.length) return res.status(404).json({ error: 'Pay run not found' });
    if (run[0].status !== 'Draft') {
      return res.status(400).json({ error: 'Only Draft runs can be modified' });
    }

    // Get all suppliers with positive balance, excluding already-added ones
    const debtors = await query(`
      SELECT
        s.id,
        COALESCE(SUM(CASE WHEN l.transaction_type IN ('PURCHASE','SUPPLIER_PAYMENT') THEN l.amount ELSE 0 END), 0)
          - COALESCE(SUM(CASE WHEN l.transaction_type IN ('PAYMENT','CASH_IN') THEN l.amount ELSE 0 END), 0)
          AS balance_due
      FROM store_suppliers s
      LEFT JOIN store_supplier_ledger l ON l.supplier_id = s.id
      WHERE s.id NOT IN (
        SELECT supplier_id FROM store_pay_run_details WHERE pay_run_id = ?
      )
      GROUP BY s.id
      HAVING balance_due > 0
    `, [req.params.id]);

    for (const d of debtors) {
      await query(
        `INSERT INTO store_pay_run_details (id, pay_run_id, supplier_id, requested_amount, approved_amount, status)
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
    const run = await query('SELECT status FROM store_pay_runs WHERE id = ?', [req.params.id]);
    if (!run.length) return res.status(404).json({ error: 'Pay run not found' });
    if (run[0].status !== 'Draft') {
      return res.status(400).json({ error: 'Only Draft runs can be modified' });
    }

    const id = uuidv4();
    const approved = approved_amount ?? requested_amount;
    await query(
      `INSERT INTO store_pay_run_details (id, pay_run_id, supplier_id, requested_amount, approved_amount, notes, status)
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
    const run = await query('SELECT status FROM store_pay_runs WHERE id = ?', [req.params.id]);
    if (!run.length) return res.status(404).json({ error: 'Pay run not found' });
    if (run[0].status === 'Disbursed') {
      return res.status(400).json({ error: 'Disbursed runs cannot be modified' });
    }

    await query(
      `UPDATE store_pay_run_details
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
      'DELETE FROM store_pay_run_details WHERE id = ? AND pay_run_id = ?',
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
      `UPDATE store_pay_runs SET status = 'Submitted', created_by = COALESCE(?, created_by)
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
      `UPDATE store_pay_runs SET status = 'Approved' WHERE id = ? AND status = 'Submitted'`,
      [req.params.id]
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /api/pay-runs/:id/finalize
// Manager-led shortcut: transition a Draft run directly to Approved,
// bypassing the Submitted / owner-WhatsApp-approval step entirely.
// Phase 7: pay run ownership is now fully with Managers.
router.patch('/:id/finalize', async (req, res) => {
  try {
    const result = await query(
      `UPDATE store_pay_runs SET status = 'Approved' WHERE id = ? AND status = 'Draft'`,
      [req.params.id]
    );
    if (result.affectedRows === 0) {
      return res.status(400).json({ error: 'Pay run must be in Draft status to finalize' });
    }
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// PATCH /api/pay-runs/:id/details/:detailId/disburse
// Disburses a single supplier row within an Approved pay run.
// Body: { disbursed_by, payment_source_supplier_id?, payment_reference? }
//
// Double-entry when payment_source_supplier_id (internal supplier) is provided:
//   1. PAYMENT on external supplier ledger      → reduces their debt
//   2. SUPPLIER_PAYMENT on internal supplier ledger → records manager cash used
//      (distinct from PURCHASE which is ad-hoc petty cash buys by the manager)
//
// After all Included details are Paid, the run is auto-marked Disbursed.
router.patch('/:id/details/:detailId/disburse', async (req, res) => {
  const { disbursed_by, payment_source_supplier_id, payment_reference } = req.body;
  try {
    const run = await query('SELECT * FROM store_pay_runs WHERE id = ?', [req.params.id]);
    if (!run.length) return res.status(404).json({ error: 'Pay run not found' });
    if (run[0].status !== 'Approved') {
      return res.status(400).json({ error: 'Only Approved runs can be disbursed' });
    }

    const details = await query(
      `SELECT d.*, s.name AS supplier_name, s.id AS supplier_id_ref
       FROM store_pay_run_details d
       JOIN store_suppliers s ON s.id = d.supplier_id
       WHERE d.id = ? AND d.pay_run_id = ?`,
      [req.params.detailId, req.params.id]
    );
    if (!details.length) return res.status(404).json({ error: 'Detail not found' });
    const d = details[0];
    if (d.status === 'Paid') return res.status(400).json({ error: 'Already disbursed' });
    if (d.status !== 'Included') return res.status(400).json({ error: 'Only Included rows can be disbursed' });

    // Validate payment source is an internal supplier if provided
    if (payment_source_supplier_id) {
      const src = await query(
        'SELECT id, name, is_internal FROM store_suppliers WHERE id = ?',
        [payment_source_supplier_id]
      );
      if (!src.length) return res.status(400).json({ error: 'Payment source supplier not found' });
      if (!src[0].is_internal) return res.status(400).json({ error: 'Payment source must be an internal expense account' });
    }

    // Load business name for description context
    const settingsRows = await query(
      `SELECT setting_value FROM yunix_settings WHERE setting_key = 'business_name' LIMIT 1`
    );
    const busName = settingsRows.length ? settingsRows[0].setting_value : 'Store';

    const today = new Date().toISOString().slice(0, 10);
    const ref   = payment_reference ? ` (Ref: ${payment_reference})` : '';
    const by    = disbursed_by ? ` by ${disbursed_by}` : '';

    // 1. PAYMENT on external supplier ledger
    await query(
      `INSERT INTO store_supplier_ledger
         (id, supplier_id, transaction_type, amount, description, reference_doc, transaction_date)
       VALUES (?, ?, 'PAYMENT', ?, ?, ?, ?)`,
      [uuidv4(), d.supplier_id, d.approved_amount,
       `Pay Run payment${by}${ref}`,
       payment_reference || null, today]
    );

    // 2. Double-entry: SUPPLIER_PAYMENT on internal supplier ledger
    //    This is distinct from PURCHASE (ad-hoc cash buy). It shows the manager
    //    acted as a payment intermediary for a prequalified external supplier.
    if (payment_source_supplier_id) {
      await query(
        `INSERT INTO store_supplier_ledger
           (id, supplier_id, transaction_type, amount, description, reference_doc, transaction_date, related_supplier_id)
         VALUES (?, ?, 'SUPPLIER_PAYMENT', ?, ?, ?, ?, ?)`,
        [uuidv4(), payment_source_supplier_id, d.approved_amount,
         `Supplier Payment on behalf of ${busName} – Paid to ${d.supplier_name}${ref}`,
         payment_reference || null, today,
         d.supplier_id]   // link back to the external supplier
      );
    }

    // Mark detail as Paid
    await query(
      `UPDATE store_pay_run_details
       SET status = 'Paid', disbursed_by = ?, disbursed_at = NOW(),
           payment_source_id = ?, payment_reference = ?
       WHERE id = ?`,
      [disbursed_by || null, payment_source_supplier_id || null,
       payment_reference || null, d.id]
    );

    // Auto-close run if all Included rows are now Paid
    const remaining = await query(
      `SELECT COUNT(*) AS cnt FROM store_pay_run_details
       WHERE pay_run_id = ? AND status = 'Included'`,
      [req.params.id]
    );
    if (Number(remaining[0].cnt) === 0) {
      await query(`UPDATE store_pay_runs SET status = 'Disbursed' WHERE id = ?`, [req.params.id]);
    }
    await recalcTotals(req.params.id);

    res.json({ ok: true, run_closed: Number(remaining[0].cnt) === 0 });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/pay-runs/:id/whatsapp
// Generates a WhatsApp deep-link message for the Owner to review and approve the pay run.
router.get('/:id/whatsapp', async (req, res) => {
  try {
    const runs = await query('SELECT * FROM store_pay_runs WHERE id = ?', [req.params.id]);
    if (!runs.length) return res.status(404).json({ error: 'Pay run not found' });
    const run = runs[0];

    const details = await query(`
      SELECT d.approved_amount, s.name AS supplier_name
      FROM store_pay_run_details d
      JOIN store_suppliers s ON s.id = d.supplier_id
      WHERE d.pay_run_id = ? AND d.status = 'Included'
      ORDER BY s.name
    `, [req.params.id]);

    // Load business settings (name, slogan, owner contact)
    const settingsRows = await query(
      `SELECT setting_key, setting_value FROM yunix_settings
       WHERE setting_key IN ('business_name', 'slogan', 'owner_name', 'owner_phone')`
    );
    const settingsMap = {};
    settingsRows.forEach(r => settingsMap[r.setting_key] = r.setting_value);
    const busName    = settingsMap['business_name'] || 'Yunix Store';
    const slogan     = settingsMap['slogan']         || 'Powered by Yunix';
    const ownerName  = settingsMap['owner_name']     || '';
    // Phone from settings takes priority; fall back to query param
    const ownerPhoneRaw = settingsMap['owner_phone'] || req.query.phone || '';

    const storeUrl = process.env.PUBLIC_URL || 'https://store-dev.unixpos.com';
    const total    = details.reduce((sum, d) => sum + Number(d.approved_amount), 0);

    const paymentLines = details.map(d =>
      `  • ${d.supplier_name}: KES ${Number(d.approved_amount).toFixed(2)}`
    ).join('\r\n');

    // Format the date properly for East Africa Time without the ugly GMT string
    const runDateObj = new Date(run.run_date);
    const runDateStr = isNaN(runDateObj.valueOf()) ? run.run_date : runDateObj.toLocaleDateString('en-KE', {
      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', timeZone: 'Africa/Nairobi'
    });

    const greeting = ownerName ? `Hi ${ownerName},` : `Hi,`;

    const message = [
      `*PAYMENT RUN APPROVAL REQUEST*`,
      `*${busName}* | ${runDateStr}`,
      ``,
      `${greeting} please review and approve the following supplier payments:`,
      ``,
      `───────────────`,
      paymentLines,
      `───────────────`,
      ``,
      `*TOTAL: KES ${total.toFixed(2)}*`,
      ``,
      `To approve, open the store controller:`,
      `${storeUrl}`,
      ``,
      `Click APPROVED to confirm, or contact the team to discuss changes.`,
      ``,
      `*${busName}*`,
      `_${slogan}_`
    ].join('\r\n');

    // Force strict %0D%0A (CRLF) encoding — prevents Windows from eating line breaks
    const encodedMessage = encodeURIComponent(message)
      .replace(/%0A/g, '%0D%0A')
      .replace(/%0D%0D%0A/g, '%0D%0A');

    // Normalise phone to Kenyan international format (254xxxxxxxxx)
    // Settings-stored owner_phone takes priority over query param
    let cleanPhone = ownerPhoneRaw.replace(/[^0-9]/g, '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '254' + cleanPhone.substring(1);
    } else if (cleanPhone.length === 9) {
      cleanPhone = '254' + cleanPhone;
    }

    // api.whatsapp.com/send works reliably in both browser and WhatsApp Web
    const whatsappUrl = cleanPhone
      ? `https://api.whatsapp.com/send?phone=${cleanPhone}&text=${encodedMessage}`
      : `https://api.whatsapp.com/send?text=${encodedMessage}`;

    res.json({ ok: true, message, whatsapp_url: whatsappUrl, total });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
