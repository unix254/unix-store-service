# Claude Implementation Feedback

---

## Milestone 16 — Business Intelligence (BI) Hub & Price Impact Overhaul

**Date:** 2026-04-16  
**Status:** Complete

### What was built

#### Task 1 — Security: `canAccessBI`
- **`flutter_app/lib/models/staff.dart`**: Added `canAccessBI` getter (`can_access_bi` capability OR isManager/isOwner).  
- **`flutter_app/lib/models/staff_member.dart`**: Added `can_access_bi` to `kAllCapabilities` list with label `'Access Business Intelligence Hub'`. Added to `defaultCapabilities` for `manager` role. The `owner` role already gets all capabilities.  
- No backend schema change is needed — capabilities are stored as a JSON array in `unix_staff.capabilities`. Just granting `can_access_bi` via the Staff Management screen is enough for existing storekeepers.

#### Task 2 — BI Hub Shell
- **New file: `flutter_app/lib/screens/store/bi_shell.dart`**: `DefaultTabController` with 3 tabs — Variance Dashboard, Yield Config, Price Impact Advisory. Has a premium header bar with the YUNIX brand aesthetic. Tabs are rendered inline (not full-page navigation) so the sidebar remains stable.  
- **`store_shell.dart`**: Removed separate `yield_` and `variance` nav entries. Replaced with a single `bi` entry (`Icons.bar_chart_rounded`, label `'Business Intelligence'`) gated by `s.canAccessBI && _flag('module_bi')`. The `_NavItem.yield_` and `_NavItem.variance` enum cases are removed. Imports for `yield_config_screen.dart` and `variance_screen.dart` replaced with `bi_shell.dart`.

#### Task 3 — UI Cleanup
- **`inventory_screen.dart`**: Stripped the `priceWarning` response-check and the `showDialog(_PriceAdvisoryDialog(...))` call from `_AdjustStockDialogState._save()`. `adjustStock()` return value no longer needed so it's awaited without assignment. The `_PriceAdvisoryDialog` class is fully deleted (~280 lines removed). Stock receipts now complete silently and cleanly.
- **`variance_screen.dart`**: Removed `_inflation` list, the `getInflationSummary()` `Future.wait` secondary call, the `_InflationHeatmap` widget render in `build()`, and the entire `_InflationHeatmap` class definition. Variance screen is now focused purely on physical stock variances.

#### Task 4 — Price Impact Advisory Screen (Backend + Frontend)
- **`src/routes/inventory.js` — `GET /api/inventory/inflation-summary`**: Heavily extended. Now accepts `?days=N` query param (default 30, capped 1–365). Added LEFT JOINs to `unix_yield_config` and `products` (read-only uniCenta). Groups results by inventory item server-side, returning an array where each item has an `impacted_products` array of `{pos_product_id, pos_product_name, pos_sell_price, portions_per_unit, cost_rise_per_portion}`.  
- **`flutter_app/lib/services/api.dart`**: Extended `getInflationSummary()` to accept `{int days}` param, new `sendPriceImpact({phone, days})` method.  
- **New file: `flutter_app/lib/screens/store/price_impact_screen.dart`**: Full-featured screen with:
  - Header with 7d/30d/90d period toggle chips
  - Per-ingredient card layout (border colour: red = cost up, green = cost down) showing old→new cost, % change, weekly KES impact
  - Expandable sub-table showing linked POS products, their sell price, portions-per-unit, and cost-rise-per-portion
  - "No yield config linked" hint when an ingredient has no POS mappings
  - Green "Send via WhatsApp" button in the header

#### Task 5 — WhatsApp Integration
- **`src/routes/inventory.js` — `POST /api/inventory/send-price-impact`**: Runs the same underlying query, formats the data into a WhatsApp-friendly markdown/emoji message (grouped by ingredient, showing cost change, % change, weekly KES impact, per-product portion breakdown). Returns `{ ok, message, whatsapp_url }`. `whatsapp_url` uses `https://api.whatsapp.com/send?phone=...&text=...` deep-link pattern (consistent with Pay Runs and Procurement routes).  
- **`price_impact_screen.dart`**: Prominent "Send via WhatsApp" button in the header bar. Clicking opens `_WhatsAppDialog` asking for an optional phone number (international format). Submitting calls `sendPriceImpact()` and `launchUrl()` to open WhatsApp. `url_launcher: ^6.3.0` was already in `pubspec.yaml`.

### Architectural decisions

1. **`module_bi` feature flag**: The sidebar entry checks `_flag('module_bi')`. This flag doesn't need to exist in the DB for the feature to work (the `_flag()` helper defaults to `true` when not found). Gemini can add the row if fine-grained module control is needed later.

2. **BI Shell is a Column + TabBarView, not a Scaffold**: `BIShell` deliberately avoids wrapping in a `Scaffold` because it's embedded inside `StoreShell`'s `Expanded(child: _body())`. Wrapping in a second Scaffold caused double AppBars in earlier milestones — this is the correct pattern for this architecture.

3. **Grouping done server-side**: The inflation-summary query now returns one row per `(inventory_item × yield_config_row)`, and the JOIN fan-out is collapsed into `impacted_products` arrays in the Node.js route handler before sending JSON. This keeps the Flutter side clean and avoids complex groupBy logic in Dart.

4. **`_PriceAdvisoryDialog` removal**: The backend `PATCH /:id/adjust` still computes `priceWarning` in the response. It's harmless to leave that logic there as it's the foundation for the BI reporting query. The Flutter side just no longer reads or displays it.

### Known notes for Gemini
- The `can_access_bi` capability needs to be granted in the DB for existing store-keeper staff who should see the BI Hub (managers/owners get it via role fallback). A one-time SQL like `UPDATE yunix_staff SET capabilities = JSON_ARRAY_APPEND(capabilities, '$', 'can_access_bi') WHERE role IN ('store') AND JSON_CONTAINS(capabilities, '"can_view_variance"')` can be used if needed.
- The BI Hub will render fine on tablets (>= 800px) and on mobile (drawer-based nav). The tab labels might need testing on very small screens — they can be made icon-only if text overflows.

---

## Milestone 17 — Database Prefix & Microservice Isolation

**Date:** 2026-04-18  
**Status:** Complete

### What was built

#### Task 1 — Migration File Rename (000–015)
All 16 existing migration SQL files were bulk-renamed using the following prefix map:

