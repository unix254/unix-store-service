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
        s.name  AS supplier_name,
        s.payment_day AS supplier_payment_day,
        s.lead_time_days AS supplier_lead_time_days,
        p.name  AS default_purchaser_name,
        (i.reorder_level IS NOT NULL AND i.quantity_in_stock <= i.reorder_level) AS needs_reorder
      FROM store_inventory i
      LEFT JOIN store_suppliers s ON s.id = i.supplier_id
      LEFT JOIN store_suppliers p ON p.id = i.default_purchaser_id
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
      FROM store_inventory i
      LEFT JOIN store_suppliers s ON s.id = i.supplier_id
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
      FROM store_inventory i
      LEFT JOIN store_suppliers s ON s.id = i.supplier_id
      LEFT JOIN (
        SELECT inventory_item_id,
               ROUND(SUM(quantity) / 30, 3) AS daily_avg
        FROM store_requisitions
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
      `SELECT * FROM store_cost_history WHERE inventory_item_id = ? ORDER BY changed_at DESC LIMIT 50`,
      [req.params.id]
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/inventory/inflation-summary
// Returns cost changes in the last 30 days, enriched with yield config + POS product data.
// Used by the dedicated Price Impact Advisory screen in the BI Hub.
// Query param: ?days=30 (optional, defaults to 30)
router.get('/inflation-summary', async (req, res) => {
  const days = Math.min(Math.max(parseInt(req.query.days) || 30, 1), 365);
  try {
    const rows = await query(`
      SELECT
        i.id                                                           AS inventory_id,
        i.name                                                         AS inventory_name,
        i.unit_of_measure,
        i.cost_per_unit                                                AS current_cost,
        ch.old_cost,
        ch.new_cost,
        ch.changed_at,
        ROUND(COALESCE(weekly.qty, 0), 3)                             AS weekly_usage,
        ROUND((ch.new_cost - COALESCE(ch.old_cost, ch.new_cost))
              * COALESCE(weekly.qty, 0), 2)                           AS weekly_impact_kes,
        -- Yield config linkage
        yc.id                                                          AS yield_config_id,
        yc.portions_per_unit,
        -- POS product details (from uniCenta read-only tables)
        p.id                                                           AS pos_product_id,
        p.name                                                         AS pos_product_name,
        p.pricesell                                                    AS pos_sell_price,
        -- Cost rise per portion for this ingredient-product pair
        CASE
          WHEN yc.portions_per_unit > 0
          THEN ROUND((ch.new_cost - COALESCE(ch.old_cost, ch.new_cost))
                     / yc.portions_per_unit, 4)
          ELSE NULL
        END                                                            AS cost_rise_per_portion
      FROM store_cost_history ch
      JOIN store_inventory i ON i.id = ch.inventory_item_id
      JOIN (
        SELECT inventory_item_id, changed_at,
               ROW_NUMBER() OVER (PARTITION BY inventory_item_id ORDER BY changed_at DESC) AS rn
        FROM store_cost_history
        WHERE changed_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
      ) latest ON latest.inventory_item_id = ch.inventory_item_id
              AND latest.changed_at = ch.changed_at
      LEFT JOIN (
        SELECT inventory_item_id, ROUND(SUM(quantity) / 4, 3) AS qty
        FROM store_requisitions
        WHERE status = 'Issued'
          AND requested_at >= DATE_SUB(CURDATE(), INTERVAL 28 DAY)
        GROUP BY inventory_item_id
      ) weekly ON weekly.inventory_item_id = i.id
      -- Join yield configs so we know which POS products use this ingredient
      LEFT JOIN store_yield_config yc ON yc.inventory_item_id = i.id
                                     AND yc.portions_per_unit > 0
      -- Join POS products table (read-only uniCenta table)
      LEFT JOIN products p ON p.id = yc.unicenta_product_id
      WHERE latest.rn = 1
      ORDER BY ABS(weekly_impact_kes) DESC, i.name ASC
    `, [days]);

    // Group by inventory item so each item appears once with an array of impacted products
    const grouped = {};
    for (const row of rows) {
      const key = row.inventory_id;
      if (!grouped[key]) {
        grouped[key] = {
          inventory_id:    row.inventory_id,
          name:            row.inventory_name,
          unit_of_measure: row.unit_of_measure,
          current_cost:    row.current_cost,
          old_cost:        row.old_cost,
          new_cost:        row.new_cost,
          changed_at:      row.changed_at,
          weekly_usage:    row.weekly_usage,
          weekly_impact_kes: row.weekly_impact_kes,
          // Legacy fields kept for backwards compat (heatmap chip format)
          id:              row.inventory_id,
          impacted_products: [],
        };
      }
      if (row.pos_product_id && row.pos_product_name) {
        grouped[key].impacted_products.push({
          pos_product_id:      row.pos_product_id,
          pos_product_name:    row.pos_product_name,
          pos_sell_price:      row.pos_sell_price,
          portions_per_unit:   row.portions_per_unit,
          cost_rise_per_portion: row.cost_rise_per_portion,
        });
      }
    }

    res.json(Object.values(grouped));
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// POST /api/inventory/send-price-impact
// Formats the price-impact report as a WhatsApp-ready text message and returns
// a deep-link URL (opens WhatsApp with the message pre-filled).
// Body: { phone?: string, days?: number }
router.post('/send-price-impact', async (req, res) => {
  const days = Math.min(Math.max(parseInt(req.body.days) || 30, 1), 365);
  const phone = req.body.phone ? String(req.body.phone).replace(/\D/g, '') : null;

  try {
    const rows = await query(`
      SELECT
        i.name                                                         AS inventory_name,
        i.unit_of_measure,
        ch.old_cost,
        ch.new_cost,
        ROUND(COALESCE(weekly.qty, 0), 3)                             AS weekly_usage,
        ROUND((ch.new_cost - COALESCE(ch.old_cost, ch.new_cost))
              * COALESCE(weekly.qty, 0), 2)                           AS weekly_impact_kes,
        p.name                                                         AS pos_product_name,
        p.pricesell                                                    AS pos_sell_price,
        CASE
          WHEN yc.portions_per_unit > 0
          THEN ROUND((ch.new_cost - COALESCE(ch.old_cost, ch.new_cost))
                     / yc.portions_per_unit, 2)
          ELSE NULL
        END                                                            AS cost_rise_per_portion
      FROM store_cost_history ch
      JOIN store_inventory i ON i.id = ch.inventory_item_id
      JOIN (
        SELECT inventory_item_id, changed_at,
               ROW_NUMBER() OVER (PARTITION BY inventory_item_id ORDER BY changed_at DESC) AS rn
        FROM store_cost_history
        WHERE changed_at >= DATE_SUB(NOW(), INTERVAL ? DAY)
      ) latest ON latest.inventory_item_id = ch.inventory_item_id
              AND latest.changed_at = ch.changed_at
      LEFT JOIN (
        SELECT inventory_item_id, ROUND(SUM(quantity) / 4, 3) AS qty
        FROM store_requisitions
        WHERE status = 'Issued'
          AND requested_at >= DATE_SUB(CURDATE(), INTERVAL 28 DAY)
        GROUP BY inventory_item_id
      ) weekly ON weekly.inventory_item_id = i.id
      LEFT JOIN store_yield_config yc ON yc.inventory_item_id = i.id AND yc.portions_per_unit > 0
      LEFT JOIN products p ON p.id = yc.unicenta_product_id
      WHERE latest.rn = 1
      ORDER BY ABS(weekly_impact_kes) DESC, i.name ASC
    `, [days]);

    if (!rows.length) {
      return res.json({ ok: true, message: null, whatsapp_url: null,
        info: 'No cost changes found in the last ' + days + ' days.' });
    }

    // Build message
    const today = new Date().toLocaleDateString('en-KE', { day: '2-digit', month: 'short', year: 'numeric' });
    const lines = [];
    lines.push(`📊 *YUNIX STORE — Price Impact Report*`);
    lines.push(`_Last ${days} days  •  Generated ${today}_`);
    lines.push('');

    // Group by ingredient
    const seen = {};
    for (const row of rows) {
      const key = row.inventory_name;
      if (!seen[key]) {
        const pctChange = row.old_cost > 0
          ? Math.round(((row.new_cost - row.old_cost) / row.old_cost) * 100)
          : 0;
        const arrow = row.new_cost > row.old_cost ? '🔺' : '🔻';
        lines.push(`${arrow} *${row.inventory_name}*`);
        lines.push(`   KES ${Number(row.old_cost).toFixed(0)} → *KES ${Number(row.new_cost).toFixed(0)}* (${pctChange > 0 ? '+' : ''}${pctChange}%)`);
        if (Number(row.weekly_impact_kes) !== 0) {
          lines.push(`   Weekly impact: *KES ${Number(row.weekly_impact_kes).toFixed(0)}*`);
        }
        seen[key] = true;
      }
      if (row.pos_product_name && row.cost_rise_per_portion != null) {
        lines.push(`   › ${row.pos_product_name}: +KES ${Number(row.cost_rise_per_portion).toFixed(2)}/portion  _(sells @ KES ${Number(row.pos_sell_price).toFixed(0)})_`);
      }
      lines.push('');
    }

    lines.push('_Please review selling prices to maintain target margins._');
    lines.push('_— YUNIX Store System_');

    const message = lines.join('\n');
    const encoded = encodeURIComponent(message);
    const whatsappUrl = phone
      ? `https://api.whatsapp.com/send?phone=${phone}&text=${encoded}`
      : `https://api.whatsapp.com/send?text=${encoded}`;

    res.json({ ok: true, message, whatsapp_url: whatsappUrl });
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
       FROM store_inventory i
       LEFT JOIN store_suppliers s ON s.id = i.supplier_id
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
          cost_per_unit, supplier_id, notes, lead_time_days, default_purchaser_id,
          risk_tier } = req.body;
  if (!name) return res.status(400).json({ error: 'name is required' });
  if (!unit_of_measure) return res.status(400).json({ error: 'unit_of_measure is required' });
  const id = uuidv4();
  try {
    await query(
      `INSERT INTO store_inventory
         (id, name, category, unit_of_measure, quantity_in_stock, reorder_level,
          cost_per_unit, supplier_id, notes, lead_time_days, default_purchaser_id, risk_tier)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [id, name, category || null, unit_of_measure, quantity_in_stock || 0,
       reorder_level || null, cost_per_unit || null, supplier_id || null,
       notes || null, lead_time_days || null, default_purchaser_id || null,
       risk_tier || null]
    );
    res.status(201).json({ id });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/inventory/:id  – full update
router.put('/:id', async (req, res) => {
  const { name, category, unit_of_measure, quantity_in_stock, reorder_level,
          cost_per_unit, supplier_id, notes, lead_time_days, default_purchaser_id,
          risk_tier } = req.body;
  const validRiskTiers = ['High', 'Standard', 'Low', null, undefined];
  if (risk_tier !== undefined && !validRiskTiers.includes(risk_tier)) {
    return res.status(400).json({ error: 'risk_tier must be High, Standard, Low, or null' });
  }
  try {
    await query(
      `UPDATE store_inventory
       SET name=?, category=?, unit_of_measure=?, quantity_in_stock=?,
           reorder_level=?, cost_per_unit=?, supplier_id=?, notes=?,
           lead_time_days=?, default_purchaser_id=?, risk_tier=?
       WHERE id=?`,
      [name, category || null, unit_of_measure, quantity_in_stock,
       reorder_level || null, cost_per_unit || null, supplier_id || null,
       notes || null, lead_time_days || null, default_purchaser_id || null,
       risk_tier || null,
       req.params.id]
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /api/inventory/:id/adjust  – adjust stock quantity
// body: { delta, reason?, new_cost_per_unit?, changed_by?, supplier_id?, total_cost? }
// • If new_cost_per_unit differs from current cost, logs to store_cost_history.
// • If delta > 0 AND supplier_id + total_cost provided (delivery), automatically posts a
//   PURCHASE entry to store_supplier_ledger so the debt is linked on the spot.
router.patch('/:id/adjust', async (req, res) => {
  const { delta, reason, new_cost_per_unit, changed_by, supplier_id, total_cost } = req.body;
  if (delta === undefined) return res.status(400).json({ error: 'delta is required' });
  try {
    // Fetch current item
    const current = await query(
      'SELECT cost_per_unit FROM store_inventory WHERE id = ?',
      [req.params.id]
    );
    if (!current.length) return res.status(404).json({ error: 'Item not found' });

    const oldCost = current[0].cost_per_unit ? Number(current[0].cost_per_unit) : null;
    const newCost = new_cost_per_unit != null ? Number(new_cost_per_unit) : null;

    // Update stock (and cost if provided)
    if (newCost != null) {
      await query(
        `UPDATE store_inventory
         SET quantity_in_stock = quantity_in_stock + ?, cost_per_unit = ?
         WHERE id = ?`,
        [delta, newCost, req.params.id]
      );
      // Log cost change if different from old cost
      if (oldCost !== newCost) {
        await query(
          `INSERT INTO store_cost_history (id, inventory_item_id, old_cost, new_cost, changed_by)
           VALUES (?, ?, ?, ?, ?)`,
          [uuidv4(), req.params.id, oldCost, newCost, changed_by || null]
        );
      }
    } else {
      await query(
        `UPDATE store_inventory
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
        `INSERT INTO store_supplier_ledger
           (id, supplier_id, transaction_type, amount, description, transaction_date)
         VALUES (?, ?, 'PURCHASE', ?, ?, CURDATE())`,
        [uuidv4(), supplier_id, Number(total_cost), desc]
      );
    }

    // ── Price-Change Advisory (Wow Factor) ──────────────────────────────────
    // If this delivery caused a price INCREASE, query the yield config to find
    // any POS menu items that use this ingredient, and calculate cost impact
    // per portion so the manager can be advised to review selling prices.
    let priceWarning = null;
    if (newCost !== null && oldCost !== null && newCost > oldCost && Number(delta) > 0) {
      try {
        // Fetch the item name for the advisory message
        const itemMeta = await query(
          'SELECT name FROM store_inventory WHERE id = ?',
          [req.params.id]
        );
        const itemName = itemMeta.length ? itemMeta[0].name : 'this item';

        // Join yield config with uniCenta products table.
        // LEFT JOIN ensures we handle missing products gracefully (they'll have NULL name).
        // We only surface rows where portions_per_unit > 0 to avoid divide-by-zero.
        const yieldRows = await query(
          `SELECT
             yc.portions_per_unit,
             p.id            AS product_id,
             p.name          AS product_name,
             p.pricesell     AS sell_price
           FROM store_yield_config yc
           LEFT JOIN products p ON yc.unicenta_product_id = p.id
           WHERE yc.inventory_item_id = ?
             AND yc.portions_per_unit > 0`,
          [req.params.id]
        );

        // Only include rows that have a matched POS product
        const impacted = yieldRows
          .filter(r => r.product_name != null)
          .map(r => ({
            productName:        r.product_name,
            sellPrice:          Number(r.sell_price || 0),
            portionsPerUnit:    Number(r.portions_per_unit),
            costRisePerPortion: parseFloat(((newCost - oldCost) / Number(r.portions_per_unit)).toFixed(2)),
          }));

        if (impacted.length > 0) {
          const percentage = Math.round(((newCost - oldCost) / oldCost) * 100);
          priceWarning = {
            itemName,
            oldCost,
            newCost,
            percentage,
            impactedProducts: impacted,
          };
        }
      } catch (yieldErr) {
        // Non-fatal: yield config query failure must never block a stock receipt.
        console.warn('[price-advisory] yield config query failed (non-fatal):', yieldErr.message);
      }
    }

    res.json({ ok: true, note: reason || null, priceWarning });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/inventory/waste  – log kitchen-side spoilage / wastage
// Creates an immediately-Issued requisition with purpose='Wastage'. No approval required.
// v1.2 change: does NOT deduct from store_inventory. Store stock was already reduced
// when the item was transferred to the kitchen via a Sales requisition. Waste is a
// kitchen-bin event only — it reduces the station's virtual balance, not the store ledger.
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
    const items = await query(
      'SELECT id, name, unit_of_measure FROM store_inventory WHERE id = ?',
      [inventory_item_id]
    );
    if (!items.length) return res.status(404).json({ error: 'Inventory item not found' });
    const item = items[0];

    const id = uuidv4();
    const isoNow = new Date().toISOString().slice(0, 19).replace('T', ' ');

    await query(
      `INSERT INTO store_requisitions
         (id, inventory_item_id, quantity, unit_of_measure, requested_by, purpose, status,
          notes, requester_location, issued_at, issued_by)
       VALUES (?, ?, ?, ?, ?, 'Wastage', 'Issued', ?, ?, ?, ?)`,
      [id, inventory_item_id, quantity, item.unit_of_measure,
       logged_by, notes || null, requester_location || null, isoNow, logged_by]
    );

    // No store_inventory deduction: stock left the store when it was issued to
    // the kitchen. Waste is tracked in the kitchen bin via requisition records,
    // and reflected in the true variance formula: true_consumption = opening +
    // transfers − waste − closing.

    res.status(201).json({ id, item_name: item.name });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// DELETE /api/inventory/:id
router.delete('/:id', async (req, res) => {
  try {
    await query('DELETE FROM store_inventory WHERE id = ?', [req.params.id]);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
