require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const { runMigrations } = require('./db');

const authRouter            = require('./routes/auth');
const inventoryRouter       = require('./routes/inventory');
const suppliersRouter       = require('./routes/suppliers');
const requisitionsRouter    = require('./routes/requisitions');
const yieldRouter           = require('./routes/yield');
const posRouter             = require('./routes/pos');
const payRunsRouter         = require('./routes/pay_runs');
const purchaseOrdersRouter  = require('./routes/purchase_orders');
const settingsRouter        = require('./routes/settings');

const app = express();

app.use(cors());
app.use(express.json());

// ── API Routes ──────────────────────────────────────────────
app.use('/api/auth',             authRouter);
app.use('/api/inventory',        inventoryRouter);
app.use('/api/suppliers',        suppliersRouter);
app.use('/api/requisitions',     requisitionsRouter);
app.use('/api/yield',            yieldRouter);
app.use('/api/pos',              posRouter);
app.use('/api/pay-runs',         payRunsRouter);
app.use('/api/purchase-orders',  purchaseOrdersRouter);
app.use('/api/settings',         settingsRouter);

// Health check
app.get('/health', (req, res) => {
  res.json({ ok: true, service: 'unix-store-service', ts: new Date().toISOString() });
});

// ── Flutter PWA Static Files ────────────────────────────────
// The Flutter web build is copied to /public/web by the Dockerfile.
// All non-API requests are served by the Flutter app (SPA fallback).
const webDir = path.join(__dirname, '..', 'public', 'web');
app.use(express.static(webDir));

// SPA fallback: serve index.html for any unmatched route
// so Flutter's client-side router works on hard refresh.
app.get('*', (req, res) => {
  res.sendFile(path.join(webDir, 'index.html'));
});

const PORT = process.env.PORT || 5000;

async function start() {
  try {
    console.log('[store] Running database migrations...');
    await runMigrations();
    console.log('[store] Migrations complete.');
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`[store] unix-store-service listening on port ${PORT}`);
    });
  } catch (err) {
    console.error('[store] Failed to start:', err.message);
    process.exit(1);
  }
}

start();