| Old name | New name |
|---|---|
| `unix_migrations` | `store_migrations` |
| `unix_store_inventory` | `store_inventory` *(redundant 'store' dropped)* |
| `unix_suppliers` | `store_suppliers` |
| `unix_supplier_ledger` | `store_supplier_ledger` |
| `unix_requisitions` | `store_requisitions` |
| `unix_yield_config` | `store_yield_config` |
| `unix_cost_history` | `store_cost_history` |
| `unix_pay_runs` | `store_pay_runs` |
| `unix_pay_run_details` | `store_pay_run_details` |
| `unix_purchase_orders` | `store_purchase_orders` |
| `unix_po_details` | `store_po_details` |
| `unix_procurement_logs` | `store_procurement_logs` |
| `unix_staff` | `yunix_staff` |
| `unix_settings` | `yunix_settings` |
| `unix_feature_flags` | `yunix_feature_flags` |

Only actual table name references were changed. Comments and migration filenames (e.g. `001_init_unix_schema.sql`) were left as-is.

#### Task 2 — Migration 016: Safe Rename Hook
Created `migrations/016_rename_existing_tables_for_isolation.sql`. This file contains `RENAME TABLE IF EXISTS` statements for every unix_ → store_/yunix_ table. The rename order is child-before-parent to satisfy FK constraints. On fresh installs, all IF EXISTS guards make it a no-op.

`unix_migrations` is renamed last, after all data tables, so the tracker table itself is migrated correctly.

#### Task 3 — db.js: Pre-boot Rename Hook
Added `ensureMigrationTableMigrated()` to `src/db.js`. Before the migration engine creates or reads `store_migrations`, it queries `information_schema.tables` to detect whether `unix_migrations` still exists. If found, it issues a raw `RENAME TABLE unix_migrations TO store_migrations`. This prevents the migration engine from creating an empty `store_migrations` and then re-running all migrations from scratch on an existing server.

Boot sequence on an existing server:
1. `ensureMigrationTableMigrated()` renames `unix_migrations → store_migrations`
2. `CREATE TABLE IF NOT EXISTS store_migrations` — no-op (already exists)
3. Reads all applied filenames — history intact
4. Skips 000–015, runs only 016 (RENAME TABLE for all data tables)
5. App starts normally with zero data loss

#### Task 4 — src/ Global Refactor
All 12 JS files under `src/` were updated with the same prefix mapping. SQL strings in route handlers, query calls, and comments now consistently reference `store_*` and `yunix_*` tables.

#### Task 5 — Flutter App Verification
No Dart files contained hardcoded `unix_` table names (as expected — the Flutter app communicates via JSON API). Two user-facing strings in `super_admin_dashboard.dart` and one docstring in `api.dart` that mentioned "unix_ tables" were updated to "store_ tables".

### Architectural decisions

1. **Two-prefix scheme**: `store_` for tables owned exclusively by this service; `yunix_` for tables shared across the ecosystem (staff, settings, feature flags). This is the long-term isolation boundary.

2. **Pre-boot hook over migration-only**: Migration 016 handles the rename for new deployments tracking via `store_migrations`. But on existing servers, the tracking table itself is `unix_migrations` — so the pre-boot hook in `db.js` must run first, before any migration query. This is a hardcoded JS check, not a SQL migration, intentionally.

3. **`RENAME TABLE IF EXISTS` throughout**: MariaDB's `RENAME TABLE IF EXISTS` (10.5+) is used in migration 016 to make every statement idempotent. If the admin re-runs the migration or it was partially applied, no error is thrown.

### Notes for Gemini
- The `yunix_staff` table rename is the most impactful shared-ecosystem change. Any other service (Waiter app, M-Pesa service) that directly queries this table must also be updated.
- `yunix_settings` and `yunix_feature_flags` are now clearly marked as shared ecosystem tables by their prefix — no service should write migrations that drop or alter these without coordinating across services.
- Migration 016 must succeed before any other new migrations are added. If you add a migration 017+, ensure the server has successfully applied 016 first.

---

## Milestone 18 — Requisition Audit Timeline

**Date:** 2026-04-21  
**Status:** Complete

### What was built

#### Database — `migrations/017_requisition_timeline.sql`
New `store_requisition_timeline` table:
- `id` VARCHAR(36) PK, `requisition_id` FK → `store_requisitions(id)` ON DELETE CASCADE
- `entry_type` ENUM(`'system'`, `'comment'`) — immutable design; no UPDATE/DELETE endpoints exist
- `actor_name` VARCHAR(100) NULL — populated on user comments and attributed system events
- `message` TEXT — the event or comment text
- `created_at` DATETIME DEFAULT CURRENT_TIMESTAMP

#### Backend — `src/routes/requisitions.js`

**`logTimelineEvent(reqId, message, actorName, entryType)` helper:**
- Fire-and-forget async function — logs to `store_requisition_timeline`; errors only `console.warn` so they never block the main requisition action

**`REQ_COLS` shared fragment:**
- All three GET endpoints (`/`, `/pending`, `/:id`) now select a `timeline_count` subquery via `COALESCE((SELECT COUNT(*) ...), 0)`. The list view gets activity counts without a separate round-trip.

**Automatic system event hooks:**
- `POST /api/requisitions` (create): logs `"Requisition submitted by {requested_by}."`
- `PATCH /:id/issue` (after commit): logs `"Issued by {issued_by}. Quantity: {qty} {uom}[. Note: {notes}]"`
- `PATCH /:id/reject`: now accepts optional `rejected_by` body param; logs `"Rejected by {actor}.[Reason: {reason}]"`

