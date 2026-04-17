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
// Compares what the store ISSUED (store_requisitions, purpose=Sales, today)
// vs what the POS SOLD (ticketlines, today), using the yield config to convert.
//
// AGGREGATION FIX: Group by inventory item (i.id) to prevent double-counting
// actual_issued when one ingredient maps to multiple POS products.
// Expected consumption = SUM( total_units_sold / portions_per_unit ) across all mapped products.
// Actual issued        = (Total Sales issues) - (Logged Wastage) for today — waste is excluded.
// Variance             = actual_issued - expected_consumption  (positive = over-issued = potential loss)
router.get('/variance/today', async (req, res) => {
  try {
    const rows = await query(`
      SELECT
        i.id                                AS inventory_item_id,
        i.name                              AS inventory_item_name,
        i.unit_of_measure,
        -- Concatenate all mapped POS product names for display
        GROUP_CONCAT(p.name ORDER BY p.name SEPARATOR ' / ')
                                            AS pos_product_name,
        -- Sum expected consumption across all POS product mappings
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
        -- Today's POS sales per product
        SELECT tl.product, SUM(tl.units) AS total_sold
        FROM ticketlines tl
        JOIN tickets t  ON t.id = tl.ticket
        JOIN receipts r ON r.id = t.id
        WHERE DATE(r.datenew) = CURDATE()
          AND t.tickettype = 0
        GROUP BY tl.product
      ) sales ON sales.product = yc.unicenta_product_id
      LEFT JOIN (
        -- Actual issued = Sales issues MINUS kitchen-logged wastage for today.
        -- Waste is excluded so dropped items don't inflate the kitchen's variance.
        SELECT
          inventory_item_id,
          SUM(CASE WHEN purpose = 'Sales'    THEN quantity ELSE 0 END)
          - SUM(CASE WHEN purpose = 'Wastage' THEN quantity ELSE 0 END)
            AS total_issued
        FROM store_requisitions
        WHERE status = 'Issued'
          AND purpose IN ('Sales', 'Wastage')
          AND DATE(issued_at) = CURDATE()
        GROUP BY inventory_item_id
      ) issued ON issued.inventory_item_id = yc.inventory_item_id
      -- GROUP BY inventory item to collapse multiple POS-product mappings
      GROUP BY i.id, i.name, i.unit_of_measure, issued.total_issued
      ORDER BY ABS(ROUND(COALESCE(issued.total_issued, 0) - SUM(COALESCE(sales.total_sold, 0) / yc.portions_per_unit), 3)) DESC
    `);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
