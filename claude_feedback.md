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

## SESSION: 2026-05-10 (Session 5) — Hardening, UX Improvements & Deploy Prep

### Backend (`src/routes/pos.js`) — Critical Crash Fix

**Fix — Verified mode: "Connection lost: The server closed the connection" for Main Kitchen + historical dates**
- Root cause 1: Parameter array had **18 values for 16 `?` marks**. Two extra `from` values were injected at positions 4 and 5, shifting every subsequent param right. By position 13, the `station_id` UUID was bound to `issued_at < ?` (a DATETIME column) → MariaDB failed to cast → hard connection drop.
- Root cause 2: Inner correlated subqueries used `${stationWhere}` which expands to `AND sk.station_id = ?`, but the inner subquery aliases its table as `sk2`, not `sk` — ambiguous/wrong alias.
- Fix: Added `const stationWhere2 = station_id ? 'AND sk2.station_id = ?' : ''` and replaced the two inner subquery `${stationWhere}` with `${stationWhere2}`. Fixed parameter array to exactly 16 values in correct order:
  `[shiftFrom, shiftTo, from, station_id, from, station_id, from, to, station_id, from, to, station_id, shiftFrom, shiftTo, shiftFrom, shiftTo]`
- Why it only broke for Main Kitchen + historical dates: only Main Kitchen had confirmed snapshots → verified mode triggered → buggy code path executed. Barista (added later, no historical confirmed snapshots) fell through to estimate mode, which has a separate correct parameter array.

### Backend (`src/routes/kitchen_counts.js`) — New Endpoint

**New: `GET /api/kitchen-counts/station-stock/:stationId`**
- Returns items from the most recent confirmed CLOSING snapshot for a station.
- Used by the kitchen requisition screen to show current station stock on each item tile.
- Response: `{ station_id, snapshot_date, items: [ { inventory_item_id, name, unit_of_measure, station_qty } ] }`

### Backend (`src/routes/requisitions.js`) — Stock Balance on Requisition Cards

**`REQ_COLS` extended with two new computed columns:**
- `i.quantity_in_stock AS store_qty` — current store inventory (JOIN already existed)
- `station_qty` — correlated subquery: latest confirmed closing snapshot qty for this item at the station named `r.requester_location`. Gives storekeeper at-a-glance signal on the card.

### Flutter — Variance Dashboard (`variance_screen.dart`)

**POS Products column truncation**
- Added `_posProductLabel(breakdown)` helper in `_VarianceTableState`.
- Shows first 2 product names; if breakdown has 3+ products, appends `+N more` (e.g. `BIRYANI / CHAPATI  +28 more`).
- Prevents columns from exploding for items mapped to 30+ POS products.
- Expand chevron still reveals all products in breakdown rows.

### Flutter — Kitchen Stock Count Screens

**Kitchen staff station restriction** (both `kitchen_closing_count.dart` and `kitchen_opening_count.dart`)
- After `getStationsSummary()`, filter: `if (staff.isKitchen && staff.locationName != null)` → only show the station matching `staff.locationName`.
- Managers, owners, storekeepers see all stations as before.
- Single-station auto-select still fires (if filtered list has one result, it auto-picks and skips the picker).

**Opening station picker UI fix** (`kitchen_opening_count.dart`)
- Replaced flat plain `_StationPickerOpening` (bare card, just icon + name + chevron) with rich Card + CircleAvatar + badge style matching the closing count picker.
- Now shows: green confirmed border (opening confirmed), amber submitted border (awaiting storekeeper), grey (not done yet). Matching subtitle text.

### Flutter — Kitchen Requisition Screen (`kitchen_requisition.dart`)

**Station stock on item tiles**
- New state: `Map<String, double> _stationStock`; loaded in `_loadStationStock()`.
- Logic: look up station ID by matching `staff.locationName` to `getStationsSummary()` names → call `ApiService.getStationStock(stationId)`.
- Each item grid tile now shows a second teal line when data exists: 🏪 station icon + `X kg` from last confirmed closing snapshot.
- Grid tile height auto-adjusts when station data is present.
- Fails silently if no station assigned or no snapshot yet — no error shown.

### Flutter — Requisition Approval Screen (`requisition_approval.dart`)

**Stock balance on storekeeper cards**
- `Requisition` model: added `requesterLocation` (from `r.requester_location`), `storeQty` (from `i.quantity_in_stock`), `stationQty` (from correlated subquery).
- Meta row: added teal `_MetaChip` with store_mall icon showing `requesterLocation` when non-null. `_MetaChip` now accepts optional `color` param for accent styling.
- New `_StockBalanceStrip` widget rendered below meta row (standard requests only, when `storeQty != null`):
  - **Store pill**: green border/text if `storeQty >= requestedQty`, red + ⚠ icon if insufficient.
  - **Station pill**: teal, shown only when `stationQty` is non-null (station has confirmed snapshot).
- Allows storekeeper to make approve/reject decisions at a glance, without opening the issue dialog only to find stock is too low.

---

## SESSION: 2026-05-09 (Session 4) — Variance Dashboard Deep Fix Round

### Backend (pos.js)

