const express = require('express');
const { query } = require('../db');

const router = express.Router();

// GET /api/settings — public (used by login screen for white-labeling)
// Returns { business_name: '...', slogan: '...', ... }
router.get('/', async (req, res) => {
  try {
    const rows = await query(
      'SELECT setting_key, setting_value FROM unix_settings ORDER BY id'
    );
    const result = {};
    rows.forEach(r => { result[r.setting_key] = r.setting_value; });
    res.json(result);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// PATCH /api/settings — update one or more settings
// Body: { business_name: 'Aspire Hotel', slogan: '...' }
router.patch('/', async (req, res) => {
  const updates = req.body;
  if (!updates || typeof updates !== 'object' || Array.isArray(updates)) {
    return res.status(400).json({ error: 'Body must be a key-value object' });
  }
  try {
    for (const [key, value] of Object.entries(updates)) {
      await query(
        `INSERT INTO unix_settings (setting_key, setting_value)
         VALUES (?, ?)
         ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)`,
        [key, String(value)]
      );
    }
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
