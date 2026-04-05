const express = require('express');
const { query } = require('../db');

const router = express.Router();

// POST /api/auth/pin
// Body: { pin: "1234" }
// Returns: { id, name, role } on success | 401 on failure
router.post('/pin', async (req, res) => {
  const { pin } = req.body;
  if (!pin || !/^\d{4}$/.test(pin)) {
    return res.status(400).json({ error: 'A 4-digit PIN is required' });
  }
  try {
    const rows = await query(
      'SELECT id, name, role FROM unix_staff WHERE pin = ? AND active = 1',
      [pin]
    );
    if (!rows.length) {
      return res.status(401).json({ error: 'Incorrect PIN' });
    }
    res.json(rows[0]);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/auth/staff  – list all staff (for admin management)
router.get('/staff', async (req, res) => {
  try {
    const rows = await query(
      'SELECT id, name, role, active, created_at FROM unix_staff ORDER BY role, name'
    );
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/auth/staff  – create a new staff member
router.post('/staff', async (req, res) => {
  const { name, pin, role } = req.body;
  if (!name || !pin || !role) {
    return res.status(400).json({ error: 'name, pin and role are required' });
  }
  if (!/^\d{4}$/.test(pin)) {
    return res.status(400).json({ error: 'PIN must be exactly 4 digits' });
  }
  if (!['kitchen', 'store', 'manager'].includes(role)) {
    return res.status(400).json({ error: 'role must be kitchen, store, or manager' });
  }
  try {
    const { v4: uuidv4 } = require('uuid');
    const existing = await query('SELECT id FROM unix_staff WHERE pin = ?', [pin]);
    if (existing.length) {
      return res.status(409).json({ error: 'That PIN is already in use by another staff member' });
    }
    const id = uuidv4();
    await query(
      'INSERT INTO unix_staff (id, name, pin, role, active) VALUES (?, ?, ?, ?, 1)',
      [id, name, pin, role]
    );
    res.status(201).json({ id });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// PUT /api/auth/staff/:id  – update name, pin (optional), role
router.put('/staff/:id', async (req, res) => {
  const { name, pin, role } = req.body;
  if (!name || !role) {
    return res.status(400).json({ error: 'name and role are required' });
  }
  if (pin && !/^\d{4}$/.test(pin)) {
    return res.status(400).json({ error: 'PIN must be exactly 4 digits' });
  }
  if (!['kitchen', 'store', 'manager'].includes(role)) {
    return res.status(400).json({ error: 'role must be kitchen, store, or manager' });
  }
  try {
    if (pin) {
      const conflict = await query(
        'SELECT id FROM unix_staff WHERE pin = ? AND id != ?',
        [pin, req.params.id]
      );
      if (conflict.length) {
        return res.status(409).json({ error: 'That PIN is already in use by another staff member' });
      }
      await query(
        'UPDATE unix_staff SET name = ?, pin = ?, role = ? WHERE id = ?',
        [name, pin, role, req.params.id]
      );
    } else {
      await query(
        'UPDATE unix_staff SET name = ?, role = ? WHERE id = ?',
        [name, role, req.params.id]
      );
    }
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// PATCH /api/auth/staff/:id/toggle  – toggle active/inactive
router.patch('/staff/:id/toggle', async (req, res) => {
  try {
    await query('UPDATE unix_staff SET active = NOT active WHERE id = ?', [req.params.id]);
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// DELETE /api/auth/staff/:id  – permanently remove a staff member
router.delete('/staff/:id', async (req, res) => {
  try {
    await query('DELETE FROM unix_staff WHERE id = ?', [req.params.id]);
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
