const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { query } = require('../db');

const router = express.Router();

// GET /api/purchase-orders
// List all POs ordered by created_at DESC with item_count
router.get('/', async (req, res) => {
  try {
    const rows = await query(`
      SELECT po.*, COUNT(pd.id) AS item_count
      FROM store_purchase_orders po
      LEFT JOIN store_po_details pd ON pd.po_id = po.id
      GROUP BY po.id
      ORDER BY po.created_at DESC
    `);
    res.json(rows);
  } catch (err) {
    console.error('GET /purchase-orders error:', err);
    res.status(500).json({ error: 'Failed to fetch purchase orders' });
  }
});

// GET /api/purchase-orders/:id
// Single PO with full line-item details
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const [po] = await query(
      `SELECT po.*, COUNT(pd.id) AS item_count
       FROM store_purchase_orders po
       LEFT JOIN store_po_details pd ON pd.po_id = po.id
       WHERE po.id = ?
       GROUP BY po.id`,
      [id]
    );

    if (!po) {
      return res.status(404).json({ error: 'Purchase order not found' });
    }

    const details = await query(`
      SELECT pd.*, i.name AS item_name, i.unit_of_measure, i.quantity_in_stock, i.reorder_level,
             s.name AS supplier_name, s.phone AS supplier_phone
      FROM store_po_details pd
      JOIN store_inventory i ON i.id = pd.inventory_item_id
      LEFT JOIN store_suppliers s ON s.id = pd.supplier_id
      WHERE pd.po_id = ?
      ORDER BY s.name, i.name
    `, [id]);

    res.json({ ...po, details });
  } catch (err) {
    console.error('GET /purchase-orders/:id error:', err);
    res.status(500).json({ error: 'Failed to fetch purchase order' });
  }
});

// POST /api/purchase-orders/auto-draft
// Auto-generate a DRAFT PO from items that need restocking
router.post('/auto-draft', async (req, res) => {
  try {
    const { created_by } = req.body;

    const items = await query(`
      SELECT
        i.id, i.name, i.unit_of_measure, i.quantity_in_stock, i.reorder_level, i.lead_time_days,
        s.id AS supplier_id, s.name AS supplier_name,
        COALESCE(rs_usage.daily_avg, 0) AS daily_usage,
        GREATEST(0, ROUND(
          (COALESCE(i.reorder_level, 0) * 2)
          - i.quantity_in_stock
          + (COALESCE(rs_usage.daily_avg, 0) * COALESCE(i.lead_time_days, 1)),
          3
        )) AS suggested_order_qty
      FROM store_inventory i
      LEFT JOIN store_suppliers s ON s.id = i.supplier_id
      LEFT JOIN (
        SELECT inventory_item_id, SUM(quantity) / 30.0 AS daily_avg
        FROM store_requisitions
        WHERE status = 'Issued' AND purpose = 'Sales'
          AND issued_at >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
        GROUP BY inventory_item_id
      ) rs_usage ON rs_usage.inventory_item_id = i.id
      WHERE i.reorder_level IS NOT NULL
        AND i.quantity_in_stock <= (
          COALESCE(i.reorder_level, 0)
          + (COALESCE(rs_usage.daily_avg, 0) * COALESCE(i.lead_time_days, 1))
        )
      ORDER BY i.name
    `);

    const poId = uuidv4();
    await query(
      `INSERT INTO store_purchase_orders (id, status, created_by) VALUES (?, 'DRAFT', ?)`,
      [poId, created_by || null]
    );

    for (const item of items) {
      await query(
        `INSERT INTO store_po_details (id, po_id, inventory_item_id, supplier_id, suggested_qty, approved_qty)
         VALUES (?, ?, ?, ?, ?, 0)`,
        [uuidv4(), poId, item.id, item.supplier_id || null, item.suggested_order_qty]
      );
    }

    const [po] = await query(
      `SELECT po.*, COUNT(pd.id) AS item_count
       FROM store_purchase_orders po
       LEFT JOIN store_po_details pd ON pd.po_id = po.id
       WHERE po.id = ?
       GROUP BY po.id`,
      [poId]
    );

    const details = await query(`
      SELECT pd.*, i.name AS item_name, i.unit_of_measure, i.quantity_in_stock, i.reorder_level,
             s.name AS supplier_name, s.phone AS supplier_phone
      FROM store_po_details pd
      JOIN store_inventory i ON i.id = pd.inventory_item_id
      LEFT JOIN store_suppliers s ON s.id = pd.supplier_id
      WHERE pd.po_id = ?
      ORDER BY s.name, i.name
    `, [poId]);

    res.status(201).json({ ...po, details });
  } catch (err) {
    console.error('POST /purchase-orders/auto-draft error:', err);
    res.status(500).json({ error: 'Failed to create auto-draft purchase order' });
  }
});