**New endpoints (immutable — no edit/delete by design):**
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/requisitions/:id/timeline` | Fetch all entries ASC for a requisition |
| POST | `/api/requisitions/:id/timeline` | Add a user comment (`actor_name` + `message` required) |

#### Flutter — models

**`lib/models/timeline_entry.dart`** (new):
- `id`, `requisitionId`, `entryType`, `actorName?`, `message`, `createdAt` (parsed DateTime)
- `isSystem` / `isComment` getters
- `formattedTime` getter using `DateFormat('dd MMM, HH:mm')`

**`lib/models/requisition.dart`** (updated):
- Added `timelineCount: int` field (default `0`), populated from `timeline_count` in JSON
- Added `hasActivity` getter (`timelineCount > 0`)

#### Flutter — services

**`lib/services/api.dart`** (updated):
- Import added: `timeline_entry.dart`
- `rejectRequisition(id, {reason?, rejectedBy?})` — new optional `rejectedBy` param forwarded as `rejected_by`
- `getRequisitionTimeline(String id)` → `GET /api/requisitions/$id/timeline` → `List<TimelineEntry>`
- `addTimelineComment(String reqId, String actorName, String message)` → `POST /api/requisitions/$reqId/timeline`

#### Flutter — UI

**`lib/screens/store/requisition_timeline_sheet.dart`** (new):
- `showRequisitionTimeline(context, {req, currentUserName})` — public entry point; opens a `showModalBottomSheet`
- **`DraggableScrollableSheet`**: initialChildSize 0.75, max 0.95 — draggable to nearly full screen on desktop/tablet
- **Header**: item name, "Requisition Activity Log · {requester}" subtitle, close button
- **Empty state**: chat bubble icon + guidance text
- **System event entries** (`_SystemEventPill`): centred pill with dividers either side, lightning bolt icon, event text + timestamp — matches Jira/GitHub ticket event style
- **Comment bubbles** (`_CommentBubble`): left-aligned for others (teal avatar), right-aligned for current user (amber avatar); asymmetric border radius; teal-tinted bubble for own comments
- **Comment input** (`_CommentInput`): rounded pill TextField, filled send button; comment triggers `addTimelineComment()` then reloads

**`lib/screens/store/requisition_approval.dart`** (updated):
- Imported `requisition_timeline_sheet.dart`
- `_reject()` now passes `rejectedBy: widget.staff.name` to `rejectRequisition()`
- New `_openTimeline(req)` method — calls `showRequisitionTimeline`, then refreshes requisition list on sheet close (catches new timeline count)
- `_RequisitionCard` extended with `onTimeline` callback param
- Added timeline activity indicator in the card's action column (between status badge and issue/reject buttons):
  - Grey chat icon when no activity (`timelineCount == 0`)
  - Teal chat icon + count badge when `hasActivity` — visible to all roles

### Architectural decisions

**Why fire-and-forget for timeline logging:**
The stock deduction transaction in `PATCH /:id/issue` is the financially critical operation. Wrapping it with a timeline INSERT would mean a timeline write failure could rollback a valid issue. Timeline is audit metadata — it should never block the core action.

**Why `timeline_count` is a subquery on the list, not a separate API call:**
Fetching timeline entries per card (N+1) on the approval screen would be expensive at scale. The subquery runs inside a single `SELECT` and adds negligible overhead since `store_requisition_timeline` is indexed on `requisition_id`.

**Why no edit/delete endpoints:**
The entire value of the audit timeline is its immutability. Removing or editing entries would defeat the accountability purpose stated in the business requirement (Kitchen claims they requested on time; Store claims otherwise). Immutability makes the log legally credible.

**Why the bottom sheet rather than a new screen:**
The approval screen already auto-polls every 30 seconds. Pushing a full Navigator route would pause that context. A `showModalBottomSheet` overlays the screen, letting the user comment without abandoning the queue context, and refreshes the list when dismissed.

**Why `rejected_by` is optional on the backend:**
Backward compatibility with any existing callers that don't pass the field. The backend defaults the actor label to `'Storekeeper'` if omitted.

### New API endpoints summary
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/requisitions/:id/timeline` | Chronological audit log for one requisition |
| POST | `/api/requisitions/:id/timeline` | Add immutable user comment |

---

## Bug Fix — Kitchen Timeline Missing (Completed: 2026-04-22)

### Problem
Milestone 18 only wired the timeline chat icon and bottom sheet to the Store approval screen. The Kitchen screen's "Today's Requests" panel (`_MyRequestsPanel` / `_RequestCard`) had no chat icon, no tap handler, and no call to `showRequisitionTimeline`.

### Root Cause
The `onOpenTimeline` callback was never threaded into the widget tree:
`_KitchenRequisitionScreenState` → `_Body` → `_MyRequestsPanel` → `_RequestCard`
and the parallel mobile path:
`_KitchenRequisitionScreenState` → `_MenuDrawer` → `_MyRequestsPanel` → `_RequestCard`

### Changes — `flutter_app/lib/screens/kitchen/kitchen_requisition.dart`

1. **Import added**: `import '../store/requisition_timeline_sheet.dart'`

2. **`_KitchenRequisitionScreenState._openTimeline()`** (new method):
   - Calls `showRequisitionTimeline(context, req: req, currentUserName: widget.staff.name)`
   - Calls `_loadMyRequests()` after the sheet closes to refresh `timelineCount` badges

3. **`_Body`**: Added `onOpenTimeline` required param; forwards to `_MyRequestsPanel`

4. **`_MenuDrawer`**: Added `onOpenTimeline` required param; forwards to `_MyRequestsPanel`

5. **`_MyRequestsPanel`**: Added `onOpenTimeline` required param; passes `() => onOpenTimeline(requests[i])` to each `_RequestCard`

6. **`_RequestCard`** (major update):
   - Added `onTimeline` optional callback
   - Wrapped in `Material` + `InkWell` so the whole card is tappable
   - Added trailing `Column` with time on top and chat icon + count below:
     - Dim grey (`0xFF37474F`) when no activity
     - Teal (`AppTheme.pinTeal`) + count badge when `req.hasActivity`
   - Fixed display name for new-item requests: shows `req.newItemName` instead of raw `[NEW ITEM REQUEST]`

---

## Milestone 19 — Procurement Item Postponement (Completed: 2026-04-22)

### Problem
The procurement screen allowed adjusting quantities on system-suggested items, and hard-deleting ad-hoc items, but offered no way to exclude a system-suggested item from the current draft order. The user had no way to say "don't order Cheese this run."

### Solution
Client-side soft-exclude (postpone) pattern — no backend changes required. The excluded state lives only in `_EditableItem.excluded` and is discarded when the screen is regenerated.

### Changes — `flutter_app/lib/screens/store/procurement_screen.dart`

**`_EditableItem`:**
- Added `bool excluded = false` mutable field
- No backend or DB implication — purely in-memory session state

**`_EditableGroup`:**
- Added `activeItems` getter: `items.where((i) => !i.excluded && i.qty > 0)`
- Added `excludedCount` getter
- Updated `toPayload()` to use `activeItems` instead of `items.where(qty > 0)` — excluded items are never sent to `buildProcurementWhatsApp`