**Fix 1 — `pos_product_breakdown` never parsed (expandable rows broken)**
- Root cause: `JSON_ARRAYAGG` in MariaDB via mysql2 returns a **raw JSON string**, not a parsed array. Flutter's `_parsedBreakdown()` only checked `raw is List`, so the string fell through returning `[]`. `hasBreakdown` was therefore always false — expand button never rendered.
- Fix: Added `rows.forEach(r => { if (typeof r.pos_product_breakdown === 'string') r.pos_product_breakdown = JSON.parse(...) })` after both estimate and verified queries before `res.json()`.

**Fix 2 — Station filter: all rows showing regardless of station (estimate mode)**
- Root cause: `_buildEstimateVarianceQuery` LEFT JOINs requisitions filtered by station but returns ALL `store_yield_config` items. Items with 0 issues to the selected station appeared with restaurant-wide `expected_consumption` from POS sales — architecturally wrong cross-station comparison.
- Fix: Added `HAVING COALESCE(issued.total_issued, 0) != 0` (via `havingClause` variable) when `locationFilter` is present. Only items with actual issues to the selected station appear.

**Fix 3 — Station filter: all rows showing regardless of station (verified mode)**
- Root cause: Same LEFT JOIN issue. Items with no snapshot data and no transfers for the selected station appeared with all-zero columns.
- Fix: Added `HAVING (opening_snap.opening_qty IS NOT NULL OR closing_snap.closing_qty IS NOT NULL OR xfer.total_xfer IS NOT NULL OR waste.total_waste IS NOT NULL)` when `stationWhere` is set.

### Flutter (variance_screen.dart)

**Fix 4 — Expandable breakdown: `_parsedBreakdown` defensive string handling**
- Added `if (raw is String) { final decoded = jsonDecode(raw); ... }` as a safety net in case a cached API response passes a string.
- Added `import 'dart:convert';`.

**Fix 5 — Expand button gate changed from `breakdown.length > 1` to `breakdown.isNotEmpty`**
- Previously only showed expand chevron when 2+ POS products mapped to one store item. Most items have 1 product — button never appeared.
- Now shows for any item with breakdown data. Useful to confirm which POS product drives consumption even for single-product items.

**Fix 6 — Column name uniformity**
- Removed conditional `isVerified ? 'True Consumption' : 'Actual Issues'`. Column is now always "True Consumption". Mode badge + info banner already communicate the mode to users.

---

## SESSION: 2026-05-09 (Session 3) — Variance Dashboard Fixes & UI Polish

### Backend (pos.js) — Station Filter Bug Fix (2 bugs)

**Bug 1 — Verified mode: "Unknown column 'r.requester_location'"**
- Root cause: `locationWhere` used `r.requester_location` but neither the `xfer` nor `waste` subqueries alias `store_requisitions` as `r`.
- Fix: Changed to `requester_location` (no alias prefix) in both subqueries.

**Bug 2 — Estimate mode: station filter matched nothing**
- Root cause: `locationParam` was set to the station UUID (e.g. `'abc-123'`), but `requester_location` stores station *names* (e.g. `'Kitchen Station'`). Every filter was returning 0 issues while still showing all items with expected consumption from POS → appeared to show data that didn't match the selected station.
- Fix: Added `SELECT name FROM store_stations WHERE id = ?` lookup before building `locationParam` in estimate mode, mirroring the existing verified-mode approach.

### Flutter — Variance Screen

1. **Column order**: Store Item moved to col 1 (was 2), POS Product(s) to col 2 (was 1). Column widths adjusted to match.
2. **Expandable breakdown rows**: Column positions updated to match new order. POS product name now correctly sits under the POS Product(s) column; Store Item column blank in breakdown rows (shown on parent row).
3. **KES Impact format**: Removed `KES ` prefix and decimal points. Now displays whole shillings with thousands separator (`#,##0` format). Column name unchanged.
4. **Search bar**: Added `TextEditingController _searchCtrl` at state level. Search field placed in `_SummaryBar` to the right of KPI chips. Filters both `inventory_item_name` and `pos_product_name` (case-insensitive, client-side — no API reload needed). KPI counts in the summary bar now reflect the filtered row count, not the raw total.
5. **`_displayRows` getter**: Now applies both Pareto filter (top 5) AND search query in one place.
6. **Dispose**: Added `_searchCtrl.dispose()` override.

### Flutter — Yield Config Screen

- Added `_searchQuery` state + `TextEditingController _searchCtrl`.
- Search bar rendered below the title/Add Mapping row when configs are non-empty (width 300px).
- `_filteredConfigs` getter filters by `inventoryItemName` or `posProductName`.
- Empty-search state renders a "No configs match..." message with `search_off` icon.

### Flutter — Kitchen Ledger Screen

- Added `_searchQuery` state + `TextEditingController _searchCtrl`.
- Search field placed inline in the filter Wrap (same row as date picker and station dropdown), width 200px.
- `_filteredRows` getter filters by `itemName` or `stationName`.
- Empty-search state renders a "No items match..." message.
- Added `_searchCtrl.dispose()` override.

### Flutter — Store Shell (Nav)

- Kitchen Ledger nav item moved from near-bottom position to immediately below Requisitions (second item). Rationale: storekeepers access it daily right after checking requisitions.

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
