const express = require('express');
const router  = express.Router();
const { pool } = require('../db');

/**
 * Validate super admin credentials against environment variables.
 * SUPER_ADMIN_USERNAME defaults to 'yunix_admin'.
 * SUPER_ADMIN_PASSWORD has no default — must be explicitly set.
 */
function checkCredentials(username, password) {
  const envUser = process.env.SUPER_ADMIN_USERNAME || 'yunix_admin';
  const envPass = process.env.SUPER_ADMIN_PASSWORD;

  if (!envPass) {
    return {
      ok: false,
      status: 503,
      error: 'Super Admin is not configured on this server. Set SUPER_ADMIN_PASSWORD in the environment.',
    };
  }
  if (username !== envUser || password !== envPass) {
    return { ok: false, status: 401, error: 'Invalid super admin credentials.' };
  }
  return { ok: true };
}

// POST /api/admin/super-login
// Body: { username, password }
// Validates super admin credentials. Returns { ok: true } on success.
router.post('/super-login', (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) {
    return res.status(400).json({ error: 'username and password are required' });
  }
  const check = checkCredentials(username, password);
  if (!check.ok) return res.status(check.status).json({ error: check.error });
  res.json({ ok: true });
});

// POST /api/admin/go-live-wipe
// Body: { username, password }
// Wipes ONLY transactional store_ tables. Master data and config are preserved.
// Credentials are re-verified on every wipe call (no token caching).
router.post('/go-live-wipe', async (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) {
    return res.status(400).json({ error: 'username and password are required' });
  }
  const check = checkCredentials(username, password);
  if (!check.ok) return res.status(check.status).json({ error: check.error });

  // Strictly transactional tables — ordered to handle FK dependencies
  // store_po_details and store_pay_run_details are children and must go first.
  const transactionalTables = [
    'store_po_details',
    'store_purchase_orders',
    'store_pay_run_details',
    'store_pay_runs',
    'store_supplier_ledger',
    'store_requisitions',
  ];

  const conn = await pool.getConnection();
  try {
    await conn.query('SET FOREIGN_KEY_CHECKS = 0');
    for (const table of transactionalTables) {
      await conn.query(`DELETE FROM \`${table}\``);
    }
    await conn.query('SET FOREIGN_KEY_CHECKS = 1');

    console.log(`[admin] Go-Live wipe completed. Tables cleared: ${transactionalTables.join(', ')}`);

    res.json({
      ok: true,
      message: 'Transactional data cleared. System is ready for Go-Live.',
      tablesCleared: transactionalTables,
    });
  } catch (err) {
    // Always re-enable FK checks even on error
    await conn.query('SET FOREIGN_KEY_CHECKS = 1').catch(() => {});
    console.error('[admin] Go-live wipe error:', err.message);
    res.status(500).json({ error: 'Wipe failed: ' + err.message });
  } finally {
    conn.release();
  }
});

module.exports = router;