**`_EditableProcurementCard` header:**
- Item count now shows `activeItems.length` (e.g. "4 items")
- When `excludedCount > 0`, a red sub-label "N postponed" appears below the count — gives instant feedback on the session's exclusions

**Item rows:**
- `AnimatedOpacity(0.45)` wraps excluded rows — smooth visual fade on toggle
- Excluded item name renders in strikethrough + grey
- "Postponed — not included in order" italic label appears below excluded item name
- Qty field is `enabled: false` when excluded (prevents confusing edits on a postponed item)
- **Three trailing button states:**
  1. Ad-hoc + not excluded → red `remove_circle` (hard delete, same as before)
  2. System-suggested + not excluded → red `do_not_disturb_on` "Postpone" → sets `excluded = true`
  3. Any excluded item → green `undo` "Restore" → sets `excluded = false`

**Send button:**
- Disabled (grayed out) when `group.activeItems.isEmpty`
- Warning text "All items postponed — nothing to send" replaces phone-missing text when all items are excluded

### Architectural decisions

**Why soft-exclude instead of hard delete for system items:**
Ad-hoc items are user-created, so hard delete is the right semantic (the user added it, they can remove it entirely). System-suggested items are auto-generated from reorder math — hard-deleting them could make the user think they've resolved an out-of-stock issue when they've just dismissed it. The undo affordance prevents accidental exclusion from silently hiding real procurement needs.

**Why client-side only:**
The instructions explicitly required "NOT saved to the database". The procurement draft is ephemeral — it's regenerated fresh each time "Generate Lists" is tapped. Persisting exclusions would add a DB table for a session-scoped decision. The correct scope is the current browser/app session.

**Why `AnimatedOpacity` rather than removing from the list:**
Keeping excluded items visible (but visually suppressed) lets the user see what they've postponed at a glance and restore with one tap. Removing from the list would require a separate "Show postponed" UI to recover them.

---

## Investigation: Variance Date Filters & Metabase Reporting Strategy

**Date:** 2026-05-05  
**Status:** Analysis only — no code changes made.

---

### Executive Summary

The current system is in excellent shape for adding date filters to the Flutter app — the backend already has most of what is needed. The Metabase story is also straightforward because both legacy POS tables and store tables live in the same `unicentapos` database. The three main things that need attention before building are: (1) a small correctness bug in the variance query (`quantity` vs `issued_quantity`), (2) aligning the store service to the 7 AM business-day shift, and (3) deciding whether to add a `store_stock_ledger` table for full historical stock tracking (not strictly needed for the variance dashboard, but needed for opening/closing balance reports).

---

### 1. Is the Schema a Ledger or an Overwrite?

**`store_requisitions` IS already an append-only event ledger for issues.**  
Every stock movement (Sales, Staff Meal, Wastage) creates a new row with `requested_at` and `issued_at` timestamps. No row is edited in-place for issuance — a new row is always appended. This is the right architecture and means date-range variance is already possible without schema changes.

**What IS overwritten:**  
`store_inventory.quantity_in_stock` — decremented on every issue, incremented on every delivery. It is a live snapshot, not history. Metabase cannot ask "what was the stock level on 15 April?" — it only knows the current level.

**The missing piece — stock receipts (deliveries) are not event-logged.**  
When a delivery arrives via `PATCH /api/inventory/:id/adjust`, the code does `UPDATE store_inventory SET quantity_in_stock = quantity_in_stock + delta`. There is no corresponding row written to any historical table. The cost change is logged to `store_cost_history`, but the *quantity received* is not. This means:
- Variance by date range: ✅ fully supported (uses `store_requisitions`)
- Opening/closing stock per period: ❌ not possible today (no receipt event log)

**Recommendation: Add `store_stock_ledger` — low urgency, high future value.**

Proposed schema (to add in a future migration):
```sql
CREATE TABLE store_stock_ledger (
  id                VARCHAR(36)   NOT NULL,
  inventory_item_id VARCHAR(36)   NOT NULL,
  movement_type     ENUM('RECEIPT','ISSUE','ADJUSTMENT','CYCLE_COUNT') NOT NULL,
  quantity          DECIMAL(12,3) NOT NULL,  -- positive = in, negative = out
  reference_id      VARCHAR(36)   NULL,      -- FK to store_requisitions.id or PO id
  reference_type    VARCHAR(30)   NULL,      -- 'requisition', 'purchase_order', 'manual'
  purpose           VARCHAR(50)   NULL,      -- 'Sales','Staff Meal','Wastage','Delivery'
  actor_name        VARCHAR(100)  NULL,
  notes             VARCHAR(500)  NULL,
  transaction_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_ledger_item_date (inventory_item_id, transaction_at),
  INDEX idx_ledger_date      (transaction_at)
);
```
Write to this on every stock change (issues, deliveries, adjustments, cycle count corrections). This becomes the single source of truth for "stock movement over any period" in Metabase. **Build this only after the date-filter variance is working — it is not a blocker for the immediate features.**

---

### 2. How the Current Variance Query Works

The query at [`src/routes/pos.js:113`](src/routes/pos.js) has three layers:

**Layer A — Yield Config backbone:**  
`store_yield_config` joined to `store_inventory` → gives ingredient ↔ POS product mapping and `portions_per_unit` ratio.

**Layer B — POS Sales subquery (legacy tables, read-only):**
```sql
SELECT tl.product, SUM(tl.units) AS total_sold
FROM ticketlines tl
JOIN tickets t  ON t.id = tl.ticket
JOIN receipts r ON r.id = t.id
WHERE DATE(r.datenew) = CURDATE()   -- ← "today" hardcoded
  AND t.tickettype = 0
GROUP BY tl.product
```

**Layer C — Actual issued subquery (store table):**
```sql
SELECT inventory_item_id,
  SUM(CASE WHEN purpose = 'Sales'    THEN quantity ELSE 0 END)
  - SUM(CASE WHEN purpose = 'Wastage' THEN quantity ELSE 0 END)
    AS total_issued
FROM store_requisitions
WHERE status = 'Issued'
  AND purpose IN ('Sales', 'Wastage')
  AND DATE(issued_at) = CURDATE()   -- ← "today" hardcoded
GROUP BY inventory_item_id
```

**Can this support date range filters? YES — trivially.**  
The date filter is in exactly two places in the whole query. Replace `CURDATE()` comparisons with parameterized range bounds. The existing `/api/pos/sales/range?from&to` endpoint already demonstrates this pattern. A new `GET /api/pos/variance/range?from=YYYY-MM-DD&to=YYYY-MM-DD` endpoint can reuse 95% of the existing SQL.

