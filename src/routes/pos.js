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
      WHERE DATE(r.datenew) = CURDATE()
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
      WHERE DATE(r.datenew) BETWEEN ? AND ?
        AND t.tickettype = 0
      GROUP BY tl.product, p.name
      ORDER BY total_units_sold DESC
    `, [from, to]);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/pos/variance/today
// Core of the Usage Variance engine:
// Compares what the store ISSUED (unix_requisitions, purpose=Sales, today)
// vs what the POS SOLD (ticketlines, today), using the yield config to convert.
//
// Expected consumption = total_units_sold / portions_per_unit
// Actual issued        = sum of issued requisition quantities for that store item
// Variance             = actual_issued - expected_consumption  (positive = over-issued = potential loss)
router.get('/variance/today', async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        i.id                            AS inventory_item_id,
        i.name                          AS inventory_item_name,
        i.unit_of_measure,
        yc.unicenta_product_id,
        p.name                          AS pos_product_name,
        yc.portions_per_unit,
        COALESCE(sales.total_sold, 0)   AS total_sold,
        ROUND(COALESCE(sales.total_sold, 0) / yc.portions_per_unit, 3)
                                        AS expected_consumption,
        COALESCE(issued.total_issued, 0) AS actual_issued,
        ROUND(
          COALESCE(issued.total_issued, 0)
          - (COALESCE(sales.total_sold, 0) / yc.portions_per_unit),
          3
        )                               AS variance
      FROM unix_yield_config yc
      JOIN unix_store_inventory i ON i.id = yc.inventory_item_id
      LEFT JOIN products p ON p.id = yc.unicenta_product_id
      LEFT JOIN (
        SELECT tl.product, SUM(tl.units) AS total_sold
        FROM ticketlines tl
        JOIN tickets t  ON t.id = tl.ticket
        JOIN receipts r ON r.id = t.id
        WHERE DATE(r.datenew) = CURDATE()
          AND t.tickettype = 0
        GROUP BY tl.product
      ) sales ON sales.product = yc.unicenta_product_id
      LEFT JOIN (
        SELECT inventory_item_id, SUM(quantity) AS total_issued
        FROM unix_requisitions
        WHERE purpose = 'Sales'
          AND status = 'Issued'
          AND DATE(issued_at) = CURDATE()
        GROUP BY inventory_item_id
      ) issued ON issued.inventory_item_id = yc.inventory_item_id
      ORDER BY ABS(variance) DESC
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
