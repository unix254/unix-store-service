/**
 * READ-ONLY access to legacy uniCenta POS tables.
 * NO INSERT / UPDATE / DELETE on any legacy table ever touches here.
 *
 * Exposed data:
 *   - products + categories   (for yield config setup UI)
 *   - daily/recent sales      (for Usage Variance dashboard)
 */

const express = require('express');
const { query } = require('../db');

const router = express.Router();

// GET /api/pos/products  – all POS menu products with category name
// Used in the Yield Config UI so staff can pick the matching menu item
router.get('/products', async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        p.id,
        p.reference,
        p.name,
        p.pricesell,
        p.pricebuy,
        p.stockunits,
        c.name AS category_name
      FROM products p
      LEFT JOIN categories c ON c.id = p.category
      WHERE p.isservice = 0
      ORDER BY c.name, p.name
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/pos/categories  – all POS categories
router.get('/categories', async (req, res) => {
  try {
    const rows = await query(`
      SELECT id, name, catorder FROM categories ORDER BY catorder, name
    `);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/pos/sales/today  – today's sales by product
// Returns: product_id, product_name, total_units_sold, total_revenue
router.get('/sales/today', async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        tl.product                AS product_id,
        p.name                    AS product_name,
        SUM(tl.units)             AS total_units_sold,
        SUM(tl.units * tl.price)  AS total_revenue
      FROM ticketlines tl
      JOIN tickets t   ON t.id = tl.ticket
      JOIN receipts r  ON r.id = t.id
      LEFT JOIN products p ON p.id = tl.product
      WHERE r.datenew >= CURDATE() AND r.datenew < (CURDATE() + INTERVAL 1 DAY)
        AND t.tickettype = 0
      GROUP BY tl.product, p.name
      ORDER BY total_units_sold DESC
    `);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/pos/sales/range?from=YYYY-MM-DD&to=YYYY-MM-DD
router.get('/sales/range', async (req, res) => {
  const { from, to } = req.query;
  if (!from || !to) return res.status(400).json({ error: 'from and to query params required (YYYY-MM-DD)' });
  try {
    const rows = await query(`
      SELECT
        tl.product                AS product_id,
        p.name                    AS product_name,
        SUM(tl.units)             AS total_units_sold,
        SUM(tl.units * tl.price)  AS total_revenue
      FROM ticketlines tl
      JOIN tickets t   ON t.id = tl.ticket
      JOIN receipts r  ON r.id = t.id
      LEFT JOIN products p ON p.id = tl.product
      WHERE r.datenew >= ? AND r.datenew < (? + INTERVAL 1 DAY)
        AND t.tickettype = 0
      GROUP BY tl.product, p.name
      ORDER BY total_units_sold DESC
    `, [from, to]);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Shared variance SQL builder ────────────────────────────────────────────────
// v1.1 ESTIMATE formula: compares POS expected consumption vs requisitions issued.
// Used as fallback when no kitchen snapshot data exists for the period.
// Returns one row per inventory item; pos_product_breakdown is JSON for expandable UI.
function _buildEstimateVarianceQuery(salesFilter, issuesFilter, locationFilter) {
  const reqWhere = locationFilter
    ? `AND requester_location = ${locationFilter}`
    : '';
  return `
    SELECT
      i.id                                AS inventory_item_id,
      i.name                              AS inventory_item_name,
      i.unit_of_measure,
      i.cost_per_unit,
      GROUP_CONCAT(p.name ORDER BY p.name SEPARATOR ' / ')
                                          AS pos_product_name,
      -- JSON breakdown: one entry per (inventory_item × POS product) pair
      JSON_ARRAYAGG(JSON_OBJECT(
        'pos_product_name', p.name,
        'expected_qty', ROUND(COALESCE(sales.total_sold, 0) / yc.portions_per_unit, 3)
      ))                                  AS pos_product_breakdown,
      ROUND(SUM(COALESCE(sales.total_sold, 0) / yc.portions_per_unit), 3)
                                          AS expected_consumption,
      COALESCE(issued.total_issued, 0)    AS true_consumption,
      ROUND(
        COALESCE(issued.total_issued, 0)
        - SUM(COALESCE(sales.total_sold, 0) / yc.portions_per_unit),
        3
      )                                   AS variance_qty,
      'estimate'                          AS variance_mode,
      NULL                                AS opening_stock,
      NULL                                AS transfers_in,
      NULL                                AS waste_qty,
      NULL                                AS closing_stock,
      ROUND(COALESCE(issued.total_issued, 0) * COALESCE(i.cost_per_unit, 0), 2) AS variance_kes
    FROM store_yield_config yc
    JOIN store_inventory i  ON i.id  = yc.inventory_item_id
    LEFT JOIN products p         ON p.id  = yc.unicenta_product_id
    LEFT JOIN (
      SELECT tl.product, SUM(tl.units) AS total_sold
      FROM ticketlines tl
      JOIN tickets t  ON t.id = tl.ticket
      JOIN receipts r ON r.id = t.id
      WHERE ${salesFilter}
        AND t.tickettype = 0
      GROUP BY tl.product
    ) sales ON sales.product = yc.unicenta_product_id
    LEFT JOIN (
      -- COALESCE(issued_quantity, quantity): uses actual issued qty when storekeeper
      -- adjusted the amount, falls back to requested qty for legacy rows (pre-M8).
      SELECT
        inventory_item_id,
        SUM(CASE WHEN purpose = 'Sales'
                 THEN COALESCE(issued_quantity, quantity) ELSE 0 END)
        - SUM(CASE WHEN purpose = 'Wastage'
                   THEN COALESCE(issued_quantity, quantity) ELSE 0 END)
          AS total_issued
      FROM store_requisitions
      WHERE status = 'Issued'
        AND purpose IN ('Sales', 'Wastage')
        AND inventory_item_id IS NOT NULL
        AND ${issuesFilter}
        ${reqWhere}
      GROUP BY inventory_item_id
    ) issued ON issued.inventory_item_id = yc.inventory_item_id
    GROUP BY i.id, i.name, i.unit_of_measure, i.cost_per_unit, issued.total_issued
    ORDER BY ABS(ROUND(
      COALESCE(issued.total_issued, 0) - SUM(COALESCE(sales.total_sold, 0) / yc.portions_per_unit),
      3
    ) * COALESCE(i.cost_per_unit, 1)) DESC
  `;
}

// ── Variance range endpoint ────────────────────────────────────────────────────
// GET /api/pos/variance/range?from=YYYY-MM-DD&to=YYYY-MM-DD[&station_id=UUID]
//
// Dual-mode:
//  - "verified"  → uses true formula (opening + transfers − waste − closing)
//                  when confirmed kitchen snapshots exist for every item in range.
//  - "estimate"  → falls back to v1.1 formula when no snapshots exist.
//
// Response includes `variance_mode` per row ('verified' | 'estimate') and
// `pos_product_breakdown` array for expandable POS product detail in the UI.
router.get('/variance/range', async (req, res) => {
  const { from, to, station_id } = req.query;
  if (!from || !to) {
    return res.status(400).json({ error: 'from and to query params required (YYYY-MM-DD)' });
  }

  const shiftFrom = `${from} 07:00:00`;
  const shiftTo   = (() => {
    const d = new Date(to);
    d.setDate(d.getDate() + 1);
    return `${d.toISOString().slice(0, 10)} 07:00:00`;
  })();

  try {
    // Check whether confirmed snapshots exist for this period (and optionally station)
    const snapCheck = await query(`
      SELECT COUNT(*) AS cnt
      FROM store_kitchen_snapshots
      WHERE snapshot_type = 'CLOSING'
        AND status = 'CONFIRMED'
        AND snapshot_date >= ?
        AND snapshot_date <= ?
        ${station_id ? 'AND station_id = ?' : ''}
    `, station_id ? [from, to, station_id] : [from, to]);

    const hasSnapshots = Number(snapCheck[0].cnt) > 0;

    if (!hasSnapshots) {
      // ── ESTIMATE MODE (v1.1 fallback) ───────────────────────────────────────
      const locationParam = station_id ? `'${station_id}'` : null;
      const sql = _buildEstimateVarianceQuery(
        `r.datenew >= ? AND r.datenew < ?`,
        `issued_at >= ? AND issued_at < ?`,
        locationParam
      );
      const rows = await query(sql, [shiftFrom, shiftTo, shiftFrom, shiftTo]);
      return res.json({ mode: 'estimate', from, to, station_id: station_id || null, rows });
    }

    // ── VERIFIED MODE (true formula) ─────────────────────────────────────────
    // For each inventory item with a yield config, compute:
    //   opening       = confirmed closing snapshot BEFORE the period
    //   transfers_in  = Sales requisitions to the station during period
    //   waste         = Wastage requisitions at the station during period
    //   closing       = confirmed closing snapshot AT or closest to period end
    //   true_consumption = opening + transfers_in − waste − closing
    //   variance_qty  = true_consumption − expected_consumption (from POS)

    const stationWhere = station_id ? 'AND sk.station_id = ?' : '';
    const stationName  = station_id
      ? (await query(`SELECT name FROM store_stations WHERE id = ?`, [station_id]))[0]?.name
      : null;
    const locationWhere = stationName
      ? `AND r.requester_location = '${stationName.replace(/'/g, "''")}'`
      : '';

    const rows = await query(`
      SELECT
        i.id                    AS inventory_item_id,
        i.name                  AS inventory_item_name,
        i.unit_of_measure,
        i.cost_per_unit,
        GROUP_CONCAT(DISTINCT p.name ORDER BY p.name SEPARATOR ' / ') AS pos_product_name,
        JSON_ARRAYAGG(JSON_OBJECT(
          'pos_product_name', p.name,
          'expected_qty', ROUND(COALESCE(sales.total_sold, 0) / yc.portions_per_unit, 3)
        ))                      AS pos_product_breakdown,

        -- Expected from POS
        ROUND(SUM(COALESCE(sales.total_sold, 0) / yc.portions_per_unit), 3) AS expected_consumption,

        -- Opening: latest confirmed CLOSING snapshot BEFORE period start
        COALESCE(opening_snap.opening_qty, 0)  AS opening_stock,

        -- Transfers to kitchen during period (Sales requisitions)
        COALESCE(xfer.total_xfer, 0)           AS transfers_in,

        -- Waste at station during period
        COALESCE(waste.total_waste, 0)          AS waste_qty,

        -- Closing: latest confirmed CLOSING snapshot AT or within period
        COALESCE(closing_snap.closing_qty, 0)  AS closing_stock,

        -- True consumption
        ROUND(
          COALESCE(opening_snap.opening_qty, 0)
          + COALESCE(xfer.total_xfer, 0)
          - COALESCE(waste.total_waste, 0)
          - COALESCE(closing_snap.closing_qty, 0),
          3
        )                                      AS true_consumption,

        -- Variance = true_consumption − expected_consumption
        ROUND(
          (COALESCE(opening_snap.opening_qty, 0)
           + COALESCE(xfer.total_xfer, 0)
           - COALESCE(waste.total_waste, 0)
           - COALESCE(closing_snap.closing_qty, 0))
          - SUM(COALESCE(sales.total_sold, 0) / yc.portions_per_unit),
          3
        )                                      AS variance_qty,
        'verified'                             AS variance_mode,

        -- KES impact for Pareto sort
        ROUND(
          ABS(
            (COALESCE(opening_snap.opening_qty, 0)
             + COALESCE(xfer.total_xfer, 0)
             - COALESCE(waste.total_waste, 0)
             - COALESCE(closing_snap.closing_qty, 0))
            - SUM(COALESCE(sales.total_sold, 0) / yc.portions_per_unit)
          ) * COALESCE(i.cost_per_unit, 1),
          2
        )                                      AS variance_kes

      FROM store_yield_config yc
      JOIN store_inventory i ON i.id = yc.inventory_item_id

      LEFT JOIN products p ON p.id = yc.unicenta_product_id

      -- POS expected consumption
      LEFT JOIN (
        SELECT tl.product, SUM(tl.units) AS total_sold
        FROM ticketlines tl
        JOIN tickets t  ON t.id = tl.ticket
        JOIN receipts r ON r.id = t.id
        WHERE r.datenew >= ? AND r.datenew < ?
          AND t.tickettype = 0
        GROUP BY tl.product
      ) sales ON sales.product = yc.unicenta_product_id

      -- Opening: closest confirmed closing snapshot BEFORE the period
      LEFT JOIN (
        SELECT ski.inventory_item_id, ski.counted_quantity AS opening_qty
        FROM store_kitchen_snapshot_items ski
        JOIN store_kitchen_snapshots sk ON sk.id = ski.snapshot_id
        WHERE sk.snapshot_type = 'CLOSING' AND sk.status = 'CONFIRMED'
          AND sk.snapshot_date < ?
          ${stationWhere}
          AND sk.id = (
            SELECT sk2.id FROM store_kitchen_snapshots sk2
            WHERE sk2.snapshot_type = 'CLOSING' AND sk2.status = 'CONFIRMED'
              AND sk2.snapshot_date < ?
              ${stationWhere}
            ORDER BY sk2.snapshot_date DESC LIMIT 1
          )
      ) opening_snap ON opening_snap.inventory_item_id = yc.inventory_item_id

      -- Closing: latest confirmed closing snapshot within or at period end
      LEFT JOIN (
        SELECT ski.inventory_item_id, ski.counted_quantity AS closing_qty
        FROM store_kitchen_snapshot_items ski
        JOIN store_kitchen_snapshots sk ON sk.id = ski.snapshot_id
        WHERE sk.snapshot_type = 'CLOSING' AND sk.status = 'CONFIRMED'
          AND sk.snapshot_date >= ? AND sk.snapshot_date <= ?
          ${stationWhere}
          AND sk.id = (
            SELECT sk2.id FROM store_kitchen_snapshots sk2
            WHERE sk2.snapshot_type = 'CLOSING' AND sk2.status = 'CONFIRMED'
              AND sk2.snapshot_date >= ? AND sk2.snapshot_date <= ?
              ${stationWhere}
            ORDER BY sk2.snapshot_date DESC LIMIT 1
          )
      ) closing_snap ON closing_snap.inventory_item_id = yc.inventory_item_id

      -- Transfers (Sales requisitions to this station)
      LEFT JOIN (
        SELECT inventory_item_id,
               SUM(COALESCE(issued_quantity, quantity)) AS total_xfer
        FROM store_requisitions
        WHERE status = 'Issued' AND purpose = 'Sales'
          AND inventory_item_id IS NOT NULL
          AND issued_at >= ? AND issued_at < ?
          ${locationWhere}
        GROUP BY inventory_item_id
      ) xfer ON xfer.inventory_item_id = yc.inventory_item_id

      -- Waste at station
      LEFT JOIN (
        SELECT inventory_item_id,
               SUM(COALESCE(issued_quantity, quantity)) AS total_waste
        FROM store_requisitions
        WHERE status = 'Issued' AND purpose = 'Wastage'
          AND inventory_item_id IS NOT NULL
          AND issued_at >= ? AND issued_at < ?
          ${locationWhere}
        GROUP BY inventory_item_id
      ) waste ON waste.inventory_item_id = yc.inventory_item_id

      GROUP BY i.id, i.name, i.unit_of_measure, i.cost_per_unit,
               opening_snap.opening_qty, xfer.total_xfer, waste.total_waste, closing_snap.closing_qty

      ORDER BY variance_kes DESC
    `, station_id
      ? [shiftFrom, shiftTo, from, from, station_id, from, to, station_id, from, to, station_id, from, to, station_id, shiftFrom, shiftTo, shiftFrom, shiftTo]
      : [shiftFrom, shiftTo, from, from, from, to, from, to, shiftFrom, shiftTo, shiftFrom, shiftTo]
    );

    res.json({ mode: 'verified', from, to, station_id: station_id || null, rows });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/pos/variance/today  — convenience alias → range for today's business day
router.get('/variance/today', async (req, res) => {
  const now     = new Date();
  const shifted = new Date(now.getTime() - 7 * 60 * 60 * 1000);
  const pad = (n) => String(n).padStart(2, '0');
  const date = `${shifted.getUTCFullYear()}-${pad(shifted.getUTCMonth() + 1)}-${pad(shifted.getUTCDate())}`;
  // Forward to range handler
  req.query.from = date;
  req.query.to   = date;
  res.redirect(307, `/api/pos/variance/range?from=${date}&to=${date}${req.query.station_id ? '&station_id=' + req.query.station_id : ''}`);
});

// GET /api/pos/issues-cost/today
// Returns the total KES value of all items issued in the current 7 AM business day.
// Used by the Requisitions screen KPI card so managers see live cash-out value.
router.get('/issues-cost/today', async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        ROUND(SUM(
          COALESCE(r.issued_quantity, r.quantity) * COALESCE(i.cost_per_unit, 0)
        ), 2)                                                     AS total_cost_kes,
        COUNT(*)                                                  AS total_issues,
        SUM(CASE WHEN r.purpose = 'Sales'
                 THEN 1 ELSE 0 END)                              AS sales_count,
        SUM(CASE WHEN r.purpose = 'Staff Meal'
                 THEN 1 ELSE 0 END)                              AS staff_meal_count,
        SUM(CASE WHEN r.purpose = 'Wastage'
                 THEN 1 ELSE 0 END)                              AS wastage_count
      FROM store_requisitions r
      JOIN store_inventory i ON i.id = r.inventory_item_id
      WHERE r.status = 'Issued'
        AND r.inventory_item_id IS NOT NULL
        AND r.issued_at >= (DATE(NOW() - INTERVAL 7 HOUR) + INTERVAL 7 HOUR) 
        AND r.issued_at < (DATE(NOW() - INTERVAL 7 HOUR) + INTERVAL 1 DAY + INTERVAL 7 HOUR)
    `);
    res.json(rows[0] ?? { total_cost_kes: 0, total_issues: 0 });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