**Latent correctness bug — `quantity` vs `issued_quantity`:**  
Layer C uses `quantity` (the originally-requested amount). But since Milestone 8, the storekeeper can issue a *different* quantity (`issued_quantity` column, added in migration 011). For any partial issuance, the variance will be wrong. The correct column is `COALESCE(issued_quantity, quantity)`. **Fix this before adding date filters so all historical data is accurate.**

---

### 3. Performance & the 60-Second Auto-Refresh

**Why is the query heavy?**

Three compounding reasons:

1. **`DATE()` wrapping prevents index use.** `DATE(r.datenew) = CURDATE()` forces a full-table function evaluation on `receipts`. Same for `DATE(issued_at)`. Fix: use range comparisons `r.datenew >= CURDATE() AND r.datenew < CURDATE() + INTERVAL 1 DAY` — this lets MariaDB use an index on `datenew` if one exists.

2. **The query joins 5+ tables across legacy and store schemas in a single round trip.** Each call scans `ticketlines → tickets → receipts` for the day's sales, plus `store_requisitions` for issuances, plus the yield config join. On a busy restaurant POS with months of data in `ticketlines`, this is non-trivial.

3. **The 60-second timer fires regardless of whether anyone is watching the screen.** The timer starts in `initState()` and only cancels in `dispose()`. If a user leaves the BI Hub open while doing other work, it runs silently in the background forever.

**Recommendation: Kill the auto-refresh for the Variance screen.**

The variance dashboard is analytical, not operational. Unlike the Kitchen screen (which must show live pending requests), variance is a shift-management tool — it doesn't need sub-minute freshness. The manual Refresh button already exists. Steps:

