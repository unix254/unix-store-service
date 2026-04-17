const express = require('express');
const router  = express.Router();
const { query } = require('../db');

// GET /api/feature-flags
// Returns all flags as an array: [{ feature_key, enabled, label, description }]
router.get('/', async (req, res) => {
  try {
    const rows = await query(
      'SELECT feature_key, enabled, label, description FROM yunix_feature_flags ORDER BY feature_key'
    );
    res.json(rows);
  } catch (err) {
    console.error('[feature-flags] GET error:', err.message);
    res.status(500).json({ error: 'Database error' });
  }
});

// PUT /api/feature-flags/:key
// Body: { enabled: true | false }
router.put('/:key', async (req, res) => {
  const { key } = req.params;
  const { enabled } = req.body;
  if (enabled === undefined || enabled === null) {
    return res.status(400).json({ error: '"enabled" field is required' });
  }
  try {
    const result = await query(
      'UPDATE yunix_feature_flags SET enabled = ? WHERE feature_key = ?',
      [enabled ? 1 : 0, key]
    );
    if (result.affectedRows === 0) {
      return res.status(404).json({ error: `Flag "${key}" not found` });
    }
    res.json({ ok: true });
  } catch (err) {
    console.error('[feature-flags] PUT error:', err.message);
    res.status(500).json({ error: 'Database error' });
  }
});

module.exports = router;
