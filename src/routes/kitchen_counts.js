/**
 * Kitchen Station Counting Routes — v1.2.0
 *
 * Implements the double-blind shift count model:
 *   Night team  → POST /closing   (blind count, no system balance shown)
 *   Morning team → POST /opening  (blind recount of high/standard-risk items,
 *                                  one-tap confirm for low-risk items)
 *   Storekeeper → GET  /ledger    (full audit table with gap analysis)
 *
 * Business day runs 7 AM → 7 AM (same shift logic as variance).
 */

const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { query } = require('../db');

const router = express.Router();

// ── Helpers ────────────────────────────────────────────────────────────────────

// Returns the current business date string YYYY-MM-DD using 7 AM shift.
function todayBusinessDate() {
  const now = new Date();
  const shifted = new Date(now.getTime() - 7 * 60 * 60 * 1000);
  const y = shifted.getUTCFullYear();
  const m = String(shifted.getUTCMonth() + 1).padStart(2, '0');
  const d = String(shifted.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

// Returns true if the current wall-clock time is "peak hours" (11 AM – 3 PM local).
function isPeakHours() {
  const h = new Date().getHours();
  return h >= 11 && h < 15;
}

// Effective risk tier for an item: use explicit tier if set, else classify by cost.
function effectiveRiskTier(item) {
  if (item.risk_tier) return item.risk_tier;
  const cost = Number(item.cost_per_unit || 0);
  if (cost >= 300) return 'High';
  if (cost >= 50)  return 'Standard';
  return 'Low';
}

// ── GET /api/kitchen-counts/stations-summary ───────────────────────────────────
// Returns all active stations with today's snapshot status — used by kitchen
// home screen to show which stations still need a closing count.
router.get('/stations-summary', async (req, res) => {
  const date = todayBusinessDate();
  try {
    const rows = await query(`
      SELECT
        s.id,
        s.name,
        s.description,
        MAX(CASE WHEN sk.snapshot_type = 'CLOSING' THEN sk.status END) AS closing_status,
        MAX(CASE WHEN sk.snapshot_type = 'OPENING' THEN sk.status END) AS opening_status
      FROM store_stations s
      LEFT JOIN store_kitchen_snapshots sk
        ON sk.station_id = s.id AND sk.snapshot_date = ?
      WHERE s.is_active = 1
      GROUP BY s.id, s.name, s.description
      ORDER BY s.name
    `, [date]);
    res.json(rows);
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ── GET /api/kitchen-counts/active-list/:stationId ────────────────────────────
// Returns the dynamic count list for a station: items with non-zero bin balance
// OR transferred in the last 48 hours. Never shows system quantities (blind).
// Each item includes its risk_tier for the opening confirmation UX.
router.get('/active-list/:stationId', async (req, res) => {
  const { stationId } = req.params;
  try {
    // Get the latest confirmed closing snapshot for this station (if any)
    const lastSnap = await query(`
      SELECT id, snapshot_date FROM store_kitchen_snapshots
      WHERE station_id = ? AND snapshot_type = 'CLOSING' AND status = 'CONFIRMED'
      ORDER BY snapshot_date DESC
      LIMIT 1
    `, [stationId]);

    const lastSnapId   = lastSnap.length ? lastSnap[0].id   : null;
    const lastSnapDate = lastSnap.length ? lastSnap[0].snapshot_date : null;

    // Build the active item set in two parts:
    // Part A – items that had a non-zero count in the last confirmed closing snapshot
    // Part B – items transferred to this station's location in the last 48 hours

    // We need the station's name to match requisition.requester_location
    const station = await query(
      `SELECT name FROM store_stations WHERE id = ?`, [stationId]
    );
    if (!station.length) return res.status(404).json({ error: 'Station not found' });
    const stationName = station[0].name;

    const rows = await query(`
      SELECT DISTINCT
        i.id,
        i.name,
        i.unit_of_measure,
        i.cost_per_unit,
        i.risk_tier,
        COALESCE(i.risk_tier,
          CASE
            WHEN COALESCE(i.cost_per_unit, 0) >= 300 THEN 'High'
            WHEN COALESCE(i.cost_per_unit, 0) >= 50  THEN 'Standard'
            ELSE 'Low'
          END
        ) AS effective_risk_tier
      FROM store_inventory i
      WHERE i.id IN (
        -- Part A: had stock in last confirmed closing count
        ${lastSnapId ? `
        SELECT ski.inventory_item_id
        FROM store_kitchen_snapshot_items ski
        WHERE ski.snapshot_id = ? AND ski.counted_quantity > 0
        UNION
        ` : ''}
        -- Part B: transferred to this station in last 48 hours
        SELECT DISTINCT r.inventory_item_id
        FROM store_requisitions r
        WHERE r.status = 'Issued'
          AND r.requester_location = ?
          AND r.issued_at >= DATE_SUB(NOW(), INTERVAL 48 HOUR)
          AND r.inventory_item_id IS NOT NULL
      )
      ORDER BY
        COALESCE(i.risk_tier,
          CASE
            WHEN COALESCE(i.cost_per_unit, 0) >= 300 THEN 'High'
            WHEN COALESCE(i.cost_per_unit, 0) >= 50  THEN 'Standard'
            ELSE 'Low'
          END
        ) ASC,
        i.name ASC
    `, lastSnapId ? [lastSnapId, stationName] : [stationName]);

    res.json({
      station_id:      stationId,
      station_name:    stationName,
      last_snap_date:  lastSnapDate,
      items:           rows,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ── POST /api/kitchen-counts/closing ──────────────────────────────────────────
// Submit a closing count for a station.
// Idempotent: if a SUBMITTED count already exists for today, it is replaced
// (storekeeper has not yet confirmed it). Once CONFIRMED, it is locked.
// body: { station_id, counted_by, items: [{inventory_item_id, counted_quantity, notes?}] }
router.post('/closing', async (req, res) => {
  const { station_id, counted_by, items } = req.body;
  if (!station_id || !counted_by || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: 'station_id, counted_by, and items[] are required' });
  }

  const date = todayBusinessDate();
  const peakHours = isPeakHours();

  try {
    // Check station exists
    const stations = await query(
      `SELECT id FROM store_stations WHERE id = ? AND is_active = 1`, [station_id]
    );
    if (!stations.length) return res.status(404).json({ error: 'Station not found or inactive' });

    // Check if a CONFIRMED closing already exists for today — locked
    const confirmed = await query(`
      SELECT id FROM store_kitchen_snapshots
      WHERE station_id = ? AND snapshot_date = ? AND snapshot_type = 'CLOSING'
        AND status = 'CONFIRMED'
    `, [station_id, date]);
    if (confirmed.length) {
      return res.status(409).json({
        error: 'A confirmed closing count already exists for today. Contact the storekeeper to amend.'
      });
    }

    // Delete any existing SUBMITTED (unconfirmed) closing for today — allow resubmit
    const existing = await query(`
      SELECT id FROM store_kitchen_snapshots
      WHERE station_id = ? AND snapshot_date = ? AND snapshot_type = 'CLOSING'
        AND status = 'SUBMITTED'
    `, [station_id, date]);
    if (existing.length) {
      await query(
        `DELETE FROM store_kitchen_snapshots WHERE id = ?`, [existing[0].id]
      );
    }

    // Create new snapshot
    const snapshotId = uuidv4();
    const now = new Date().toISOString().slice(0, 19).replace('T', ' ');
    await query(`
      INSERT INTO store_kitchen_snapshots
        (id, station_id, snapshot_date, snapshot_type, status, counted_by, counted_at, is_peak_hours)
      VALUES (?, ?, ?, 'CLOSING', 'SUBMITTED', ?, ?, ?)
    `, [snapshotId, station_id, date, counted_by, now, peakHours ? 1 : 0]);

    // Insert line items
    for (const item of items) {
      if (!item.inventory_item_id) continue;
      await query(`
        INSERT INTO store_kitchen_snapshot_items (id, snapshot_id, inventory_item_id, counted_quantity, notes)
        VALUES (?, ?, ?, ?, ?)
      `, [uuidv4(), snapshotId, item.inventory_item_id, Number(item.counted_quantity) || 0, item.notes || null]);
    }

    res.status(201).json({
      id:         snapshotId,
      date:       date,
      peak_hours: peakHours,
      message:    peakHours
        ? 'Closing count submitted — flagged as High-Risk (counted during peak hours).'
        : 'Closing count submitted successfully.',
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ── GET /api/kitchen-counts/opening-data/:stationId ───────────────────────────
// Returns data for the morning opening confirmation flow:
//   - Previous night's closing count (the "expected opening") — quantities HIDDEN
//     for high/standard risk items, shown for low-risk items.
//   - Whether today's opening has already been submitted.
// The frontend uses risk_tier to decide blind vs confirm UX per item.
router.get('/opening-data/:stationId', async (req, res) => {
  const { stationId } = req.params;
  const today     = todayBusinessDate();
  const yesterday = (() => {
    const d = new Date(today);
    d.setDate(d.getDate() - 1);
    return d.toISOString().slice(0, 10);
  })();

  try {
    // Get yesterday's closing count (the basis for today's opening)
    const prevSnap = await query(`
      SELECT sk.id, sk.snapshot_date, sk.status, sk.counted_by
      FROM store_kitchen_snapshots sk
      WHERE sk.station_id = ? AND sk.snapshot_date = ? AND sk.snapshot_type = 'CLOSING'
      ORDER BY sk.status DESC
      LIMIT 1
    `, [stationId, yesterday]);

    let closingItems = [];
    if (prevSnap.length) {
      closingItems = await query(`
        SELECT
          ski.inventory_item_id,
          i.name,
          i.unit_of_measure,
          i.cost_per_unit,
          ski.counted_quantity,
          COALESCE(i.risk_tier,
            CASE
              WHEN COALESCE(i.cost_per_unit, 0) >= 300 THEN 'High'
              WHEN COALESCE(i.cost_per_unit, 0) >= 50  THEN 'Standard'
              ELSE 'Low'
            END
          ) AS effective_risk_tier
        FROM store_kitchen_snapshot_items ski
        JOIN store_inventory i ON i.id = ski.inventory_item_id
        WHERE ski.snapshot_id = ?
        ORDER BY
          COALESCE(i.risk_tier,
            CASE
              WHEN COALESCE(i.cost_per_unit, 0) >= 300 THEN 'High'
              WHEN COALESCE(i.cost_per_unit, 0) >= 50  THEN 'Standard'
              ELSE 'Low'
            END
          ) ASC,
          i.name ASC
      `, [prevSnap[0].id]);
    }

    // Check if today's opening has already been submitted
    const todayOpening = await query(`
      SELECT id, status, counted_by FROM store_kitchen_snapshots
      WHERE station_id = ? AND snapshot_date = ? AND snapshot_type = 'OPENING'
      LIMIT 1
    `, [stationId, today]);

    res.json({
      station_id:          stationId,
      today:               today,
      previous_closing:    prevSnap.length ? { ...prevSnap[0], items: closingItems } : null,
      today_opening:       todayOpening.length ? todayOpening[0] : null,
      has_previous_closing: prevSnap.length > 0,
    });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ── POST /api/kitchen-counts/opening ──────────────────────────────────────────
// Submit opening confirmation count.
// High/Standard risk items are blind-recounted; Low risk items may auto-confirm
// (frontend sends the previous closing qty for low-risk items, their own count for others).
// body: { station_id, counted_by, items: [{inventory_item_id, counted_quantity, notes?}] }
router.post('/opening', async (req, res) => {
  const { station_id, counted_by, items } = req.body;
  if (!station_id || !counted_by || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: 'station_id, counted_by, and items[] are required' });
  }

  const date = todayBusinessDate();

  try {
    // Check station
    const stations = await query(
      `SELECT id FROM store_stations WHERE id = ? AND is_active = 1`, [station_id]
    );
    if (!stations.length) return res.status(404).json({ error: 'Station not found or inactive' });

    // Check if CONFIRMED opening exists — locked
    const confirmed = await query(`
      SELECT id FROM store_kitchen_snapshots
      WHERE station_id = ? AND snapshot_date = ? AND snapshot_type = 'OPENING'
        AND status = 'CONFIRMED'
    `, [station_id, date]);
    if (confirmed.length) {
      return res.status(409).json({ error: 'Opening count already confirmed for today.' });
    }

    // Replace existing SUBMITTED opening if present
    const existing = await query(`
      SELECT id FROM store_kitchen_snapshots
      WHERE station_id = ? AND snapshot_date = ? AND snapshot_type = 'OPENING'
        AND status = 'SUBMITTED'
    `, [station_id, date]);
    if (existing.length) {
      await query(`DELETE FROM store_kitchen_snapshots WHERE id = ?`, [existing[0].id]);
    }

    const snapshotId = uuidv4();
    const now = new Date().toISOString().slice(0, 19).replace('T', ' ');
    await query(`
      INSERT INTO store_kitchen_snapshots
        (id, station_id, snapshot_date, snapshot_type, status, counted_by, counted_at)
      VALUES (?, ?, ?, 'OPENING', 'SUBMITTED', ?, ?)
    `, [snapshotId, station_id, date, counted_by, now]);

    for (const item of items) {
      if (!item.inventory_item_id) continue;
      await query(`
        INSERT INTO store_kitchen_snapshot_items (id, snapshot_id, inventory_item_id, counted_quantity, notes)
        VALUES (?, ?, ?, ?, ?)
      `, [uuidv4(), snapshotId, item.inventory_item_id, Number(item.counted_quantity) || 0, item.notes || null]);
    }

    res.status(201).json({ id: snapshotId, date });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ── PATCH /api/kitchen-counts/:id/confirm ─────────────────────────────────────
// Storekeeper confirms a snapshot (locks it). Optional override of item quantities.
// body: { confirmed_by, overrides?: [{inventory_item_id, counted_quantity, notes?}] }
router.patch('/:id/confirm', async (req, res) => {
  const { confirmed_by, overrides } = req.body;
  if (!confirmed_by) return res.status(400).json({ error: 'confirmed_by is required' });

  try {
    const snap = await query(
      `SELECT * FROM store_kitchen_snapshots WHERE id = ?`, [req.params.id]
    );
    if (!snap.length) return res.status(404).json({ error: 'Snapshot not found' });
    if (snap[0].status === 'CONFIRMED') {
      return res.status(409).json({ error: 'Already confirmed' });
    }

    // Apply overrides if provided
    if (Array.isArray(overrides) && overrides.length > 0) {
      for (const ov of overrides) {
        await query(`
          UPDATE store_kitchen_snapshot_items
          SET counted_quantity = ?, notes = ?
          WHERE snapshot_id = ? AND inventory_item_id = ?
        `, [Number(ov.counted_quantity) || 0, ov.notes || null, req.params.id, ov.inventory_item_id]);
      }
    }

    const now = new Date().toISOString().slice(0, 19).replace('T', ' ');
    await query(`
      UPDATE store_kitchen_snapshots
      SET status = 'CONFIRMED', confirmed_by = ?, confirmed_at = ?
      WHERE id = ?
    `, [confirmed_by, now, req.params.id]);

    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ── GET /api/kitchen-counts/ledger ────────────────────────────────────────────
// Storekeeper ledger view for a given date.
// Query params: date=YYYY-MM-DD (defaults to today), station_id (optional)
// Returns: Item | Location | Opening | Morning Count | Handover Variance |
//          Transfers | Waste | Closing | Expected Closing
router.get('/ledger', async (req, res) => {
  const date = req.query.date || todayBusinessDate();
  const stationId = req.query.station_id || null;

  const yesterday = (() => {
    const d = new Date(date);
    d.setDate(d.getDate() - 1);
    return d.toISOString().slice(0, 10);
  })();

  // 7 AM shift boundaries for the requested business date
  const shiftStart = `${date} 07:00:00`;
  const shiftEnd   = (() => {
    const d = new Date(date);
    d.setDate(d.getDate() + 1);
    return `${d.toISOString().slice(0, 10)} 07:00:00`;
  })();

  try {
    // Fetch all active stations (or just one if filtered)
    const stationRows = await query(
      stationId
        ? `SELECT id, name FROM store_stations WHERE id = ? AND is_active = 1`
        : `SELECT id, name FROM store_stations WHERE is_active = 1 ORDER BY name`,
      stationId ? [stationId] : []
    );

    const result = [];

    for (const station of stationRows) {
      // 1. Opening = yesterday's confirmed closing snapshot items
      const openingSnap = await query(`
        SELECT sk.id FROM store_kitchen_snapshots sk
        WHERE sk.station_id = ? AND sk.snapshot_date = ?
          AND sk.snapshot_type = 'CLOSING' AND sk.status = 'CONFIRMED'
        LIMIT 1
      `, [station.id, yesterday]);

      const openingItems = openingSnap.length
        ? await query(`
            SELECT ski.inventory_item_id, ski.counted_quantity AS qty
            FROM store_kitchen_snapshot_items ski
            WHERE ski.snapshot_id = ?
          `, [openingSnap[0].id])
        : [];

      // 2. Morning count = today's OPENING snapshot items (any status)
      const morningSnap = await query(`
        SELECT sk.id, sk.status, sk.counted_by FROM store_kitchen_snapshots sk
        WHERE sk.station_id = ? AND sk.snapshot_date = ? AND sk.snapshot_type = 'OPENING'
        ORDER BY sk.status DESC LIMIT 1
      `, [station.id, date]);

      const morningItems = morningSnap.length
        ? await query(`
            SELECT ski.inventory_item_id, ski.counted_quantity AS qty
            FROM store_kitchen_snapshot_items ski
            WHERE ski.snapshot_id = ?
          `, [morningSnap[0].id])
        : [];

      // 3. Transfers = Sales requisitions issued to this station today
      const transferRows = await query(`
        SELECT inventory_item_id, SUM(COALESCE(issued_quantity, quantity)) AS qty
        FROM store_requisitions
        WHERE status = 'Issued'
          AND purpose = 'Sales'
          AND requester_location = ?
          AND inventory_item_id IS NOT NULL
          AND issued_at >= ? AND issued_at < ?
        GROUP BY inventory_item_id
      `, [station.name, shiftStart, shiftEnd]);

      // 4. Waste = Wastage requisitions at this station today
      const wasteRows = await query(`
        SELECT inventory_item_id, SUM(COALESCE(issued_quantity, quantity)) AS qty
        FROM store_requisitions
        WHERE status = 'Issued'
          AND purpose = 'Wastage'
          AND requester_location = ?
          AND inventory_item_id IS NOT NULL
          AND issued_at >= ? AND issued_at < ?
        GROUP BY inventory_item_id
      `, [station.name, shiftStart, shiftEnd]);

      // 5. Closing = today's CLOSING snapshot items (any status)
      const closingSnap = await query(`
        SELECT sk.id, sk.status, sk.counted_by, sk.is_peak_hours FROM store_kitchen_snapshots sk
        WHERE sk.station_id = ? AND sk.snapshot_date = ? AND sk.snapshot_type = 'CLOSING'
        ORDER BY sk.status DESC LIMIT 1
      `, [station.id, date]);

      const closingItems = closingSnap.length
        ? await query(`
            SELECT ski.inventory_item_id, ski.counted_quantity AS qty
            FROM store_kitchen_snapshot_items ski
            WHERE ski.snapshot_id = ?
          `, [closingSnap[0].id])
        : [];

      // 6. Expected consumption from POS for this date
      const posExpected = await query(`
        SELECT
          yc.inventory_item_id,
          ROUND(SUM(COALESCE(s.total_sold, 0) / yc.portions_per_unit), 3) AS expected_qty
        FROM store_yield_config yc
        LEFT JOIN (
          SELECT tl.product, SUM(tl.units) AS total_sold
          FROM ticketlines tl
          JOIN tickets t  ON t.id = tl.ticket
          JOIN receipts r ON r.id = t.id
          WHERE r.datenew >= ? AND r.datenew < ?
            AND t.tickettype = 0
          GROUP BY tl.product
        ) s ON s.product = yc.unicenta_product_id
        GROUP BY yc.inventory_item_id
      `, [shiftStart, shiftEnd]);

      // ── Combine into ledger rows ───────────────────────────────────────────
      // Build maps for O(1) lookups
      const toMap = (arr) => Object.fromEntries(arr.map(r => [r.inventory_item_id, Number(r.qty) || 0]));
      const openMap    = toMap(openingItems);
      const morningMap = toMap(morningItems);
      const xferMap    = toMap(transferRows);
      const wasteMap   = toMap(wasteRows);
      const closingMap = toMap(closingItems);
      const posMap     = Object.fromEntries(posExpected.map(r => [r.inventory_item_id, Number(r.expected_qty) || 0]));

      // Union of all item IDs that appear in any of the above
      const allItemIds = new Set([
        ...Object.keys(openMap),
        ...Object.keys(morningMap),
        ...Object.keys(xferMap),
        ...Object.keys(wasteMap),
        ...Object.keys(closingMap),
      ]);

      if (!allItemIds.size) continue;

      // Fetch item names
      const itemIds = [...allItemIds];
      const placeholders = itemIds.map(() => '?').join(',');
      const itemMeta = await query(
        `SELECT id, name, unit_of_measure FROM store_inventory WHERE id IN (${placeholders})`,
        itemIds
      );
      const metaMap = Object.fromEntries(itemMeta.map(i => [i.id, i]));

      for (const itemId of itemIds) {
        const meta            = metaMap[itemId] || { name: itemId, unit_of_measure: '—' };
        const opening         = openMap[itemId]    || 0;
        const morningCount    = morningMap[itemId]  || null; // null = not yet counted
        const transfers       = xferMap[itemId]     || 0;
        const waste           = wasteMap[itemId]    || 0;
        const closing         = closingMap[itemId]  ?? null; // null = not yet counted
        const posExp          = posMap[itemId]       || 0;
        const handoverVariance = morningCount !== null ? morningCount - opening : null;
        // Expected closing = opening + transfers - waste - expected_pos_consumption
        const expectedClosing = opening + transfers - waste - posExp;

        result.push({
          inventory_item_id: itemId,
          item_name:         meta.name,
          unit_of_measure:   meta.unit_of_measure,
          station_id:        station.id,
          station_name:      station.name,
          closing_status:    closingSnap.length ? closingSnap[0].status : null,
          opening_status:    morningSnap.length ? morningSnap[0].status : null,
          is_peak_hours:     closingSnap.length ? Boolean(closingSnap[0].is_peak_hours) : false,
          // Ledger columns in chronological audit order
          opening,
          morning_count:     morningCount,
          handover_variance: handoverVariance,
          transfers,
          waste,
          closing,
          expected_closing:  Math.round(expectedClosing * 1000) / 1000,
        });
      }
    }

    // Sort: stations alphabetically, then items alphabetically within station
    result.sort((a, b) =>
      a.station_name.localeCompare(b.station_name) ||
      a.item_name.localeCompare(b.item_name)
    );

    res.json({ date, rows: result });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: err.message });
  }
});

// ── GET /api/kitchen-counts/snapshots/:stationId ──────────────────────────────
// List recent snapshots for a station — used by the storekeeper confirm screen.
// Query param: ?days=7 (default 7)
router.get('/snapshots/:stationId', async (req, res) => {
  const days = Math.min(parseInt(req.query.days) || 7, 90);
  try {
    const rows = await query(`
      SELECT sk.*, COUNT(ski.id) AS item_count
      FROM store_kitchen_snapshots sk
      LEFT JOIN store_kitchen_snapshot_items ski ON ski.snapshot_id = sk.id
      WHERE sk.station_id = ?
        AND sk.snapshot_date >= DATE_SUB(CURDATE(), INTERVAL ? DAY)
      GROUP BY sk.id
      ORDER BY sk.snapshot_date DESC, sk.snapshot_type DESC
    `, [req.params.stationId, days]);
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
