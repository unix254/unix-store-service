const mysql = require('mysql2/promise');
const fs = require('fs');
const path = require('path');

const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT ? parseInt(process.env.DB_PORT, 10) : 3306,
  user: process.env.DB_USER || 'unicenta',
  password: process.env.DB_PASSWORD || 'unicentapos',
  database: process.env.DB_NAME || 'unicentapos',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
  multipleStatements: true
});

async function query(sql, params) {
  const [rows] = await pool.execute(sql, params);
  return rows;
}

/**
 * Pre-boot hook: if the server still has the legacy unix_migrations table,
 * rename it to store_migrations before the migration engine starts.
 * This preserves the applied-migration history on existing deployments.
 */
async function ensureMigrationTableMigrated(conn) {
  const [rows] = await conn.query(`
    SELECT COUNT(*) AS cnt
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_name = 'unix_migrations'
  `);
  if (rows[0].cnt > 0) {
    console.log('[db] Detected legacy unix_migrations — renaming to store_migrations...');
    await conn.query('RENAME TABLE unix_migrations TO store_migrations');
    console.log('[db] Renamed unix_migrations → store_migrations OK');
  }
}

/**
 * Run all SQL migration files from /migrations in order.
 * Tracks completed migrations in store_migrations — each file runs exactly once.
 */
async function runMigrations() {
  const migrationsDir = path.join(__dirname, '..', 'migrations');
  const files = fs.readdirSync(migrationsDir).filter(f => f.endsWith('.sql')).sort();

  const conn = await pool.getConnection();
  try {
    // Rename legacy tracking table on existing servers before anything else
    await ensureMigrationTableMigrated(conn);

    // Create migration tracking table if it doesn't exist (fresh installs)
    await conn.query(`
      CREATE TABLE IF NOT EXISTS store_migrations (
        filename     VARCHAR(255) NOT NULL PRIMARY KEY,
        applied_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Fetch already-applied migrations
    const [applied] = await conn.query('SELECT filename FROM store_migrations');
    const appliedSet = new Set(applied.map(r => r.filename));

    for (const file of files) {
      if (appliedSet.has(file)) {
        console.log(`[db] Skipping (already applied): ${file}`);
        continue;
      }

      const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
      console.log(`[db] Running migration: ${file}`);
      try {
        await conn.query(sql);
        await conn.query('INSERT INTO store_migrations (filename) VALUES (?)', [file]);
        console.log(`[db] Migration OK: ${file}`);
      } catch (err) {
        console.error(`[db] Migration FAILED: ${file} — ${err.message}`);
        throw err; // halt startup on migration failure
      }
    }
  } finally {
    conn.release();
  }
}

module.exports = { pool, query, runMigrations };
