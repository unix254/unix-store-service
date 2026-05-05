const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { query } = require('../db');

const router = express.Router();

// GET /api/suppliers  – list all suppliers with their current balance
// For external suppliers: PURCHASE increases debt, PAYMENT decreases it.
// For internal suppliers (managers): PURCHASE + SUPPLIER_PAYMENT + OTHER_EXPENSE are debits
//   (cash spent from the float), PAYMENT + CASH_IN are credits (float replenishment).
router.get('/', async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        s.*,
        COALESCE(SUM(CASE WHEN l.transaction_type IN ('PURCHASE','SUPPLIER_PAYMENT','OTHER_EXPENSE') THEN l.amount ELSE 0 END), 0)
          - COALESCE(SUM(CASE WHEN l.transaction_type IN ('PAYMENT','CASH_IN') THEN l.amount ELSE 0 END), 0)
          AS balance_due
      FROM store_suppliers s
      LEFT JOIN store_supplier_ledger l ON l.supplier_id = s.id
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
    const rows = await query('SELECT * FROM store_suppliers WHERE id = ?', [req.params.id]);
    if (!rows.length) return res.status(404).json({ error: 'Supplier not found' });
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/suppliers
router.post('/', async (req, res) => {
  const { name, phone, location, payment_day, lead_time_days, notes, is_internal } = req.body;
  if (!name) return res.status(400).json({ error: 'name is required' });
  const id = uuidv4();
  try {
    await query(
      `INSERT INTO store_suppliers (id, name, phone, location, payment_day, lead_time_days, notes, is_internal)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [id, name, phone || null, location || null, payment_day || null, lead_time_days || 1,
       notes || null, is_internal ? 1 : 0]
    );
    res.status(201).json({ id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/suppliers/:id
router.put('/:id', async (req, res) => {
  const { name, phone, location, payment_day, lead_time_days, notes, is_internal } = req.body;
  try {
    await query(
      `UPDATE store_suppliers SET name=?, phone=?, location=?, payment_day=?, lead_time_days=?, notes=?, is_internal=?
       WHERE id=?`,
      [name, phone || null, location || null, payment_day || null, lead_time_days || 1,
       notes || null, is_internal ? 1 : 0, req.params.id]
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /api/suppliers/:id
router.delete('/:id', async (req, res) => {
  try {
    await query('DELETE FROM store_suppliers WHERE id = ?', [req.params.id]);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Ledger sub-routes ────────────────────────────────────────

// GET /api/suppliers/:id/ledger  – full transaction history + running balance
// Optional: ?from=YYYY-MM-DD&to=YYYY-MM-DD to filter by date range.
// Joins related_supplier_id → name so the UI can show "Paid to [Supplier X]".
router.get('/:id/ledger', async (req, res) => {
  const { from, to } = req.query;
  try {
    let sql = `
      SELECT l.*,
             rs.name AS related_supplier_name
      FROM store_supplier_ledger l
      LEFT JOIN store_suppliers rs ON rs.id = l.related_supplier_id
      WHERE l.supplier_id = ?
    `;
    const params = [req.params.id];
    if (from) { sql += ' AND l.transaction_date >= ?'; params.push(from); }
    if (to)   { sql += ' AND l.transaction_date <= ?'; params.push(to); }
    sql += ' ORDER BY l.transaction_date, l.created_at';

    const entries = await query(sql, params);
    let balance = 0;
    const withBalance = entries.map(e => {
      const isDebit = e.transaction_type === 'PURCHASE'
                   || e.transaction_type === 'SUPPLIER_PAYMENT'
                   || e.transaction_type === 'OTHER_EXPENSE';
      balance += isDebit ? Number(e.amount) : -Number(e.amount);
      return { ...e, running_balance: Number(balance.toFixed(2)) };
    });
    res.json(withBalance);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/suppliers/:id/ledger  – manually record a PURCHASE, PAYMENT, CASH_IN, or OTHER_EXPENSE
// SUPPLIER_PAYMENT is created automatically by the pay run disburse route.
// CASH_IN is used on internal (manager) accounts to record bank withdrawals / float top-ups.
// OTHER_EXPENSE is a catch-all debit for miscellaneous float spending not linked to a supplier.
router.post('/:id/ledger', async (req, res) => {
  const { transaction_type, amount, description, reference_doc, transaction_date } = req.body;
  if (!transaction_type || !amount || !transaction_date) {
    return res.status(400).json({ error: 'transaction_type, amount, and transaction_date are required' });
  }
  if (!['PURCHASE', 'PAYMENT', 'CASH_IN', 'OTHER_EXPENSE'].includes(transaction_type)) {
    return res.status(400).json({ error: 'transaction_type must be PURCHASE, PAYMENT, CASH_IN, or OTHER_EXPENSE' });
  }
  const id = uuidv4();
  try {
    await query(
      `INSERT INTO store_supplier_ledger (id, supplier_id, transaction_type, amount, description, reference_doc, transaction_date)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      [id, req.params.id, transaction_type, amount, description || null, reference_doc || null, transaction_date]
    );
    res.status(201).json({ id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────
// GET /api/suppliers/:id/statement
// Returns a structured statement summary for a supplier.
// Query params: ?days=30  (default: last 30 days)
// Response includes opening balance, period totals, closing balance.
// ─────────────────────────────────────────────────────────────
router.get('/:id/statement', async (req, res) => {
  try {
    const supplier = await query('SELECT * FROM store_suppliers WHERE id = ?', [req.params.id]);
    if (!supplier.length) return res.status(404).json({ error: 'Supplier not found' });
    const s = supplier[0];

    const today = new Date();
    const todayStr = today.toISOString().slice(0, 10);
    // Accept explicit from/to date params; fall back to days-based window.
    let periodStartStr, days;
    if (req.query.from && req.query.to) {
      periodStartStr = req.query.from;
      const toStr    = req.query.to <= todayStr ? req.query.to : todayStr;
      days = Math.ceil((new Date(toStr) - new Date(periodStartStr)) / 86400000) + 1;
    } else {
      days = parseInt(req.query.days, 10) || 30;
      const periodStart = new Date(today);
      periodStart.setDate(today.getDate() - days);
      periodStartStr = periodStart.toISOString().slice(0, 10);
    }
    const endStr = req.query.to && req.query.to <= todayStr ? req.query.to : todayStr;

    // Opening balance: all transactions BEFORE the period
    const openRows = await query(
      `SELECT
         COALESCE(SUM(CASE WHEN transaction_type IN ('PURCHASE','SUPPLIER_PAYMENT','OTHER_EXPENSE') THEN amount ELSE 0 END), 0)
           - COALESCE(SUM(CASE WHEN transaction_type IN ('PAYMENT','CASH_IN') THEN amount ELSE 0 END), 0)
           AS opening_balance
       FROM store_supplier_ledger
       WHERE supplier_id = ? AND transaction_date < ?`,
      [req.params.id, periodStartStr]
    );
    const openingBalance = Number(openRows[0].opening_balance);

    // Period entries
    const periodRows = await query(
      `SELECT l.*, rs.name AS related_supplier_name
       FROM store_supplier_ledger l
       LEFT JOIN store_suppliers rs ON rs.id = l.related_supplier_id
       WHERE l.supplier_id = ?
         AND l.transaction_date >= ? AND l.transaction_date <= ?
       ORDER BY l.transaction_date, l.created_at`,
      [req.params.id, periodStartStr, endStr]
    );

    let purchases = 0, supplierPayments = 0, otherExpenses = 0, payments = 0, cashIns = 0;
    for (const r of periodRows) {
      if (r.transaction_type === 'PURCHASE')         purchases        += Number(r.amount);
      if (r.transaction_type === 'SUPPLIER_PAYMENT') supplierPayments += Number(r.amount);
      if (r.transaction_type === 'OTHER_EXPENSE')    otherExpenses    += Number(r.amount);
      if (r.transaction_type === 'PAYMENT')          payments         += Number(r.amount);
      if (r.transaction_type === 'CASH_IN')          cashIns          += Number(r.amount);
    }

    const totalDebits   = purchases + supplierPayments + otherExpenses;
    const totalCredits  = payments + cashIns;
    const closingBalance = openingBalance + totalDebits - totalCredits;

    // Load business name for message formatting
    const settingsRows = await query(
      `SELECT setting_key, setting_value FROM yunix_settings WHERE setting_key IN ('business_name','slogan')`
    );
    const sm = {};
    settingsRows.forEach(r => sm[r.setting_key] = r.setting_value);

    res.json({
      supplier: { id: s.id, name: s.name, phone: s.phone, is_internal: !!s.is_internal },
      period: { start: periodStartStr, end: endStr, days },
      opening_balance:          Number(openingBalance.toFixed(2)),
      period_purchases:         Number(purchases.toFixed(2)),
      period_supplier_payments: Number(supplierPayments.toFixed(2)),
      period_other_expenses:    Number(otherExpenses.toFixed(2)),
      period_payments:          Number(payments.toFixed(2)),
      period_cash_ins:          Number(cashIns.toFixed(2)),
      closing_balance:          Number(closingBalance.toFixed(2)),
      entries: periodRows,
      business_name: sm['business_name'] || 'Yunix Store',
      slogan: sm['slogan'] || 'Powered by Yunix',
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ─────────────────────────────────────────────────────────────
// GET /api/suppliers/:id/statement/whatsapp
// Generates a formatted WhatsApp mini-statement URL.
// Query params: ?days=30  OR  ?from=YYYY-MM-DD&to=YYYY-MM-DD
// ─────────────────────────────────────────────────────────────
router.get('/:id/statement/whatsapp', async (req, res) => {
  try {
    const supplier = await query('SELECT * FROM store_suppliers WHERE id = ?', [req.params.id]);
    if (!supplier.length) return res.status(404).json({ error: 'Supplier not found' });
    const s = supplier[0];

    const today = new Date();
    const todayStr = today.toISOString().slice(0, 10);
    let periodStartStr, endStr, days;
    if (req.query.from && req.query.to) {
      periodStartStr = req.query.from;
      endStr = req.query.to <= todayStr ? req.query.to : todayStr;
      days = Math.ceil((new Date(endStr) - new Date(periodStartStr)) / 86400000) + 1;
    } else {
      days = parseInt(req.query.days, 10) || 30;
      const periodStart = new Date(today);
      periodStart.setDate(today.getDate() - days);
      periodStartStr = periodStart.toISOString().slice(0, 10);
      endStr = todayStr;
    }

    const openRows = await query(
      `SELECT
         COALESCE(SUM(CASE WHEN transaction_type IN ('PURCHASE','SUPPLIER_PAYMENT','OTHER_EXPENSE') THEN amount ELSE 0 END), 0)
           - COALESCE(SUM(CASE WHEN transaction_type IN ('PAYMENT','CASH_IN') THEN amount ELSE 0 END), 0)
           AS opening_balance
       FROM store_supplier_ledger
       WHERE supplier_id = ? AND transaction_date < ?`,
      [req.params.id, periodStartStr]
    );
    const openingBalance = Number(openRows[0].opening_balance);

    const periodRows = await query(
      `SELECT transaction_type, amount FROM store_supplier_ledger
       WHERE supplier_id = ? AND transaction_date >= ? AND transaction_date <= ?`,
      [req.params.id, periodStartStr, endStr]
    );

    let purchases = 0, supplierPayments = 0, otherExpenses = 0, payments = 0, cashIns = 0;
    for (const r of periodRows) {
      if (r.transaction_type === 'PURCHASE')         purchases        += Number(r.amount);
      if (r.transaction_type === 'SUPPLIER_PAYMENT') supplierPayments += Number(r.amount);
      if (r.transaction_type === 'OTHER_EXPENSE')    otherExpenses    += Number(r.amount);
      if (r.transaction_type === 'PAYMENT')          payments         += Number(r.amount);
      if (r.transaction_type === 'CASH_IN')          cashIns          += Number(r.amount);
    }
    const closingBalance = openingBalance + purchases + supplierPayments + otherExpenses - payments - cashIns;

    const settingsRows = await query(
      `SELECT setting_key, setting_value FROM yunix_settings WHERE setting_key IN ('business_name','slogan')`
    );
    const sm = {};
    settingsRows.forEach(r => sm[r.setting_key] = r.setting_value);
    const busName = sm['business_name'] || 'Yunix Store';
    const slogan  = sm['slogan']  || 'Powered by Yunix';

    const fmt = (n) => `KES ${Math.abs(n).toLocaleString('en-KE', { minimumFractionDigits: 2 })}`;
    const periodLabel = `${periodStartStr} to ${endStr}`;

    // Build mini-statement message (WhatsApp-friendly)
    const isInternal = !!s.is_internal;
    let lines;

    if (isInternal) {
      // Manager float statement: show full breakdown as requested in Phase 7
      lines = [
        `*MANAGER FLOAT STATEMENT – ${busName}*`,
        ``,
        `*${s.name}*`,
        `Period: ${periodLabel} (last ${days} days)`,
        ``,
        `───────────────────────`,
        `Opening Float:              ${fmt(openingBalance)}`,
        ``,
        `💰 Cash Received from Bank: ${fmt(cashIns)}`,
        `🧾 Used to Pay Suppliers:   ${fmt(supplierPayments)}`,
        `🛒 Ad-Hoc Expenses:         ${fmt(purchases)}`,
        `📋 Other Expenses:          ${fmt(otherExpenses)}`,
        `↩️ Payments Reimbursed:     ${fmt(payments)}`,
        `───────────────────────`,
        `*Running Float Balance:  ${fmt(closingBalance)}*`,
        closingBalance > 0
          ? `_(Manager has ${fmt(closingBalance)} outstanding)_`
          : `_(Float fully accounted for)_`,
        ``,
        `*${busName}*`,
        `_${slogan}_`,
      ];
    } else {
      // External supplier statement (unchanged)
      lines = [
        `*ACCOUNT STATEMENT – ${busName}*`,
        ``,
        `*${s.name}*`,
        `Period: ${periodLabel} (last ${days} days)`,
        ``,
        `───────────────────────`,
        `Opening Balance:   ${fmt(openingBalance)}`,
        `Total Purchases:   ${fmt(purchases + supplierPayments)}`,
        `Payments Received: ${fmt(payments)}`,
        `───────────────────────`,
        `*Closing Balance:  ${fmt(closingBalance)}*`,
        closingBalance > 0 ? `_(Amount outstanding)_` : `_(Account settled)_`,
        ``,
        `*${busName}*`,
        `_${slogan}_`,
      ];
    }

    const message = lines.join('\r\n');

    const encoded = encodeURIComponent(message)
      .replace(/%0A/g, '%0D%0A')
      .replace(/%0D%0D%0A/g, '%0D%0A');

    let cleanPhone = (s.phone || '').replace(/[^0-9]/g, '');
    if (cleanPhone.startsWith('0')) cleanPhone = '254' + cleanPhone.substring(1);
    else if (cleanPhone.length === 9) cleanPhone = '254' + cleanPhone;

    const whatsappUrl = cleanPhone
      ? `https://api.whatsapp.com/send?phone=${cleanPhone}&text=${encoded}`
      : `https://api.whatsapp.com/send?text=${encoded}`;

    res.json({ ok: true, message, whatsapp_url: whatsappUrl });
  } catch (err) {
    console.error(err);
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
        COALESCE(SUM(CASE WHEN l.transaction_type IN ('PURCHASE','SUPPLIER_PAYMENT','OTHER_EXPENSE') THEN l.amount ELSE 0 END), 0)
          - COALESCE(SUM(CASE WHEN l.transaction_type IN ('PAYMENT','CASH_IN') THEN l.amount ELSE 0 END), 0)
          AS balance_due
      FROM store_suppliers s
      LEFT JOIN store_supplier_ledger l ON l.supplier_id = s.id
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
    const rows = await query('SELECT * FROM store_suppliers WHERE id = ?', [req.params.id]);
    if (!rows.length) return res.status(404).json({ error: 'Supplier not found' });
    const supplier = rows[0];

    const today = new Date().toLocaleDateString('en-KE', {
      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
    });

    const emojiGreen = String.fromCodePoint(0x1F7E2);   // 🟢
    const emojiDate = String.fromCodePoint(0x1F4C5);    // 📅
    const emojiDiamond = String.fromCodePoint(0x1F539); // 🔹

    const itemLines = items
      .map(it => `  ${emojiDiamond} ${it.quantity} ${it.unit} – ${it.name}`)
      .join('\r\n');

    const settingsRows = await query(`SELECT setting_key, setting_value FROM yunix_settings WHERE setting_key IN ('business_name', 'slogan')`);
    const settingsMap = {};
    settingsRows.forEach(r => settingsMap[r.setting_key] = r.setting_value);
    const busName = settingsMap['business_name'] || 'Yunix Store';
    const slogan = settingsMap['slogan'] || 'Powered by Yunix';

    const message = [
      `${emojiGreen} *NEW ORDER REQUEST: ${busName}* | ${emojiDate} ${today}`,
      ``,
      `Hi *${supplier.name}*, `,
      `Please prepare the following items for delivery:`,
      ``,
      itemLines,
      ``,
      note ? `Note: ${note}` : null,
      `Kindly reply to confirm availability and expected delivery time. Thank you!`,
      ``,
      `*${busName}*`,
      `_${slogan}_`
    ].filter(l => l !== null && l !== undefined).join('\r\n');

    // Force strict %0D%0A (CRLF) encoding for Windows Desktop WhatsApp protocol handler
    // This physically prevents Windows from eating the line breaks when routing the URI.
    const encodedMessage = encodeURIComponent(message)
        .replace(/%0A/g, '%0D%0A')
        .replace(/%0D%0D%0A/g, '%0D%0A');

    let cleanPhone = supplier.phone ? supplier.phone.replace(/[^0-9]/g, '') : '';
    
    // Format to Kenyan international code (254) if missing
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '254' + cleanPhone.substring(1);
    } else if (cleanPhone.length === 9) {
      cleanPhone = '254' + cleanPhone;
    }

    // Switch back to api.whatsapp.com/send because it reliably resolved the phone number
    // in the earlier versions. We include the %0D%0A fix from before.
    const whatsappUrl = cleanPhone
      ? `https://api.whatsapp.com/send?phone=${cleanPhone}&text=${encodedMessage}`
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
