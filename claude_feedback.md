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
