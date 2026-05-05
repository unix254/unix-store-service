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
// Generates the full variance query for a given date filter clause.
// `salesFilter`  : WHERE fragment applied to the receipts/ticketlines subquery
// `issuesFilter` : WHERE fragment applied to the store_requisitions subquery
// Both fragments must not include a leading AND.
function _buildVarianceQuery(salesFilter, issuesFilter) {
  return `
    SELECT
      i.id                                AS inventory_item_id,
      i.name                              AS inventory_item_name,
      i.unit_of_measure,
      GROUP_CONCAT(p.name ORDER BY p.name SEPARATOR ' / ')
                                          AS pos_product_name,
      ROUND(SUM(COALESCE(sales.total_sold, 0) / yc.portions_per_unit), 3)
                                          AS expected_consumption,
      COALESCE(issued.total_issued, 0)    AS actual_issued,
      ROUND(
        COALESCE(issued.total_issued, 0)
        - SUM(COALESCE(sales.total_sold, 0) / yc.portions_per_unit),
        3
      )                                   AS variance_qty
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
      GROUP BY inventory_item_id
    ) issued ON issued.inventory_item_id = yc.inventory_item_id
    GROUP BY i.id, i.name, i.unit_of_measure, issued.total_issued
    ORDER BY ABS(ROUND(
      COALESCE(issued.total_issued, 0) - SUM(COALESCE(sales.total_sold, 0) / yc.portions_per_unit),
      3
    )) DESC
  `;
}

// GET /api/pos/variance/today
// Uses 7 AM–7 AM business day shift so late-night sales (e.g. 2 AM) are
// counted against the previous day's shift rather than the calendar day.
router.get('/variance/today', async (req, res) => {
  try {
    const sql = _buildVarianceQuery(
      `r.datenew >= (DATE(NOW() - INTERVAL 7 HOUR) + INTERVAL 7 HOUR) AND r.datenew < (DATE(NOW() - INTERVAL 7 HOUR) + INTERVAL 1 DAY + INTERVAL 7 HOUR)`,
      `issued_at >= (DATE(NOW() - INTERVAL 7 HOUR) + INTERVAL 7 HOUR) AND issued_at < (DATE(NOW() - INTERVAL 7 HOUR) + INTERVAL 1 DAY + INTERVAL 7 HOUR)`
    );
    const rows = await query(sql);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/pos/variance/range?from=YYYY-MM-DD&to=YYYY-MM-DD
// Both `from` and `to` are treated as business days (7 AM shift applied).
// E.g. from=2026-05-01&to=2026-05-05 covers 01-May 07:00 → 06-May 07:00.
router.get('/variance/range', async (req, res) => {
  const { from, to } = req.query;
  if (!from || !to) {
    return res.status(400).json({ error: 'from and to query params required (YYYY-MM-DD)' });
  }
  try {
    const sql = _buildVarianceQuery(
      `r.datenew >= (? + INTERVAL 7 HOUR) AND r.datenew < (? + INTERVAL 1 DAY + INTERVAL 7 HOUR)`,
      `issued_at >= (? + INTERVAL 7 HOUR) AND issued_at < (? + INTERVAL 1 DAY + INTERVAL 7 HOUR)`
    );
    // Each subquery needs from + to params → 4 params total
    const rows = await query(sql, [from, to, from, to]);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
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
