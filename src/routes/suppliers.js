const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { query } = require('../db');

const router = express.Router();

// GET /api/suppliers  – list all suppliers with their current balance
router.get('/', async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        s.*,
        COALESCE(SUM(CASE WHEN l.transaction_type = 'PURCHASE' THEN l.amount ELSE 0 END), 0)
          - COALESCE(SUM(CASE WHEN l.transaction_type = 'PAYMENT'  THEN l.amount ELSE 0 END), 0)
          AS balance_due
      FROM unix_suppliers s
      LEFT JOIN unix_supplier_ledger l ON l.supplier_id = s.id
      GROUP BY s.id
      ORDER BY s.name
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/suppliers/:id
router.get('/:id', async (req, res) => {
  try {
    const rows = await query('SELECT * FROM unix_suppliers WHERE id = ?', [req.params.id]);
    if (!rows.length) return res.status(404).json({ error: 'Supplier not found' });
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/suppliers
router.post('/', async (req, res) => {
  const { name, phone, location, payment_day, lead_time_days, notes } = req.body;
  if (!name) return res.status(400).json({ error: 'name is required' });
  const id = uuidv4();
  try {
    await query(
      `INSERT INTO unix_suppliers (id, name, phone, location, payment_day, lead_time_days, notes)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [id, name, phone || null, location || null, payment_day || null, lead_time_days || 1, notes || null]
    );
    res.status(201).json({ id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/suppliers/:id
router.put('/:id', async (req, res) => {
  const { name, phone, location, payment_day, lead_time_days, notes } = req.body;
  try {
    await query(
      `UPDATE unix_suppliers SET name=?, phone=?, location=?, payment_day=?, lead_time_days=?, notes=?
       WHERE id=?`,
      [name, phone || null, location || null, payment_day || null, lead_time_days || 1, notes || null, req.params.id]
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /api/suppliers/:id
router.delete('/:id', async (req, res) => {
  try {
    await query('DELETE FROM unix_suppliers WHERE id = ?', [req.params.id]);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Ledger sub-routes ────────────────────────────────────────

// GET /api/suppliers/:id/ledger  – full transaction history + running balance
router.get('/:id/ledger', async (req, res) => {
  try {
    const entries = await query(
      `SELECT * FROM unix_supplier_ledger WHERE supplier_id = ? ORDER BY transaction_date, created_at`,
      [req.params.id]
    );
    let balance = 0;
    const withBalance = entries.map(e => {
      balance += e.transaction_type === 'PURCHASE' ? Number(e.amount) : -Number(e.amount);
      return { ...e, running_balance: Number(balance.toFixed(2)) };
    });
    res.json(withBalance);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/suppliers/:id/ledger  – record a PURCHASE or PAYMENT
router.post('/:id/ledger', async (req, res) => {
  const { transaction_type, amount, description, reference_doc, transaction_date } = req.body;
  if (!transaction_type || !amount || !transaction_date) {
    return res.status(400).json({ error: 'transaction_type, amount, and transaction_date are required' });
  }
  if (!['PURCHASE', 'PAYMENT'].includes(transaction_type)) {
    return res.status(400).json({ error: 'transaction_type must be PURCHASE or PAYMENT' });
  }
  const id = uuidv4();
  try {
    await query(
      `INSERT INTO unix_supplier_ledger (id, supplier_id, transaction_type, amount, description, reference_doc, transaction_date)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [id, req.params.id, transaction_type, amount, description || null, reference_doc || null, transaction_date]
    );
    res.status(201).json({ id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/suppliers/alerts/upcoming-debt
// Returns suppliers with balance due, sorted by urgency (payment_day nearest)
router.get('/alerts/upcoming-debt', async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        s.id, s.name, s.phone, s.payment_day, s.lead_time_days,
        COALESCE(SUM(CASE WHEN l.transaction_type = 'PURCHASE' THEN l.amount ELSE 0 END), 0)
          - COALESCE(SUM(CASE WHEN l.transaction_type = 'PAYMENT'  THEN l.amount ELSE 0 END), 0)
          AS balance_due
      FROM unix_suppliers s
      LEFT JOIN unix_supplier_ledger l ON l.supplier_id = s.id
      GROUP BY s.id
      HAVING balance_due > 0
      ORDER BY balance_due DESC
    `);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Order Message (SMS / WhatsApp Stub) ─────────────────────

// POST /api/suppliers/:id/order
// Builds a formatted order message and returns it as a preview.
// Future: integrate Africa's Talking (SMS) or WhatsApp Business API.
// Body: { items: [{ name, quantity, unit }], note: "optional" }
router.post('/:id/order', async (req, res) => {
  const { items, note } = req.body;
  if (!items || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: 'items array is required' });
  }
  try {
    const rows = await query('SELECT * FROM unix_suppliers WHERE id = ?', [req.params.id]);
    if (!rows.length) return res.status(404).json({ error: 'Supplier not found' });
    const supplier = rows[0];

    const today = new Date().toLocaleDateString('en-KE', {
      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
    });

    const itemLines = items
      .map(it => `  • ${it.quantity} ${it.unit} – ${it.name}`)
      .join('\n');

    const storeUrl = process.env.PUBLIC_URL || 'https://store-dev.unixpos.com';

    const message = [
      `*ORDER REQUEST – Yunix Store*`,
      `Date: ${today}`,
      ``,
      `Hello *${supplier.name}*,`,
      `Please prepare the following order:`,
      ``,
      itemLines,
      note ? `\nNote: ${note}` : '',
      ``,
      `Kindly confirm availability and delivery time.`,
      `Thank you.`,
      ``,
      `_Sent via Yunix Store Controller_`,
      `_${storeUrl}_`
    ].filter(l => l !== undefined).join('\n');

    const whatsappUrl = supplier.phone
      ? `https://wa.me/${supplier.phone.replace(/[^0-9]/g, '')}?text=${encodeURIComponent(message)}`
      : null;

    res.json({
      ok: true,
      supplier: { name: supplier.name, phone: supplier.phone },
      message,
      whatsapp_url: whatsappUrl,
      note: 'SMS/WhatsApp API integration pending. Use whatsapp_url to open in browser.'
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
