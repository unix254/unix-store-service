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
 * Run all SQL migration files from /migrations in order.
 * Uses CREATE TABLE IF NOT EXISTS so it is safe to run on every startup.
 */
async function runMigrations() {
  const migrationsDir = path.join(__dirname, '..', 'migrations');
  const files = fs.readdirSync(migrationsDir).filter(f => f.endsWith('.sql')).sort();

  for (const file of files) {
    const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
    console.log(`[db] Running migration: ${file}`);
    const conn = await pool.getConnection();
    try {
      await conn.query(sql);
      console.log(`[db] Migration OK: ${file}`);
    } finally {
      conn.release();
    }
  }
}

module.exports = { pool, query, runMigrations };
