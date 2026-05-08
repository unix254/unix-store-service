# Claude Feedback — v1.2.0 Kitchen Station Tracking & True Variance Engine

**Session Date:** 2026-05-09  
**Roles:** Claude as Architect + Engineer + Librarian (role-switched by Yunis)  
**Milestone:** v1.2.0 — Kitchen Virtual Bin Model, True Variance, Station Count Flows

---

## What Was Built

### Backend

**`migrations/018_kitchen_station_tracking.sql`** — New migration (purely additive):
- `store_stations` — kitchen stations with unique name constraint
- `store_kitchen_snapshots` — CLOSING/OPENING count headers (DRAFT/SUBMITTED/CONFIRMED), peak-hours flag
- `store_kitchen_snapshot_items` — per-item counted quantities per snapshot
- `ALTER TABLE store_inventory ADD COLUMN IF NOT EXISTS risk_tier ENUM('High','Standard','Low') NULL`

**`src/routes/stations.js`** — Full CRUD for station management:
- GET /, GET /:id, POST /, PUT /:id, PATCH /:id/toggle, DELETE /:id
- ER_DUP_ENTRY handled with friendly message

**`src/routes/kitchen_counts.js`** — Full kitchen count flow:
- `GET /stations-summary` — today's snapshot status per station
- `GET /active-list/:stationId` — blind count item list (non-zero bin OR transferred in 48 hrs)
- `POST /closing` — idempotent blind closing count (replaces SUBMITTED, rejects CONFIRMED); flags peak hours 11AM-3PM
- `GET /opening-data/:stationId` — yesterday's closing items for morning confirmation
- `POST /opening` — opening confirmation count
- `PATCH /:id/confirm` — storekeeper locks a snapshot
- `GET /ledger` — 10-column audit table per date/station
- `GET /snapshots/:stationId` — recent snapshots list

**`src/routes/pos.js`** — Major variance rework:
- Old `_buildVarianceQuery` renamed `_buildEstimateVarianceQuery` (v1.1 preserved as fallback)
- New `GET /variance/range`: checks snapshot existence → Verified mode (true formula) or Estimate mode (fallback)
- Verified formula: `opening + transfers_in - waste - closing_stock - expected_consumption`
- Each row now includes: `pos_product_breakdown` JSON, `variance_kes`, `variance_mode`, all snapshot fields
- Pareto sort: `ABS(variance_qty * cost_per_unit) DESC`
- `GET /variance/today` redirects to `/variance/range` with today's date

**`src/routes/inventory.js`** — Three targeted changes:
1. Waste endpoint: removed store_inventory deduction (waste only affects kitchen bin now)
2. PUT /:id: added `risk_tier` field validation + persistence
3. POST /: added `risk_tier` to INSERT

**`src/index.js`** — Registered `/api/stations` and `/api/kitchen-counts` routes

### Flutter — Models & API

**`lib/models/station.dart`** — Four new model classes:
- `Station`, `StationSummary`, `KitchenLedgerRow`, `CountItem`
- `CountItem.effectiveRiskTier` auto-classifies by cost if no `risk_tier` set
- `CountItem.requiresBlindCount` = tier is High or Standard

**`lib/models/inventory_item.dart`** — Added `riskTier` field (nullable String)

**`lib/models/staff.dart`** — Added `canDoStockCount` getter (capability + manager/owner fallback)

**`lib/models/staff_member.dart`** — Added `can_do_stock_count` to `kAllCapabilities`

**`lib/services/api.dart`** — 12 new methods covering all station/count/ledger endpoints

### Flutter — Screens

**`lib/screens/kitchen/kitchen_home.dart`** — Rewritten from direct-route to hub screen:
- Requisition card (always visible)
- Closing Stock Count card (gated by `canDoStockCount`)
- Opening Confirmation card (gated by `canDoStockCount`)

**`lib/screens/kitchen/kitchen_closing_count.dart`** — Full mobile-first blind count screen:
- Station picker with confirmed/submitted/not-done badges
- Blind count instruction banner, risk tier badge per item
- Peak-hours warning in success dialog
- Single submission per confirmed day enforcement

**`lib/screens/kitchen/kitchen_opening_count.dart`** — Hybrid confirm/blind screen:
- High/Standard items: empty qty field (truly blind)
- Low-risk items: "Confirm" chip auto-fills prev closing qty OR manual qty entry

**`lib/screens/store/kitchen_ledger_screen.dart`** — Storekeeper audit screen:
- Date picker + station filter dropdown
- 10-column horizontal-scroll table with colour coding
- Confirm/Lock dialog per snapshot

**`lib/screens/store/variance_screen.dart`** — Fully rewritten:
- `getVarianceRangeV2()` — returns `{mode, rows, from, to, station_id}`
- Verified/Estimate mode badge, station filter, date range picker
- Pareto toggle (Top 5 KES offenders vs All Items)
- Expandable POS product breakdown per ingredient row
- KES Impact column, legend

**`lib/screens/store/inventory_screen.dart`** — Risk Tier dropdown added to item form (Auto/High/Standard/Low)

**`lib/screens/store/store_shell.dart`** — Kitchen Ledger nav item added; 2x `withOpacity` fixed to `withValues(alpha:)`

---

## Known Issues / Fragility Points

1. **Verified-mode SQL params** — Two separate params arrays depending on `station_id` presence. Test both paths.
2. **Kitchen bin initialization** — Before first count per station, system falls back to estimate mode correctly via null `opening_stock` check.
3. **`withOpacity` backlog** — ~148 warnings remain in older files; intentionally deferred.

---

## Decisions Made (Confirmed in Session)

- `store_stations` not `store_locations` (avoids future ambiguity with `yunix_branches`)
- No "bar" terminology anywhere (Muslim-client convention)
- Waste deduction architecture changed: kitchen waste no longer touches `store_inventory.quantity_in_stock`
- `can_do_stock_count` not auto-granted to kitchen role — storekeeper grants per staff member
- Pareto sort by KES financial impact (not unit variance)

---

## Still Pending

- Stations Management UI (add/edit/toggle stations from Settings screen)
- Docker Hub rebuild for v1.2.0 — after testing
