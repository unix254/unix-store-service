/**
 * Procurement List Generator
 *
 * Scans inventory items at or below reorder level, groups them by their
 * default_purchaser_id (an internal supplier / manager), and generates a
 * WhatsApp message per group routed to that manager's phone.
 *
 * Items with no default purchaser are grouped under "Unassigned".
 *
 * POST /api/procurement/generate  – generate lists + log + return WhatsApp links
 * GET  /api/procurement/logs      – history of generated lists
 */

const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { query } = require('../db');

const router = express.Router();

// ── Phone normalisation helper (Kenyan numbers) ───────────────────────────────
function normalisePhone(raw) {
  if (!raw) return '';
  let clean = raw.replace(/[^0-9]/g, '');
  if (clean.startsWith('0'))       clean = '254' + clean.substring(1);
  else if (clean.length === 9)     clean = '254' + clean;
  return clean;
}

// ── POST /api/procurement/generate ───────────────────────────────────────────
router.post('/generate', async (req, res) => {
  try {
    const { generated_by } = req.body;

    // Load business name for message header
    const settingsRows = await query(
      `SELECT setting_key, setting_value FROM unix_settings
       WHERE setting_key IN ('business_name', 'slogan')`
    );
    const settingsMap = {};
    settingsRows.forEach(r => settingsMap[r.setting_key] = r.setting_value);
    const busName = settingsMap['business_name'] || 'Yunix Store';

    // Fetch all items at or below reorder level, with their default purchaser info
    const items = await query(`
      SELECT
        i.id,
        i.name,
        i.unit_of_measure,
        i.quantity_in_stock,
        i.reorder_level,
        i.lead_time_days,
        i.default_purchaser_id,
        p.name  AS purchaser_name,
        p.phone AS purchaser_phone,
        GREATEST(0, ROUND(
          (COALESCE(i.reorder_level, 0) * 2)
          - i.quantity_in_stock
          + (COALESCE(usage30.daily_avg, 0) * COALESCE(i.lead_time_days, 1)),
          3
        )) AS suggested_qty
      FROM unix_store_inventory i
      LEFT JOIN unix_suppliers p ON p.id = i.default_purchaser_id AND p.is_internal = 1
      LEFT JOIN (
        SELECT inventory_item_id, ROUND(SUM(quantity) / 30, 3) AS daily_avg
        FROM unix_requisitions
        WHERE status = 'Issued'
          AND requested_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
        GROUP BY inventory_item_id
      ) usage30 ON usage30.inventory_item_id = i.id
      WHERE i.reorder_level IS NOT NULL
        AND i.quantity_in_stock <= i.reorder_level
      ORDER BY p.name, i.name
    `);

    if (!items.length) {
      return res.json({ ok: true, message: 'No items currently below reorder level.', groups: [] });
    }

    // Group items by purchaser
    const groupMap = {};
    for (const item of items) {
      const key = item.default_purchaser_id || '__unassigned__';
      if (!groupMap[key]) {
        groupMap[key] = {
          purchaser_id:    item.default_purchaser_id || null,
          purchaser_name:  item.purchaser_name       || 'Unassigned',
          purchaser_phone: item.purchaser_phone       || null,
          items: [],
        };
      }
      groupMap[key].items.push({
        id:             item.id,
        name:           item.name,
        unit:           item.unit_of_measure,
        in_stock:       Number(item.quantity_in_stock),
        reorder_level:  Number(item.reorder_level),
        suggested_qty:  Number(item.suggested_qty),
      });
    }

    const today = new Date().toLocaleDateString('en-KE', {
      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
      timeZone: 'Africa/Nairobi',
    });

    // Build WhatsApp URL per group
    const groups = Object.values(groupMap).map(group => {
      const itemLines = group.items
        .map(it => `  • ${it.name}: ${it.suggested_qty} ${it.unit}  (stock: ${it.in_stock})`)
        .join('\r\n');

      const message = [
        `*PROCUREMENT LIST – ${busName}*`,
        `${today}`,
        ``,
        `Hi ${group.purchaser_name}, please purchase the following items:`,
        ``,
        `─────────────────────────`,
        itemLines,
        `─────────────────────────`,
        ``,
        `Quantities shown are suggested based on reorder levels and lead times.`,
        `Please confirm purchases and update stock on delivery.`,
        ``,
        `*${busName}*`,
      ].join('\r\n');

      const encoded = encodeURIComponent(message)
        .replace(/%0A/g, '%0D%0A')
        .replace(/%0D%0D%0A/g, '%0D%0A');

      const cleanPhone = normalisePhone(group.purchaser_phone);
      const whatsapp_url = cleanPhone
        ? `https://api.whatsapp.com/send?phone=${cleanPhone}&text=${encoded}`
        : `https://api.whatsapp.com/send?text=${encoded}`;

      return { ...group, message, whatsapp_url };
    });

    // Log the generation
    const logId = uuidv4();
    await query(
      `INSERT INTO unix_procurement_logs (id, generated_by, item_count, groups_json)
       VALUES (?, ?, ?, ?)`,
      [logId, generated_by || null, items.length, JSON.stringify(
        groups.map(g => ({
          purchaser_id:   g.purchaser_id,
          purchaser_name: g.purchaser_name,
          item_count:     g.items.length,
          items:          g.items.map(i => ({ name: i.name, suggested_qty: i.suggested_qty, unit: i.unit })),
        }))
      )]
    );

    res.json({ ok: true, log_id: logId, item_count: items.length, groups });
  } catch (err) {
    console.error('procurement/generate error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ── POST /api/procurement/build-whatsapp ─────────────────────────────────────
// Accepts pre-built (possibly user-adjusted) groups and returns WhatsApp URLs.
// Body: { groups: [{ purchaser_name, purchaser_phone, items: [{ name, unit, qty }] }] }
// This allows the Flutter UI to send edited/ad-hoc procurement lists to this endpoint
// and receive formatted WhatsApp deep-links without hitting generate again.
router.post('/build-whatsapp', async (req, res) => {
  try {
    const { groups } = req.body;
    if (!Array.isArray(groups) || groups.length === 0) {
      return res.status(400).json({ error: 'groups array is required' });
    }

    const settingsRows = await query(
      `SELECT setting_key, setting_value FROM unix_settings
       WHERE setting_key IN ('business_name', 'slogan')`
    );
    const sm = {};
    settingsRows.forEach(r => sm[r.setting_key] = r.setting_value);
    const busName = sm['business_name'] || 'Yunix Store';

    const today = new Date().toLocaleDateString('en-KE', {
      weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
      timeZone: 'Africa/Nairobi',
    });

    const result = groups.map(group => {
      const items = (group.items || []);
      const itemLines = items
        .map(it => `  • ${it.name}: ${Number(it.qty).toFixed(
          Number(it.qty) % 1 === 0 ? 0 : 1
        )} ${it.unit || ''}`)
        .join('\r\n');

      const message = [
        `*PROCUREMENT LIST – ${busName}*`,
        `${today}`,
        ``,
        `Hi ${group.purchaser_name || 'Team'}, please purchase the following items:`,
        ``,
        `─────────────────────────`,
        itemLines,
        `─────────────────────────`,
        ``,
        `Quantities shown are confirmed by the Storekeeper.`,
        `Please update stock on delivery.`,
        ``,
        `*${busName}*`,
      ].join('\r\n');

      const encoded = encodeURIComponent(message)
        .replace(/%0A/g, '%0D%0A')
        .replace(/%0D%0D%0A/g, '%0D%0A');

      const cleanPhone = normalisePhone(group.purchaser_phone);
      const whatsapp_url = cleanPhone
        ? `https://api.whatsapp.com/send?phone=${cleanPhone}&text=${encoded}`
        : `https://api.whatsapp.com/send?text=${encoded}`;

      return { ...group, message, whatsapp_url };
    });

    res.json({ ok: true, groups: result });
  } catch (err) {
    console.error('procurement/build-whatsapp error:', err);
    res.status(500).json({ error: err.message });
  }
});

// ── GET /api/procurement/logs ─────────────────────────────────────────────────
router.get('/logs', async (req, res) => {
  try {
    const rows = await query(`
      SELECT id, generated_at, generated_by, item_count, groups_json
      FROM unix_procurement_logs
      ORDER BY generated_at DESC
      LIMIT 50
    `);
    res.json(rows.map(r => ({
      ...r,
      groups_json: typeof r.groups_json === 'string'
        ? JSON.parse(r.groups_json)
        : r.groups_json,
    })));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