// POST /api/purchase-orders/:id/details
// Add a manual line item to a PO
router.post('/:id/details', async (req, res) => {
  try {
    const { id } = req.params;
    const { inventory_item_id, supplier_id, suggested_qty, approved_qty } = req.body;

    if (!inventory_item_id) {
      return res.status(400).json({ error: 'inventory_item_id is required' });
    }

    const [po] = await query('SELECT id, status FROM store_purchase_orders WHERE id = ?', [id]);
    if (!po) {
      return res.status(404).json({ error: 'Purchase order not found' });
    }

    const [item] = await query(
      'SELECT id, name, unit_of_measure, quantity_in_stock, reorder_level FROM store_inventory WHERE id = ?',
      [inventory_item_id]
    );
    if (!item) {
      return res.status(400).json({ error: 'Inventory item not found' });
    }

    const detailId = uuidv4();
    await query(
      `INSERT INTO store_po_details (id, po_id, inventory_item_id, supplier_id, suggested_qty, approved_qty)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [
        detailId,
        id,
        inventory_item_id,
        supplier_id || null,
        suggested_qty != null ? suggested_qty : 0,
        approved_qty != null ? approved_qty : 0,
      ]
    );

    const [detail] = await query(`
      SELECT pd.*, i.name AS item_name, i.unit_of_measure, i.quantity_in_stock, i.reorder_level,
             s.name AS supplier_name, s.phone AS supplier_phone
      FROM store_po_details pd
      JOIN store_inventory i ON i.id = pd.inventory_item_id
      LEFT JOIN store_suppliers s ON s.id = pd.supplier_id
      WHERE pd.id = ?
    `, [detailId]);

    res.status(201).json(detail);
  } catch (err) {
    console.error('POST /purchase-orders/:id/details error:', err);
    res.status(500).json({ error: 'Failed to add detail line' });
  }
});

// PUT /api/purchase-orders/:id/details/:detailId
// Update an existing detail line
router.put('/:id/details/:detailId', async (req, res) => {
  try {
    const { id, detailId } = req.params;
    const { approved_qty, supplier_id } = req.body;

    const [detail] = await query(
      'SELECT id FROM store_po_details WHERE id = ? AND po_id = ?',
      [detailId, id]
    );
    if (!detail) {
      return res.status(404).json({ error: 'Detail line not found' });
    }

    const fields = [];
    const values = [];

    if (approved_qty != null) {
      fields.push('approved_qty = ?');
      values.push(approved_qty);
    }
    if (supplier_id !== undefined) {
      fields.push('supplier_id = ?');
      values.push(supplier_id || null);
    }

    if (fields.length === 0) {
      return res.status(400).json({ error: 'No updatable fields provided' });
    }

    values.push(detailId);
    await query(`UPDATE store_po_details SET ${fields.join(', ')} WHERE id = ?`, values);

    const [updated] = await query(`
      SELECT pd.*, i.name AS item_name, i.unit_of_measure, i.quantity_in_stock, i.reorder_level,
             s.name AS supplier_name, s.phone AS supplier_phone
      FROM store_po_details pd
      JOIN store_inventory i ON i.id = pd.inventory_item_id
      LEFT JOIN store_suppliers s ON s.id = pd.supplier_id
      WHERE pd.id = ?
    `, [detailId]);

    res.json(updated);
  } catch (err) {
    console.error('PUT /purchase-orders/:id/details/:detailId error:', err);
    res.status(500).json({ error: 'Failed to update detail line' });
  }
});

// DELETE /api/purchase-orders/:id/details/:detailId
// Remove a detail line
router.delete('/:id/details/:detailId', async (req, res) => {
  try {
    const { id, detailId } = req.params;

    const [detail] = await query(
      'SELECT id FROM store_po_details WHERE id = ? AND po_id = ?',
      [detailId, id]
    );
    if (!detail) {
      return res.status(404).json({ error: 'Detail line not found' });
    }

    await query('DELETE FROM store_po_details WHERE id = ?', [detailId]);
    res.json({ ok: true });
  } catch (err) {
    console.error('DELETE /purchase-orders/:id/details/:detailId error:', err);
    res.status(500).json({ error: 'Failed to delete detail line' });
  }
});

// PATCH /api/purchase-orders/:id/submit
// Move a DRAFT PO to PENDING_APPROVAL
router.patch('/:id/submit', async (req, res) => {
  try {
    const { id } = req.params;

    const [po] = await query('SELECT * FROM store_purchase_orders WHERE id = ?', [id]);
    if (!po) {
      return res.status(404).json({ error: 'Purchase order not found' });
    }
    if (po.status !== 'DRAFT') {
      return res.status(400).json({ error: `Cannot submit a PO with status '${po.status}'. Only DRAFT POs can be submitted.` });
    }

    await query(
      `UPDATE store_purchase_orders SET status = 'PENDING_APPROVAL' WHERE id = ?`,
      [id]
    );

    const [updated] = await query('SELECT * FROM store_purchase_orders WHERE id = ?', [id]);
    res.json(updated);
  } catch (err) {
    console.error('PATCH /purchase-orders/:id/submit error:', err);
    res.status(500).json({ error: 'Failed to submit purchase order' });
  }
});

// PATCH /api/purchase-orders/:id/approve
// Approve a PENDING_APPROVAL PO
router.patch('/:id/approve', async (req, res) => {
  try {
    const { id } = req.params;
    const { approved_by } = req.body;

    if (!approved_by) {
      return res.status(400).json({ error: 'approved_by is required' });
    }

    const [po] = await query('SELECT * FROM store_purchase_orders WHERE id = ?', [id]);
    if (!po) {
      return res.status(404).json({ error: 'Purchase order not found' });
    }
    if (po.status !== 'PENDING_APPROVAL') {
      return res.status(400).json({ error: `Cannot approve a PO with status '${po.status}'. Only PENDING_APPROVAL POs can be approved.` });
    }

    await query(
      `UPDATE store_purchase_orders SET status = 'APPROVED', approved_by = ?, approved_at = NOW() WHERE id = ?`,
      [approved_by, id]
    );

    const [updated] = await query('SELECT * FROM store_purchase_orders WHERE id = ?', [id]);
    res.json(updated);
  } catch (err) {
    console.error('PATCH /purchase-orders/:id/approve error:', err);
    res.status(500).json({ error: 'Failed to approve purchase order' });
  }
});

module.exports = router;