1. Remove `Timer.periodic(...)` from `VarianceScreen.initState()` — 5-minute change.
2. Add a short server-side in-memory cache in `pos.js` for the `variance/today` endpoint (5-minute TTL). This means even if a user hammers the manual Refresh button, the DB is only hit once every 5 minutes.
3. Confirm `receipts.datenew` has an index in the MariaDB schema. If not, add one (it's a read-only legacy table — adding an index is safe and not a violation of the read-only rule).

---

### 4. The 7 AM Business Day Shift

**Current behavior:** Both the variance query and `/sales/today` use `DATE(r.datenew) = CURDATE()` — standard midnight-to-midnight. A kitchen issuance at 2 AM Wednesday counts as Wednesday's issues, but it was actually part of Tuesday's dinner service.

**The existing Metabase dashboards already use a 7 AM shift**, so the store service needs to match for the data to be comparable.

**The formula:**
```
business_day(timestamp) = DATE(timestamp - INTERVAL 7 HOUR)
```

Example: 2 AM Wednesday − 7 hours = Wednesday 7 PM Tuesday → DATE = Tuesday ✓

**SQL implementation:**
```sql
-- "Today's business day" comparisons:
-- Instead of: WHERE DATE(r.datenew) = CURDATE()
WHERE DATE(r.datenew - INTERVAL 7 HOUR) = DATE(NOW() - INTERVAL 7 HOUR)

-- Range for a specific business day X:
WHERE r.datenew >= CONCAT(DATE(X), ' 07:00:00')
  AND r.datenew < DATE_ADD(CONCAT(DATE(X), ' 07:00:00'), INTERVAL 1 DAY)
```

**Where to apply:**
- `GET /api/pos/variance/today` — both the sales and issuances subqueries
- The new `variance/range` endpoint — from/to params treated as business days, expanded to actual timestamps using the 7-hour offset
- `/api/pos/sales/today` — for consistency

**Implementation tip:** Add a `BUSINESS_DAY_SHIFT_HOURS` environment variable (default `7`) to make this configurable per client in the future.

---

### 5. Metabase Integration Strategy

**The big advantage: everything is in one database.**  
Metabase is on the same `unicenta-network` Docker network and connects directly to MariaDB `unicentapos` (confirmed in `docker-compose.yml:18-32`). Both `store_*` tables and legacy `ticketlines/receipts/products` are in the same schema. This means Metabase SQL questions can freely JOIN them — no HTTP calls, no API bridging, no cross-database complexity.

**`JAVA_TIMEZONE=Africa/Nairobi` is already set on the Metabase container** — timezone-aware queries will work correctly.

---

#### Proposed Metabase Dashboard 1: "Daily Variance Report"

This is the primary management dashboard — replaces the need to open the Flutter app for long-range analysis.

Core query (uses Metabase `{{date_from}}` and `{{date_to}}` filter variables):
```sql
SELECT
  i.name                                                           AS item,
  i.unit_of_measure                                                AS uom,
  i.cost_per_unit,
  GROUP_CONCAT(p.name ORDER BY p.name SEPARATOR ' / ')            AS pos_products,
  ROUND(SUM(COALESCE(sales.total_sold, 0) / yc.portions_per_unit), 3)
                                                                   AS expected_qty,
  COALESCE(iss.total_issued, 0)                                   AS actual_issued,
  ROUND(COALESCE(iss.total_issued, 0)
    - SUM(COALESCE(sales.total_sold, 0) / yc.portions_per_unit), 3)
                                                                   AS variance_qty,
  ROUND(
    (COALESCE(iss.total_issued, 0)
    - SUM(COALESCE(sales.total_sold, 0) / yc.portions_per_unit))
    * COALESCE(i.cost_per_unit, 0), 2
  )                                                                AS variance_kes
FROM store_yield_config yc
JOIN store_inventory i ON i.id = yc.inventory_item_id
LEFT JOIN products p ON p.id = yc.unicenta_product_id
LEFT JOIN (
  -- POS sales with 7 AM business-day shift
  SELECT tl.product, SUM(tl.units) AS total_sold
  FROM ticketlines tl
  JOIN tickets t  ON t.id = tl.ticket
  JOIN receipts r ON r.id = t.id
  WHERE DATE(r.datenew - INTERVAL 7 HOUR)
          BETWEEN {{date_from}} AND {{date_to}}
    AND t.tickettype = 0
  GROUP BY tl.product
) sales ON sales.product = yc.unicenta_product_id
LEFT JOIN (
  -- Actual issued (Sales minus Wastage) with 7 AM shift
  SELECT
    inventory_item_id,
    SUM(CASE WHEN purpose = 'Sales'
             THEN COALESCE(issued_quantity, quantity) ELSE 0 END)
    - SUM(CASE WHEN purpose = 'Wastage'
               THEN COALESCE(issued_quantity, quantity) ELSE 0 END)
      AS total_issued
  FROM store_requisitions
  WHERE status = 'Issued'
    AND purpose IN ('Sales', 'Wastage')
    AND inventory_item_id IS NOT NULL
    AND DATE(issued_at - INTERVAL 7 HOUR)
          BETWEEN {{date_from}} AND {{date_to}}
  GROUP BY inventory_item_id
) iss ON iss.inventory_item_id = yc.inventory_item_id
GROUP BY i.id, i.name, i.unit_of_measure, i.cost_per_unit, iss.total_issued
ORDER BY ABS(variance_kes) DESC NULLS LAST
```

The `{{date_from}}` and `{{date_to}}` become a date-range picker widget automatically in the Metabase dashboard UI.

---

#### Proposed Metabase Dashboard 2: "Weekly Variance Trend"

Shows whether variance is improving or worsening week-over-week. Group by business week:
```sql
SELECT
  YEARWEEK(DATE(r.datenew - INTERVAL 7 HOUR), 1) AS business_week,
  MIN(DATE(r.datenew - INTERVAL 7 HOUR))         AS week_start,
  i.name                                          AS item,
  ROUND(SUM(tl.units) / yc.portions_per_unit, 3) AS expected_qty,
  -- join to store_requisitions as in Dashboard 1...
```

This gives a time-series chart per ingredient — powerful for spotting seasonal patterns (e.g. chicken variance always spikes on weekends).

---

#### Proposed Metabase Dashboard 3: "Staff Meal & Wastage Cost"

A separate view showing the KES cost of non-sales stock movements — segmented by purpose:
```sql
SELECT
  DATE(issued_at - INTERVAL 7 HOUR)   AS business_date,
  purpose,
  i.name                               AS item,
  SUM(COALESCE(issued_quantity, quantity)) AS qty_issued,
  SUM(COALESCE(issued_quantity, quantity) * COALESCE(i.cost_per_unit, 0)) AS cost_kes
FROM store_requisitions sr
JOIN store_inventory i ON i.id = sr.inventory_item_id
WHERE status = 'Issued'
  AND purpose IN ('Staff Meal', 'Wastage', 'Other')
  AND inventory_item_id IS NOT NULL
  AND DATE(issued_at - INTERVAL 7 HOUR)
        BETWEEN {{date_from}} AND {{date_to}}
GROUP BY business_date, purpose, sr.inventory_item_id, i.name
ORDER BY business_date DESC, cost_kes DESC
```

---

### 6. Pitfalls for Metabase Queries

**1. `issued_quantity` vs `quantity` — always use `COALESCE(issued_quantity, quantity)`.**  
`issued_quantity` was added in migration 011. Older rows (before partial issuance was implemented) have `issued_quantity = NULL`. `COALESCE` handles both old and new rows correctly. Never use bare `quantity` in issued-stock aggregations.

**2. `inventory_item_id = NULL` rows exist.**  
Free-text "new item requests" have `inventory_item_id = NULL`. Always add `WHERE inventory_item_id IS NOT NULL` to any aggregation that joins `store_inventory`.

**3. `purpose` has 4 values: Sales, Staff Meal, Wastage, Other.**  
The variance engine only compares Sales vs POS. Staff Meal and Wastage are separate cost categories. Filter `purpose = 'Sales'` for variance; use `purpose IN ('Staff Meal','Wastage','Other')` for cost reporting.

**4. `receipts.datenew` index.**  
Over months of operation, `ticketlines` + `receipts` grows large. Confirm `receipts.datenew` has an index. Long-range Metabase queries (30+ days) will be slow without it. Check with: `SHOW INDEX FROM receipts`. Adding an index to a legacy table is safe — it does not violate the read-only rule (the rule only prohibits INSERT/UPDATE/DELETE on the data, not schema maintenance).

**5. Timezone — verify MariaDB `time_zone`.**  
`JAVA_TIMEZONE=Africa/Nairobi` is set on the Metabase container. But if MariaDB's `@@time_zone` is still `UTC` (the Docker default), then `NOW()` and `CURDATE()` return UTC time inside SQL queries. The 7 AM shift math (`- INTERVAL 7 HOUR`) partially compensates, but the boundaries can be off by 3 hours (EAT = UTC+3). Verify with `SELECT @@global.time_zone` and set it to `Africa/Nairobi` if needed.

---

### 7. Flutter App: Adding Date Filters to the Variance Screen

#### Backend: New Range Endpoint
Add `GET /api/pos/variance/range?from=YYYY-MM-DD&to=YYYY-MM-DD` to `pos.js`. Almost identical to the existing `variance/today` query — only the date filter changes. Keep `variance/today` as a convenience alias (internally call the range endpoint with today's business date, or keep the existing query untouched and have both).

#### Flutter: UI Changes to `VarianceScreen`

1. **Add `_selectedPeriod` state** — an enum: `today`, `yesterday`, `this_week`, `last_week`, `custom`.
2. **Add a period selector in the header** — a `SegmentedButton` or `ChoiceChip` row. Options: `Today | Yesterday | This Week | Last Week | Custom`.
3. **For `custom`, call `showDateRangePicker()`** — built into Flutter Material, gives a calendar UI.
4. **Replace `getVarianceToday()` call** with `getVarianceRange(from, to)` calling the new endpoint.
5. **Update the screen title** to show the selected period (e.g., "Usage Variance — This Week (29 Apr – 5 May)").
6. **Remove the 60-second `Timer.periodic`** — keep only the manual Refresh button.

**Business-day period calculations in Dart:**
```dart
// Helper: which business day does this DateTime fall on?
DateTime businessDay(DateTime dt) {
  final shifted = dt.subtract(const Duration(hours: 7));
  return DateTime(shifted.year, shifted.month, shifted.day);
}

// "Today" as a business day
final today = businessDay(DateTime.now());

// "Yesterday"
final yesterday = today.subtract(const Duration(days: 1));

// "This week" — Monday to today
final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
final thisWeekEnd = today;

// Format for API: YYYY-MM-DD
String fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
```

---

### 8. Implementation Priority Order

| Priority | Task | Effort | Impact |
|---|---|---|---|
| 1 | Fix `quantity` → `COALESCE(issued_quantity, quantity)` in variance query | 5 min | Correctness fix |
| 2 | Add `GET /api/pos/variance/range?from&to` with 7 AM shift | 1–2 hrs | Core new feature |
| 3 | Add date period selector to Flutter `VarianceScreen` | 2–3 hrs | User-requested |
| 4 | Remove 60s auto-refresh from `VarianceScreen` | 5 min | Performance |
| 5 | Verify `receipts.datenew` index exists; add if missing | 15 min | Performance |
| 6 | Set up Metabase Dashboard 1 (Daily Variance) | 1–2 hrs | Reporting |
| 7 | Set up Metabase Dashboard 2 (Weekly Trend) | 1 hr | Reporting |
| 8 | Set up Metabase Dashboard 3 (Staff Meal & Wastage Cost) | 1 hr | Reporting |
| 9 | Add 5-min server-side cache in `pos.js` for `variance/today` | 30 min | Performance |
| 10 | Add `store_stock_ledger` table for full historical stock events | 2–3 hrs | Future (not blocker) |

---

## Milestone 20 — Date Filters, 7 AM Shift, Bug Fix & KPI Cards

**Date:** 2026-05-05  
**Status:** Complete

### What was built

#### Task 1 — Backend Bug Fix & 7 AM Business Day Shift (`src/routes/pos.js`)

**Partial issuance bug fixed:** The issued subquery previously used bare `quantity`, which ignores cases where the storekeeper issued a different amount than requested (added in Milestone 8 via `issued_quantity` column). Changed to `COALESCE(issued_quantity, quantity)` in both Sales and Wastage CASE branches. This affects historical accuracy for all partial issuances.

**7 AM shift applied:** Both the POS sales filter and the store requisitions filter now use the business-day shift formula:
```sql
DATE(r.datenew - INTERVAL 7 HOUR) = DATE(NOW() - INTERVAL 7 HOUR)
DATE(issued_at - INTERVAL 7 HOUR) = DATE(NOW() - INTERVAL 7 HOUR)
```
A 2 AM issuance on Wednesday now correctly falls within Tuesday's business day, matching the existing Metabase dashboard convention.

**Query refactored into a shared builder:** `_buildVarianceQuery(salesFilter, issuesFilter)` returns the full SQL with pluggable WHERE fragments. Both `variance/today` and `variance/range` call this function — DRY, no duplication.

#### Task 2 — `GET /api/pos/variance/range?from=YYYY-MM-DD&to=YYYY-MM-DD`

New endpoint added to `src/routes/pos.js`. Uses `BETWEEN ? AND ?` on the business-day-shifted dates. The `from` and `to` params are treated as business dates (7 AM shift applied inside the SQL). Four query params are passed to the prepared statement (two per subquery).

#### Task 3 — `GET /api/pos/issues-cost/today`

New endpoint added to `src/routes/pos.js`. Returns the total KES value of all items issued in the current 7 AM business day:
```json
{ "total_cost_kes": 4250.00, "total_issues": 12, "sales_count": 9, "staff_meal_count": 2, "wastage_count": 1 }
```
JOINs `store_requisitions` with `store_inventory` for `cost_per_unit`. Uses `COALESCE(issued_quantity, quantity)` for accuracy. Filters `inventory_item_id IS NOT NULL` to exclude free-text new-item requests.

#### Task 4 — Variance Screen Refactor (`flutter_app/lib/screens/store/variance_screen.dart`)

**Full rewrite** of the variance screen:

- **Auto-refresh removed:** `Timer.periodic` (60s) and its `_autoRefresh` state variable are gone. Users use the manual Refresh button only.
- **Period selector added:** A `ChoiceChip` row with 5 options — `Today | Yesterday | This Week | Last Week | Custom`. Custom opens Flutter's native `showDateRangePicker` calendar UI.
- **Business-day helpers:** `_businessDay(DateTime)` subtracts 7 hours and takes the date — same shift logic as the backend. `_periodDates()` returns `(from, to, title)` for any period enum value.
- **Dynamic title:** Header title updates to reflect the selected period (e.g. "Usage Variance — This Week", "Usage Variance — 29 Apr – 5 May").
- **API change:** Calls `getVarianceRange(from, to)` instead of `getVarianceToday()`. The `getVarianceToday()` API method is kept for backward compatibility.
- **Explainer banner updated** to mention the 7 AM business day.

#### Task 5 — Inventory Capital KPI Card (`flutter_app/lib/screens/store/inventory_screen.dart`)

- Added `_totalCapital` computed getter: `_items.fold(0.0, (sum, i) => sum + i.quantityInStock * (i.costPerUnit ?? 0.0))`.
- Added `_CapitalKpiCard` widget class: teal gradient card showing the total KES value of all stock with item count. Rendered below the inventory header, above the search bar, once loading completes.
- No additional API call needed — calculated from the already-fetched `_items` list.

#### Task 6 — Issued Cost KPI Card (`flutter_app/lib/screens/store/requisition_approval.dart`)

- Added `_issuedCostToday` and `_issuedCountToday` state fields.
- `_loadRequisitions()` now uses `Future.wait([getRequisitions(), getIssuedCostToday()])` — both calls fire in parallel so there is no extra latency.
- Added `_IssuedCostKpiCard` widget class: purple gradient card showing today's total issued cost (KES) and issue count. Sub-label reads "7 AM business day" so managers know the scope.
- Rendered between the `_TopBar` and `_FilterTabs` in the build method.

#### API service (`flutter_app/lib/services/api.dart`)

Two new methods added:
- `getVarianceRange(String from, String to)` → `GET /api/pos/variance/range?from=...&to=...`
- `getIssuedCostToday()` → `GET /api/pos/issues-cost/today`

### Architectural decisions

**Why a shared SQL builder function (`_buildVarianceQuery`):** The variance SQL is ~50 lines with complex multi-level JOINs. Duplicating it for `today` vs `range` would create a maintenance trap where one gets bugfixes the other doesn't. The builder takes just the two filter fragments that differ between the two endpoints.

**Why `variance/today` kept as a separate route:** Backward compatibility — the existing Flutter `getVarianceToday()` method still works; callers that haven't updated yet won't break. Internally, `variance/today` now uses the same shared builder with the 7 AM date filter.

**Why calculate inventory capital on the frontend:** The `getInventory()` call already fetches all items with `quantity_in_stock` and `cost_per_unit`. A separate backend aggregation endpoint would be a redundant round trip. The Dart fold is O(n) and runs in microseconds.

**Why `Future.wait` for requisitions + issued-cost:** The requisition approval screen already makes one heavy API call on every 30-second poll. Chaining `getIssuedCostToday()` sequentially would add ~50–200ms latency to every refresh. Parallel fetch keeps the UX snappy.

**Why the KPI cards only render when `!_loading`:** Showing a zero-value KPI while data is still fetching would look incorrect. The card appears only once real data is available, avoiding a flash of `KES 0`.

---

### Summary of Key Architectural Findings

| Question | Answer |
|---|---|
| Is `store_requisitions` an event ledger? | **Yes** — every issue is an append-only row with timestamps |
| Is stock delivery logged historically? | **No** — only `quantity_in_stock` is updated (overwrite) |
| Can date-range variance be done today? | **Yes** — the SQL only needs the `CURDATE()` replaced |
| Is there a correctness bug in the current query? | **Yes** — `quantity` should be `COALESCE(issued_quantity, quantity)` |
| Does the 7 AM shift apply to store tables? | **No yet** — needs to be added to match Metabase |
| Can Metabase JOIN store and legacy tables? | **Yes** — same `unicentapos` DB, same MariaDB instance |
| Is the 60s auto-refresh justified? | **No** — analytical dashboard, should be manual-only |

---

## Milestone 21 — Operational UI Polish & Filters

**Date:** 2026-05-05  
**Status:** Complete

### Task 1 — Requisitions Auto-Refresh & Error Handling (`requisition_approval.dart`)

- **Poll interval changed:** `Timer.periodic(Duration(seconds: 30), ...)` → `Timer.periodic(Duration(minutes: 30), ...)`. Countdown ticker reduced from per-second to per-minute.
- **Three-method pattern** introduced to separate background vs user-initiated fetches:
  - `_loadRequisitions()` — sets `_loading = true`, calls `_fetchAndApply()`, shows errors on failure (user-triggered path).
  - `_backgroundPoll()` — calls `_fetchAndApply()` inside a bare `try { } catch (_) { }` that swallows all exceptions silently (timer-triggered path).
  - `_fetchAndApply({bool background = false})` — shared data logic; calls `Future.wait([getRequisitions(), getIssuedCostToday()])` and applies state.
- **Result:** Red `ClientException` error screens from brief network drops during background polling are permanently eliminated.

### Task 2 — Supplier List Layout Fix (`supplier_ledger.dart`)

- **Root cause:** The `ListTile.title` `Row` used `mainAxisSize: MainAxisSize.min` with a `Flexible` wrapping the name `Text`. On wide screens, when the "Internal" badge was present, the `Flexible` could collapse to zero width, causing the name text to render one character per line.
- **Fix:** Changed to `Row()` (default `mainAxisSize: MainAxisSize.max`) + `Expanded` with `overflow: TextOverflow.ellipsis`. The name now takes all available space and gracefully truncates. The badge stays right-aligned within the row.

### Task 3 — Supplier Ledger Date Filters

#### Backend (`src/routes/suppliers.js`)

- **`GET /:id/ledger`**: Now accepts optional `?from=YYYY-MM-DD&to=YYYY-MM-DD` query params. If provided, adds `AND l.transaction_date >= ?` / `AND l.transaction_date <= ?` clauses to the SQL.
- **`GET /:id/statement`**: Accepts `?from=...&to=...` (custom range) OR `?days=N` (rolling window). When `from`/`to` are provided, `days` is computed from the difference for the summary section. Period label reflects the actual dates.
- **`GET /:id/statement/whatsapp`**: Same logic as above — WhatsApp message header now reads "Statement for period: X – Y" when a date filter is active.

#### API Service (`flutter_app/lib/services/api.dart`)

- `getSupplierLedger(supplierId, {String? from, String? to})` — builds query string conditionally.
- `getSupplierStatementWhatsApp(supplierId, {int days = 30, String? from, String? to})` — prefers `from`/`to` over `days` when both are provided.

#### Flutter UI (`flutter_app/lib/screens/store/supplier_ledger.dart`)

- **Enum + helpers** added at file scope: `_LedgerPeriod` (5 values: `thisMonth`, `lastMonth`, `last90`, `allTime`, `custom`), `_LedgerPeriodLabel` extension, `_fmtDate()`, `_ledgerPeriodDates()` — returns `({String? from, String? to, String label})`.
- **State** in `_SupplierDetailState`: `_LedgerPeriod _ledgerPeriod = _LedgerPeriod.allTime` and `DateTimeRange? _customLedgerRange`.
- **`_loadLedger()`**: Calls `_ledgerPeriodDates()` and passes `from`/`to` to `getSupplierLedger()`.
- **`_sendMiniStatement()`**: Calls `_ledgerPeriodDates()` and passes `from`/`to` to `getSupplierStatementWhatsApp()` — WhatsApp statement now always reflects the active filter.
- **`_LedgerPeriodSelector` widget**: Horizontally scrollable `ChoiceChip` row rendered above the "Transaction History" title. Custom period opens `showDateRangePicker`; the chip label updates to the selected date range (e.g. "1 Apr – 30 Apr"). Selecting any other period clears `_customLedgerRange` and reloads.

### Task 4 — Variance Print Placeholder (`variance_screen.dart`)

- Added a `picture_as_pdf_rounded` `IconButton` in the `_VarianceHeader` `Wrap`, to the left of the Refresh button.
- Tapping it shows a styled `SnackBar` (teal background, floating, rounded, 3-second duration) with a PDF icon and the message "PDF Report generation coming soon."
- `tooltip: 'Download PDF (coming soon)'` provides hover context on desktop.
- No functional wiring — placeholder only. The button is always enabled so the message is always discoverable.

### Architectural notes

**Why allTime is the default for ledger period:** New users and initial reviews are most likely to want to see the full history. Defaulting to "This Month" would hide older debts. Users can narrow as needed.

**Why the WhatsApp statement respects the active filter:** If a manager selects "Last Month" to review February's statement and then taps "Send Statement," they expect the message to reflect what's on screen — not 30 rolling days. Passing `from`/`to` makes the behavior predictable without any additional UX explanation.

**Why the print button is always enabled (not `onPressed: null`):** A disabled button is invisible to new users. An always-enabled button with a "coming soon" snackbar teaches the user that the feature exists and is planned, which is better for adoption when the real PDF engine ships.
