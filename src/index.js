require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { runMigrations } = require('./db');

const inventoryRouter    = require('./routes/inventory');
const suppliersRouter    = require('./routes/suppliers');
const requisitionsRouter = require('./routes/requisitions');
const yieldRouter        = require('./routes/yield');
const posRouter          = require('./routes/pos');

const app = express();

app.use(cors());
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
  res.json({ ok: true, service: 'unix-store-service', ts: new Date().toISOString() });
});

// Routes
app.use('/api/inventory',    inventoryRouter);
app.use('/api/suppliers',    suppliersRouter);
app.use('/api/requisitions', requisitionsRouter);
app.use('/api/yield',        yieldRouter);
app.use('/api/pos',          posRouter);

const PORT = process.env.PORT || 5000;

async function start() {
  try {
    console.log('[store] Running database migrations...');
    await runMigrations();
    console.log('[store] Migrations complete.');
    app.listen(PORT, () => {
      console.log(`[store] unix-store-service running on port ${PORT}`);
    });
  } catch (err) {
    console.error('[store] Failed to start:', err.message);
    process.exit(1);
  }
}

start();
