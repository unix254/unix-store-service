# Feedback from Claude Code (Engineer)

This document is to be filled out by Claude Code and read by Gemini (Lead Architect).

---

## Milestone 1 – Foundation & Data (Completed: 2026-04-03)

### 1. uniCenta Database Analysis Findings

After mapping the MySQL schema from `MySQL-create.sql` and `MySQL-FKeys.sql`:

**Critical Finding – All PKs are VARCHAR(36) UUIDs, not integers.**
- `products.id`, `tickets.id`, `ticketlines.ticket`, `stockcurrent.product`, `stockdiary.product` – all STRING UUIDs.
- Exception: `tickets.ticketid` is an INT sequential counter (display number) but the true PK is the UUID `id`.

**Key Table Relationships:**
- `ticketlines(ticket)` → `tickets(id)` — composite PK: (`ticket`, `line`)
- `ticketlines(product)` → `products(id)` — nullable (free-text lines can have NULL product)
- `tickets(id)` → `receipts(id)` — 1:1, **the date lives in `receipts.datenew`**, NOT in `tickets`
- `stockcurrent` — composite PK: (`location`, `product`, `attributesetinstance_id`), real-time balance
- `stockdiary` — journal of every stock movement, has `reason` (INT code), `units`, `price`

**Sales Query Architecture (for Usage Variance):**
```sql
-- To get today's sales, the JOIN chain is:
ticketlines → tickets → receipts (for datenew date filter)
-- tickettype = 0 is a normal sale ticket
-- Filter: DATE(receipts.datenew) = CURDATE()
```
This is confirmed and embedded in `src/routes/pos.js` (`/api/pos/sales/today` and `/api/pos/variance/today`).

**Why we bypass stockcurrent/stockdiary:**
uniCenta's stock system is designed for retail (unit items). It has no concept of:
- Bulk ingredient quantities (kg, L)
- Yield / portion conversion
- Purpose-tagged internal movements (Sales vs Staff Meal)
- Supplier payment scheduling
The `unix_` schema is a clean parallel ledger that solves these gaps.

---

### 2. What Was Built (Milestone 1 Deliverables)

**Location:** `C:\PROJECTS\unix-store-service\`

**Node.js Backend (`unix-store-service`):**
- `src/index.js` — Express entry point, auto-runs migrations on startup
- `src/db.js` — mysql2 pool + migration runner
- `src/routes/inventory.js` — CRUD for `unix_store_inventory` + stock adjust + reorder alerts
- `src/routes/suppliers.js` — CRUD for `unix_suppliers` + running balance ledger + debt alert
- `src/routes/requisitions.js` — Requisition workflow with transactional stock deduction on issue
- `src/routes/yield.js` — CRUD for `unix_yield_config` with live JOIN to `products` table
- `src/routes/pos.js` — READ-ONLY: products, categories, today's sales, date-range sales, **Usage Variance engine**
- `migrations/001_init_unix_schema.sql` — Full `unix_` schema DDL

**Docker:**
- `Dockerfile` added to `unix-store-service/`
- `unix-store-service` service added to `unicenta-docker/docker-compose.yml` (port 5000, on `unicenta-network`)

**Key API Endpoints Available:**
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Service health check |
| GET/POST/PUT/DELETE | `/api/inventory` | Store item management |
| PATCH | `/api/inventory/:id/adjust` | Receive delivery / manual correction |
| GET | `/api/inventory/alerts/reorder` | Items at or below reorder level |
| GET/POST/PUT/DELETE | `/api/suppliers` | Supplier management |
| GET/POST | `/api/suppliers/:id/ledger` | Supplier transaction history |
| GET | `/api/suppliers/alerts/upcoming-debt` | Debt dashboard |
| GET/POST | `/api/requisitions` | Requisition management |
| PATCH | `/api/requisitions/:id/issue` | Transactional issue (deducts stock atomically) |
| GET/POST/PUT/DELETE | `/api/yield` | Yield config management |
| GET | `/api/pos/products` | Read-only POS menu products |
| GET | `/api/pos/sales/today` | Today's POS sales by product |
| GET | `/api/pos/sales/range` | Date-range POS sales |
| GET | `/api/pos/variance/today` | **Usage Variance: issued vs sold** |

---

### 3. Roadblocks / Architect Decisions Required (M1)

**None blocking for Milestone 1. All decisions resolved in M2.**

---

## Milestone 2 – Supplier Ledger & Debt Flow (Completed: 2026-04-03)

### What Was Built

**Backend additions:**
- `migrations/002_add_staff_pins.sql` — `unix_staff` table with seeded default PINs (1111/store, 9999/manager, 2222/kitchen)
- `src/routes/auth.js` — `POST /api/auth/pin` → returns `{ id, name, role }` or 401
- `src/routes/suppliers.js` — added `POST /api/suppliers/:id/order` WhatsApp/SMS order message stub
- `src/index.js` — updated with auth route + `express.static('public/web')` + SPA fallback for Flutter PWA

**Flutter PWA (`flutter_app/`):**
```
flutter_app/
├── pubspec.yaml          (flutter, http, intl, google_fonts, url_launcher)
├── web/index.html        (PWA meta tags, service worker)
├── web/manifest.json     (PWA install config)
└── lib/
    ├── main.dart
    ├── config/theme.dart         (Inter font, teal/amber brand palette)
    ├── services/api.dart         (full API client, Uri.base.resolve for PWA)
    ├── models/{staff, supplier, ledger_entry}.dart
    └── screens/
        ├── pin_login.dart        (4-dot indicator, shake on wrong PIN, role routing)
        ├── store/
        │   ├── store_shell.dart  (dark sidebar, 5 nav items, staff chip, lock)
        │   └── supplier_ledger.dart  (two-panel: supplier list + detail + ledger table + dialogs)
        └── kitchen/
            └── kitchen_home.dart  (placeholder for M3)
```

**Dockerfile** updated to multi-stage: `ghcr.io/cirruslabs/flutter:3.22.0` → `node:20-alpine`

### Default PINs (change after first deploy)
| PIN  | Name         | Role    |
|------|--------------|---------|
| 1111 | Store Keeper | store   |
| 9999 | Manager      | manager |
| 2222 | Kitchen Staff| kitchen |

### SMS/WhatsApp Order Flow
`POST /api/suppliers/:id/order` returns:
- Formatted WhatsApp message text
- `whatsapp_url` — `wa.me/` deep link that Flutter opens via `url_launcher`
- Future: integrate Africa's Talking SMS API or WhatsApp Business API

### To Build & Test Locally
```bash
cd C:\PROJECTS\unix-store-service\flutter_app
flutter pub get
flutter build web --release

cd C:\PROJECTS\unix-pos-server\unicenta-docker
docker compose up --build unix-store-service
# App available at http://localhost:5000
```

### Open Items for Milestone 3
- Cloudflare tunnel: add `store.<CLIENT_CODE>.unixpos.com → localhost:5000` to tunnel config
- Kitchen requisition workflow (the main M3 deliverable)
- Staff management UI (add/remove staff PINs from Manager role)

---

## Milestone 3 – Requisition Flow (Completed: 2026-04-03)

### What Was Built

**Backend changes:**
- `.env.example` → added `PUBLIC_URL=https://store-dev.unixpos.com`
- `docker-compose.yml` → `PUBLIC_URL` passed to `unix-store-service` container
- `src/routes/suppliers.js` → order messages now append the store's public URL (branding + reference link)
- `unix_requisitions` table was already live from Milestone 1 (no new migration needed)

**Flutter additions:**
```
lib/
├── models/
│   ├── inventory_item.dart   ← New model for kitchen item picker
│   └── requisition.dart      ← New model (purpose, status, timestamps)
├── services/api.dart         ← Extended: getInventory(), getRequisitions(),
│                                          submitRequisition(), issueRequisition(), rejectRequisition()
└── screens/
    ├── kitchen/
    │   ├── kitchen_home.dart          ← Now routes directly to KitchenRequisitionScreen
    │   └── kitchen_requisition.dart  ← MAIN M3 SCREEN (new, full implementation)
    └── store/
        ├── store_shell.dart           ← Requisitions nav now wired to approval screen
        └── requisition_approval.dart  ← MAIN M3 SCREEN (new, full implementation)
```

### Kitchen Tablet UI (`kitchen_requisition.dart`)
- Dark theme, 11-inch tablet optimised
- **Item Grid**: Wrap layout of 150×100 item cards with name + stock level; red border on low-stock items
- **Quantity Stepper**: Large 72×72 tap buttons, big display number + UOM label
- **Purpose Picker**: Two full-width 80px tap targets — `📦 FOR SALES` (teal) and `🍽️ STAFF MEAL` (amber)
- **Submit**: 72px-high, full-width button with haptic feedback
- **Right panel**: "Today's Requests" live list showing status of own submissions
- Refresh on submit, error inline display, connection error handling

### Store Desktop Approval UI (`requisition_approval.dart`)
- **30-second auto-poll** with visible countdown ring + timestamp of last refresh
- **Pending badge** in header: red count of waiting requests
- **Filter tabs**: Pending | All | Issued | Rejected with live counts
- **Per-card actions**: `Issue` button (green, triggers confirm dialog → calls transactional `PATCH /issue`) and `Reject` (red outline)
- Shows: requested by, time, purpose badge, notes, issued-by info on completed items
- Confirm dialog on Issue to prevent accidental stock deductions

### Purpose Enum Clarification
The DB enum uses `'Sales'` and `'Staff Meal'` (title case, space-separated), NOT the `SALES`/`STAFF_MEAL` format mentioned in instructions. This is correct and consistent with the existing schema from M1. The UI displays them as `📦 FOR SALES` and `🍽️ STAFF MEAL`.

### To Simulate a Requisition Handover
1. Open `http://localhost:5000` → PIN `2222` → Kitchen screen
2. Pick an inventory item → set quantity → choose purpose → Submit
3. Open another tab → PIN `1111` → Store → Requisitions
4. See the pending card → click Issue → stock deducted atomically

### Open Items for Milestone 4
- Yield Config UI (staff-configurable: 1 Whole Chicken = 8 portions)
- Usage Variance dashboard (Sales vs. Issues comparison)
- Cycle Counting flow for high-value items
- Staff management screen (manager can add/change PINs)

---

## Milestone 4 – Inventory Management & Yield Config (Completed: 2026-04-03)

### What Was Built

**Flutter additions:**
```
lib/
├── models/
│   ├── inventory_item.dart   ← Extended: added costPerUnit, supplierId, notes, toFormJson()
│   ├── pos_product.dart      ← New: POS product model with displayLabel getter
│   └── yield_config.dart     ← New: yield config model with summary getter
├── services/api.dart         ← Extended: full Yield CRUD, getPosProducts(), getReorderAlerts()
└── screens/store/
    ├── store_shell.dart       ← Wired Inventory + Yield Config nav items
    ├── inventory_screen.dart  ← MAIN M4 SCREEN: full inventory table with dialogs
    └── yield_config_screen.dart ← MAIN M4 SCREEN: yield card grid with 3-step form
```

### Inventory Screen (`inventory_screen.dart`)
- **Header**: stat chips showing total items, low-stock count, total estimated value; Add Item button
- **Filter bar**: live search TextField (name/category/UOM) + category FilterChip row
- **DataTable**: sortable rows with alternating/scaffold background colors; low-stock rows highlighted red tint with `⚠️` icon
- **Row actions**: Edit (blueGrey pencil), Adjust Stock (green add_circle), Delete (red, confirm dialog)
- **`_ItemFormDialog`**: fields for name, category, UOM (dropdown: kg, g, L, ml, pcs, dozen, bag, box, crate), qty, reorder level, cost per unit, supplier (dropdown from loaded list), notes
- **`_AdjustStockDialog`**: shows current stock, toggle between Receive Delivery (positive delta) and Manual Correction (any delta), reason field; calls `PATCH /api/inventory/:id/adjust`

### Yield Config Screen (`yield_config_screen.dart`)
- **`_ExplainerBanner`**: collapsible teal banner explaining the variance logic (1 store unit → N POS portions) and warning about POS product UUID requirement
- **`_ConfigGrid`**: `Wrap` of 320px `_ConfigCard` cards (responsive layout)
- **`_ConfigCard`**: store item pill → arrow → POS product pill, `summary` sentence, edit + delete action buttons
- **`_YieldFormDialog`**: 3-step layout:
  1. Store inventory item dropdown
  2. POS product dropdown (from live `GET /api/pos/products` data) or manual UUID text field if POS fetch fails
  3. Portions per unit number field
  - Live `_PreviewBox` showing `"1 kg Whole Chicken → 8 × Chicken Portion"` as the user fills the form
- **Error handling**: `catchError` on POS product fetch shows inline warning and falls back to manual UUID input

### Navigation Wiring (`store_shell.dart`)
Added imports and `switch` cases for `_NavItem.inventory → InventoryScreen()` and `_NavItem.yield_ → YieldConfigScreen()`. The `_ComingSoon` placeholder now only activates for the `variance` nav item.

### Models (new in M4)
- **`PosProduct`**: `id`, `name`, `categoryName`, `pricesell`; `displayLabel` = `"$name  ·  $categoryName"`
- **`YieldConfig`**: `id`, `inventoryItemId`, `inventoryItemName`, `unitOfMeasure`, `unicentaProductId`, `posProductName`, `portionsPerUnit`, `notes`; `summary` getter produces `"1 kg Whole Chicken → 8 × Chicken Portion"`
- **`InventoryItem`** (extended): added `costPerUnit`, `supplierId`, `notes`, `toFormJson()` method

### End-to-End Test Instructions
1. Deploy: `docker compose up --build unix-store-service`
2. Login PIN `1111` → Store Keeper
3. Navigate to **Inventory** — add a "Whole Chicken" item (kg, reorder level 10, cost 350)
4. Adjust stock — receive 50 units; confirm row turns green (no longer low stock)
5. Navigate to **Yield Config** — add a config linking "Whole Chicken" → POS product "Chicken Portion" → 8 portions per unit
6. On Kitchen tablet (PIN `2222`) → request 5 kg "Whole Chicken" for Sales
7. On Store screen → approve the requisition
8. Variance dashboard (next milestone) will show expected 40 portions sold vs actual POS sales

### Open Items for Milestone 5
- **Usage Variance dashboard** — wire `GET /api/pos/variance/today` to a Flutter UI (table + highlight overuse/underuse)
- **Cycle Count flow** — manager-triggered count session, item-by-item confirmation, auto-correction
- **Staff Management screen** — manager can add/edit/deactivate staff PINs
- **Cloudflare Tunnel guide** — per-client subdomain setup (`store.<CLIENT>.unixpos.com`)

---

## Milestone 5 – Variance, Cycle Counts & Final Polish (Completed: 2026-04-04)

### What Was Built

**Backend additions (`src/routes/auth.js`):**
- `POST /api/auth/staff` — create staff (validates 4-digit PIN uniqueness, role enum)
- `PUT /api/auth/staff/:id` — update name, role; optionally update PIN (conflict-checked)
- `PATCH /api/auth/staff/:id/toggle` — flip active/inactive (soft deactivate)
- `DELETE /api/auth/staff/:id` — hard delete (permanent, UI warns to prefer deactivate)

**New Flutter model:**
- `staff_member.dart` — `StaffMember` with `id`, `name`, `role`, `active`, `createdAt`; `roleLabel` getter; distinct from `Staff` (the session object) which has no `active` field

**`api.dart` additions:**
- `getAllStaff()`, `createStaff()`, `updateStaff()`, `toggleStaffActive()`, `deleteStaff()`

**New Flutter screens:**
```
lib/screens/store/
├── variance_screen.dart        ← Usage Variance Dashboard (M5)
├── staff_management_screen.dart ← Staff PIN CRUD, Manager-only (M5)
└── cycle_count_screen.dart     ← Cycle Count 3-phase flow, Manager-only (M5)
```

---

### Variance Dashboard (`variance_screen.dart`)
- Auto-refreshes every 60 seconds via `Timer.periodic`; manual refresh button + last-refreshed timestamp
- **Summary bar**: stat chips for Total Tracked, Over-Issued (red), Under-Issued (green), On Track
- **Legend**: inline coloured dot key in header
- **Table**: POS Product | Store Item | Expected Issues | Actual Issues | Variance | UOM
  - Red background tint + red `↑ +X.X` text for over-issued rows (loss risk)
  - Green tint + green `↓ -X.X` text for under-issued rows (saved/carry-over)
  - Neutral white/grey alternating rows for on-track items
- **Explainer banner**: collapsible blue info box explaining the variance formula
- **Empty state**: guides user to add Yield Config if no items are tracked
- **Error state**: inline error + Retry button

### Staff Management Screen (`staff_management_screen.dart`)
- Lists all staff sorted manager → store → kitchen, then alphabetically
- **`_StaffCard`**: avatar (initial letter), role colour badge, PIN mask (`••••`), active/inactive chip
- Role colour palette: manager = purple, store = teal, kitchen = amber
- **Deactivate** (orange icon): soft disable with confirmation dialog; shows INACTIVE badge
- **Reactivate** (green icon): re-enables the account
- **Edit** (pencil icon): opens prefilled `_StaffFormDialog`
- **Delete** (red icon): hard delete with warning to prefer deactivation
- **`_StaffFormDialog`**: name field, 3-chip role selector, PIN + confirm PIN fields with show/hide toggle; validates PIN uniqueness conflict via 409 from API
- Manager-only: only visible in sidebar when `staff.isManager`

### Cycle Count Flow (`cycle_count_screen.dart`)
3-phase full-page overlay (pushed via `Navigator.push` from Inventory tab):

**Phase 1 – Count Items:**
- Instructions banner (yellow, collapsible)
- Table: Item | UOM | System Qty | Counted Qty (text field)
- Blank = skip item; validates non-negative numbers
- `FilteringTextInputFormatter` for decimal-only input
- Low-stock items highlighted with red `⚠` icon

**Phase 2 – Review Discrepancies:**
- Lists only items where counted ≠ system (threshold 0.0001 for floating point safety)
- Table shows: Item | UOM | System Qty | Counted Qty | Adjustment (±delta in red/green)
- "No discrepancies" happy path shows a success icon + allows finishing with zero adjustments
- Confirm button shows count: `"Confirm & Apply 3 Adjustments"`

**Phase 3 – Done:**
- Success icon, summary sentence, "Return to Inventory" button
- On return, `InventoryScreen._loadData()` fires automatically (Navigator.pop returns `true`)

**Phase stepper**: appBar shows `1. Count Items → 2. Review Discrepancies → 3. Done` with colour-coded active/past/future states

### StoreShell Updates (`store_shell.dart`)
- Added `_NavItem.variance` and `_NavItem.staff` to enum
- `_navItems` changed from `static const` to a computed getter that conditionally appends the Staff nav tile only when `widget.staff.isManager`
- All 6 nav cases now have explicit `_body()` handlers — `_ComingSoon` widget is fully retired (kept as dead code, doesn't affect compilation)
- `InventoryScreen` now receives `staff: widget.staff` (required param added in M5)

### End-to-End Test Instructions
1. `docker compose up --build unix-store-service`
2. **Variance**: Login PIN `9999` (Manager) → Variance tab → add Yield Configs → see today's issued-vs-sold comparison
3. **Cycle Count**: Inventory tab → "Start Cycle Count" (manager only) → fill in counted quantities → review discrepancies → confirm → stock auto-adjusted
4. **Staff Management**: Staff tab (manager only) → Add a new staff member → set PIN `5678`, role Kitchen → login with PIN `5678` to verify
5. **Deactivate**: Staff tab → deactivate the new staff → try PIN `5678` → should get 401

### Architecture Notes
- `Staff` model (session object, no `active`) vs `StaffMember` model (admin view, has `active`) — intentionally separate to keep session objects minimal
- PIN uniqueness enforced at DB level via route-level `SELECT` check before `INSERT`/`UPDATE` (returns `409 Conflict`)
- Cycle count adjustments use existing `PATCH /api/inventory/:id/adjust` with `reason: "Cycle Count"` — no new backend endpoint needed
- Manager-only UI gating is client-side (role check on `Staff.isManager`) — for MVP this is sufficient; production would add server-side role middleware

### MVP Complete — All 5 Pain Points Addressed
| Pain Point | Feature | Status |
|---|---|---|
| Blind Store | Inventory Management (M4) | ✅ |
| Supplier Debt | Supplier Ledger + Debt Alerts (M2) | ✅ |
| Logistics/Lead Time | Reorder Alerts + Supplier Order WhatsApp (M2/M4) | ✅ |
| Cycle Counting | Cycle Count 3-phase flow (M5) | ✅ |
| Loss Prevention | Usage Variance Dashboard (M5) | ✅ |

### Remaining Pre-Launch Tasks (for Architect/Gemini)
- **Cloudflare Tunnel config** — per-client `store.<CLIENT>.unixpos.com → localhost:5000`
- **Default PIN change** — update seeds 1111/9999/2222 to real values before first deploy
- **Server-side role middleware** — `requireRole('manager')` middleware on staff/admin routes for production hardening
- **Africa's Talking or WhatsApp Business API** — replace WhatsApp URL stub with real outbound messaging

---

## Milestone 6 – Phase 2 Polish (Completed: 2026-04-05)

### What Was Built

**Database migration (`migrations/003_milestone6.sql`):**
- `unix_staff`: Added `capabilities JSON NULL`, `location_name VARCHAR(100) NULL`; seeded default capability arrays per role
- `unix_requisitions`: Added `requester_location VARCHAR(100) NULL`
- `unix_store_inventory`: Added `lead_time_days INT NULL`
- New table `unix_cost_history` — tracks old/new cost per item on every delivery receive; enables inflation heatmap
- New table `unix_pay_runs` — status ENUM (Draft/Submitted/Approved/Disbursed), approval token, totals, creator
- New table `unix_pay_run_details` — per-supplier line items with requested vs approved amounts; status ENUM (Included/Postponed/Paid)

**Backend changes:**

*`src/routes/auth.js`*
- `POST /api/auth/pin` now returns `capabilities` (parsed from JSON), `location_name`
- `GET /api/auth/staff` returns full capabilities + location_name per staff member
- `POST` and `PUT /api/auth/staff/:id` accept `capabilities` (JSON array) and `location_name`

*`src/routes/inventory.js`*
- `GET /draft-po` — auto-draft PO: triggers when `quantity_in_stock ≤ reorder_level + (daily_avg_30d × lead_time_days)`; `daily_avg = SUM(issued in last 30 days) / 30`; returns suggested order qty per supplier
- `GET /cost-history/:id` — last 50 cost changes for an item
- `GET /inflation-summary` — all recent cost changes with `weekly_impact_kes = (new_cost - old_cost) × weekly_usage`
- `POST /waste` — immediately creates an `Issued` requisition with `purpose='Wastage'` + deducts stock atomically; no approval needed
- `PATCH /:id/adjust` updated: if `new_cost_per_unit` differs from current cost, logs a record to `unix_cost_history`
- `POST /` and `PUT /:id` now accept `lead_time_days`

*`src/routes/pay_runs.js`* (new file)
- `GET /today` — auto-creates a Draft run for today if none exists
- `POST /:id/auto-populate` — fetches all suppliers with positive balance, adds as Included details
- `PATCH /:id/disburse` — posts PAYMENT ledger entries for each Included supplier, zeroing debts; returns WhatsApp-ready summary
- `GET /:id/whatsapp` — generates a `wa.me` deep-link message with payment breakdown + app URL
- `helper recalcTotals()` — keeps `total_requested` / `total_approved` in sync on every detail change

*`src/routes/pos.js`*
- **CRITICAL AGGREGATION FIX:** Variance query now `GROUP BY i.id` (inventory item). Previously one row per `unix_yield_config` mapping — if "Goat Meat" mapped to both "Samosa" and "Stew", `actual_issued` was duplicated for each row. Now uses `SUM(COALESCE(sales.total_sold, 0) / yc.portions_per_unit)` to aggregate expected consumption across all mapped POS products. `GROUP_CONCAT(p.name)` used for the `pos_product_name` display column.
- Waste exclusion already in place: `actual_issued = Sales qty − Wastage qty`

*`src/index.js`*
- Registered `pay_runs` router at `/api/pay-runs`

**Flutter models:**

*`models/staff.dart`*
- Added `capabilities: List<String>`, `locationName: String?`
- `hasCapability(String cap)` method — checks capabilities list; falls back to `isManager` for backward compatibility
- Fine-grained capability getters: `canApproveRequisitions`, `canManageInventory`, `canDraftPO`, `canApprovePayRun`, `canLogWaste`, `canManageStaff`, `canViewVariance`

*`models/staff_member.dart`*
- Added `capabilities: List<String>`, `locationName: String?`, `hasCapability()`
- `kAllCapabilities` const list of `(key, label)` tuples for UI checkbox rendering
- `defaultCapabilities(String role)` function seeds sensible defaults per role on creation

*`services/api.dart`*
- Added: `getDraftPO()`, `logWaste()`, `getInflationSummary()`, `getCostHistory()`
- Added full Pay Run API: `getPayRuns()`, `getTodayPayRun()`, `getPayRun()`, `autoPopulatePayRun()`, `addPayRunDetail()`, `updatePayRunDetail()`, `removePayRunDetail()`, `submitPayRun()`, `approvePayRun()`, `disbursePayRun()`, `getPayRunWhatsApp()`

**New Flutter screens:**

*`screens/store/pay_runs_screen.dart`*
- Two-panel layout: dark sidebar listing all runs with status colour coding + `_RunDetailPanel`
- Status-gated actions: Draft → auto-populate + submit (opens WhatsApp); Submitted → re-send or approve (manager only via `staff.canApprovePayRun`); Approved → disburse (with irreversible-action confirm dialog); Disbursed → read-only chip
- `_SupplierTable`: Requested / Approved columns, edit amount dialog, postpone/re-include toggle, remove row

*`screens/store/purchase_orders_screen.dart`*
- Header with item count, Recalculate button, and "Send Orders (N items)" bulk button
- Purple formula explainer banner: `Stock ≤ Reorder Level + (Daily Use × Lead Time Days)`
- `_PoTable`: per-row checkboxes + select-all; columns: Item / Supplier / UOM / In Stock / Min Level / Daily Use / Lead Days / Order Qty (teal badge)
- Footer per-supplier WhatsApp send buttons (green `#25D366`)

**Updated Flutter screens:**

*`screens/store/store_shell.dart`*
- Enum extended: added `payRuns`, `purchaseOrders`
- Purchase Orders added to core nav (all store/manager roles)
- Pay Runs added to manager-only nav (alongside Staff)
- `_body()` wired for all 8 nav items

*`screens/store/supplier_ledger.dart`*
- `_SupplierList` converted from `StatelessWidget` → `StatefulWidget` with `_search` state
- Search TextField (with clear button) filters by supplier name and location in real time

*`screens/store/yield_config_screen.dart`*
- POS product `DropdownButtonFormField` replaced with `Autocomplete<PosProduct>` with custom dropdown list view (max 220px height, instant filter by name)
- Handles large POS product lists that previously caused scroll-lag in dropdown

*`screens/store/variance_screen.dart`*
- Added `_inflation` state + `getInflationSummary()` parallel fetch in `_load()`
- Added `_InflationHeatmap` widget below summary bar: amber banner with colour-coded item chips showing `±%` price change and tooltip with KES weekly impact amount
- Column header updated from "POS Product" → "POS Product(s)" to reflect aggregated display

*`screens/kitchen/kitchen_requisition.dart`*
- Added `_logWaste()` method: shows dark-themed waste dialog (qty + notes + ⚠️ warning), calls `ApiService.instance.logWaste()`, reloads on success
- `_Header` updated: red-outlined "Log Waste" button with `Icons.delete_rounded`
- `_Body` + `_RequestForm` updated: `search`/`onSearch` params added; search `TextField` (with clear button) appears above the item grid; items filtered in real time
- `_RequestForm.filteredItems` computed from search string before passing to `_ItemGrid`

*`screens/store/staff_management_screen.dart`*
- `_StaffCard` shows: location badge (blueGrey, location icon), capabilities count badge (teal, tooltip listing all labels)
- `_StaffFormDialogState`: location dropdown from `_kLocations` list, collapsible capabilities `CheckboxListTile` section seeded by `defaultCapabilities()` on role change
- `_submit()` includes `capabilities` and `location_name` in POST/PUT body

### Architecture Decisions

**Why waste uses requisitions table, not a separate table:**
Reusing `unix_requisitions` with `purpose='Wastage'` and `status='Issued'` avoids a new table and keeps all stock movements in one auditable place. The variance formula subtracts wastage from sales issues at query time: `SUM(Sales) − SUM(Wastage)`.

**Why capabilities fall back to `isManager`:**
All new capability getters use `|| isManager` fallback so existing screens that rely on `staff.isManager` continue working without modification. M6 screens use `hasCapability()` for forward-looking role granularity.

**Why the variance aggregation fix is critical:**
Before the fix, a single inventory item mapped to N POS products produced N rows — and each row's `actual_issued` join was the full day's issued qty. For 2 POS mappings, the calculated variance was effectively doubled. The `GROUP BY i.id` + `SUM(expected)` fix resolves this cleanly.

**Pay Run WhatsApp (100% free, no API):**
Uses `url_launcher` to open a `wa.me/?text=...` deep link on the manager's device. The owner's WhatsApp opens with a pre-filled approval summary. No third-party WhatsApp API or cost involved.

### New API Endpoints Summary (M6)
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/inventory/draft-po` | Auto-draft PO items below reorder + lead time buffer |
| POST | `/api/inventory/waste` | Log wastage (immediately issued, no approval) |
| GET | `/api/inventory/inflation-summary` | Recent cost changes with weekly KES impact |
| GET | `/api/inventory/cost-history/:id` | Per-item cost change history |
| GET | `/api/pay-runs` | List all pay runs |
| GET | `/api/pay-runs/today` | Today's run (auto-creates Draft if none) |
| GET | `/api/pay-runs/:id` | Single run with details |
| POST | `/api/pay-runs/:id/auto-populate` | Add all positive-balance suppliers to run |
| POST | `/api/pay-runs/:id/details` | Add a detail row manually |
| PUT | `/api/pay-runs/:id/details/:detailId` | Edit amount / status |
| DELETE | `/api/pay-runs/:id/details/:detailId` | Remove detail row |
| PATCH | `/api/pay-runs/:id/submit` | Submit for owner review (opens WhatsApp) |
| PATCH | `/api/pay-runs/:id/approve` | Manager marks as Approved |
| PATCH | `/api/pay-runs/:id/disburse` | Disburse + post ledger payments |
| GET | `/api/pay-runs/:id/whatsapp` | WhatsApp deep link for owner review |

---

## Milestone 7 – Phase 3 Discipline & Debt Linking (Completed: 2026-04-05)

### What Was Built

**Database migration (`migrations/004_purchase_orders.sql`):**
- `unix_purchase_orders` — PO header with status ENUM (`DRAFT`, `PENDING_APPROVAL`, `APPROVED`, `SENT`), maker/checker fields (`created_by`, `approved_by`, `approved_at`), notes
- `unix_po_details` — line items with `suggested_qty` and `approved_qty` columns; CASCADE-delete FK to header

**New backend (`src/routes/purchase_orders.js`):**
- `GET /api/purchase-orders` — list all POs with `item_count` subquery
- `GET /api/purchase-orders/:id` — single PO with full detail rows joined to inventory + suppliers
- `POST /api/purchase-orders/auto-draft` — runs reorder math, saves DRAFT header + detail rows (empty draft if nothing below threshold)
- `POST /api/purchase-orders/:id/details` — manual line addition
- `PUT /api/purchase-orders/:id/details/:detailId` — edit approved_qty or supplier
- `DELETE /api/purchase-orders/:id/details/:detailId` — remove line
- `PATCH /api/purchase-orders/:id/submit` — DRAFT → PENDING_APPROVAL (400 if wrong status)
- `PATCH /api/purchase-orders/:id/approve` — PENDING_APPROVAL → APPROVED, stamps `approved_by` + `approved_at`
- Registered in `src/index.js` at `/api/purchase-orders`

**Updated backend (`src/routes/inventory.js`):**
- `PATCH /api/inventory/:id/adjust` now accepts `supplier_id` + `total_cost`
- When a positive delivery is tagged with a supplier + invoice cost, automatically INSERTs a `PURCHASE` entry into `unix_supplier_ledger` within the same request — zero-friction debt linking on stock receive

**Flutter `services/api.dart`:**
- `adjustStock()` updated: new optional params `supplierId`, `totalCost`, `changedBy`, `newCostPerUnit` (previously only `reason`)
- New PO methods: `getPurchaseOrders()`, `getPurchaseOrder()`, `autoDraftPO()`, `addPoDetail()`, `updatePoDetail()`, `removePoDetail()`, `submitPO()`, `approvePO()`

**`screens/store/purchase_orders_screen.dart` — Complete Rewrite (Maker-Checker):**
- Master-detail `LayoutBuilder` layout matching pay_runs_screen pattern (stacks on mobile < 800px)
- `_PoListPanel` (260px dark sidebar): lists all POs with status colour badges; "New Auto-Draft PO" button at top
- `_PoDetailPanel`: header with PO date, status badge, action buttons gated by status:
  - DRAFT: Add Item + Submit for Approval (WhatsApp buttons hidden)
  - PENDING_APPROVAL: Approve PO (manager/capability gated) OR "Awaiting Manager Approval" chip
  - APPROVED/SENT: "Approved ✓" chip + per-supplier WhatsApp send buttons in footer
- `_PoTable`: Item | Supplier | UOM | In Stock | Suggested Qty | Approved Qty (teal badge + inline edit pencil in Draft mode) | Remove (Draft mode only)
- `_AddItemDialog`: searchable inventory item picker + qty field; returned as `{ inventory_item_id, supplier_id, suggested_qty, approved_qty }`
- `_EmptyDetail`: call-to-action when no PO selected

**`screens/store/supplier_ledger.dart`:**
- `_SupplierFormDialog`: replaced payment day free-text `TextEditingController` + `TextFormField` with a structured `DropdownButtonFormField<String?>` using `_kPaymentDays = ['Monday'…'Sunday', 'Daily']`
- Existing values that match the enum are pre-selected; unrecognised legacy values gracefully treated as "Not scheduled"

**`screens/store/pay_runs_screen.dart`:**
- `_RunDetailPanel`: "To Pay" section now groups included suppliers by their `payment_day` value
- `_buildDayGroups()` top-level helper: sorts groups in Mon→Sun→Daily→Unscheduled order; each group has a blue day-badge header showing day name, count, and KES sub-total; an "Unscheduled" group collects suppliers with no payment day set
- `payment_day` comes from the existing `unix_suppliers` join in `GET /api/pay-runs/:id`

**`screens/store/inventory_screen.dart`:**
- `_AdjustStockDialog` now accepts `List<Supplier> suppliers` parameter
- In Receive Delivery mode, two additional required fields appear:
  1. **Supplier dropdown** — pre-selected with item's default supplier; "No supplier / cash purchase" option suppresses debt posting
  2. **Total Invoice Cost (KES)** — validated as a positive number
- A green confirmation banner appears when a supplier is selected: "Invoice cost will be added to the supplier's debt automatically."
- Invoice cost validation prevents accidental submission without a cost value in delivery mode
- `_showAdjustDialog()` now passes `suppliers: _suppliers` to the dialog

### Architecture Decisions

**Why WhatsApp buttons are locked until APPROVED:**
Enforces the maker-checker discipline — the Storekeeper proposes the order (DRAFT), the Manager approves quantities and suppliers (APPROVED), and only then can the Storekeeper dispatch via WhatsApp. Prevents unauthorised or unreviewed orders going out to suppliers.

**Why delivery cost is required (not optional):**
Making it required closes a common gap: deliveries received without logging the invoice cost create invisible debt. The validation nudge ensures every delivery is financially tracked. Cash purchases can still bypass debt linking by selecting "No supplier".

**Why payment_day grouping helps the owner:**
Kenyan restaurant suppliers often operate on fixed weekly payment days (e.g. butcher on Monday, veg supplier on Friday). Grouping by day lets the owner pre-approve 2–3 days' worth of payments at once rather than having to approve the same run multiple times.

### New API Endpoints Summary (M7)
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/purchase-orders` | List all POs with item count |
| GET | `/api/purchase-orders/:id` | Single PO with full detail rows |
| POST | `/api/purchase-orders/auto-draft` | Create DRAFT from reorder math |
| POST | `/api/purchase-orders/:id/details` | Add manual line |
| PUT | `/api/purchase-orders/:id/details/:detailId` | Edit line qty/supplier |
| DELETE | `/api/purchase-orders/:id/details/:detailId` | Remove line |
| PATCH | `/api/purchase-orders/:id/submit` | DRAFT → PENDING_APPROVAL |
| PATCH | `/api/purchase-orders/:id/approve` | PENDING_APPROVAL → APPROVED |

---

## Milestone 8 – Phase 6: Manager Ledger Optimization & Supplier Statements (Completed: 2026-04-12)

### What Was Built

**Database migration (`migrations/009_supplier_payment.sql`):**
- Added `SUPPLIER_PAYMENT` to the `transaction_type` ENUM on `unix_supplier_ledger` (previously only `PURCHASE` / `PAYMENT`)
- Added `related_supplier_id VARCHAR(36)` nullable column to `unix_supplier_ledger` — allows a payment row to reference which external supplier the manager cash was ultimately paid to
- Added index on `related_supplier_id`

**Updated backend (`src/routes/suppliers.js`):**
- All five balance queries (supplier list, debt alerts, auto-populate, statement opening balance, WhatsApp statement opening balance) updated to treat `SUPPLIER_PAYMENT` as a **debit** alongside `PURCHASE` (i.e. money going out of the manager's float)
- Manual ledger POST now accepts `SUPPLIER_PAYMENT` type with optional `related_supplier_id`
- `GET /api/suppliers/:id/statement` — returns a dated period statement with:
  - `opening_balance`, `period_purchases`, `period_payments`, `closing_balance`
  - Includes `period_supplier_payments` for internal managers
- `GET /api/suppliers/:id/statement/whatsapp` — returns WhatsApp deep-link URL with a formatted statement body
  - Regular external suppliers: standard debt statement (invoices vs payments)
  - **Internal manager accounts**: "Manager Float Statement" format with emoji breakdown — 💰 Cash Received from Bank, 🧾 Used to Pay Suppliers, 🛒 Ad-Hoc Expenses, ↩️ Payments Reimbursed, Running Float Balance

**Flutter `models/ledger_entry.dart`:**
- Added `isSupplierPayment` getter
- `isDebit` now covers both `PURCHASE` and `SUPPLIER_PAYMENT`
- `_TypeBadge` widget: new amber/orange badge for `SUPPLIER_PAYMENT` with `Icons.swap_horiz_rounded`
- Amount column: `SUPPLIER_PAYMENT` rendered in the same debit colour as `PURCHASE`

**Flutter `screens/store/supplier_ledger.dart`:**
- Supplier list now shows an "Internal" chip on rows where `supplier.isInternal == true`
- Detail view for internal suppliers shows a blue **"Record Cash-In"** button (`Icons.account_balance_rounded`)
- Detail view for internal suppliers shows an amber **"Record Supplier Payment"** button (`Icons.swap_horiz_rounded`)
- `_AddEntryDialog`: extended to handle `SUPPLIER_PAYMENT` — shows a second dropdown of external suppliers for `related_supplier_id` linkage
- Statement button opens bottom sheet with period selector, displays closing balance, opens WhatsApp on tap

### Architecture Decisions

**Why `SUPPLIER_PAYMENT` is a debit on the manager ledger:**
The manager is modelled as an internal supplier who receives the float. When they pay an external supplier from that float, it is a debit against their balance — money leaving the float. This mirrors double-entry exactly: the external supplier ledger gains a `PAYMENT` credit at the same moment.

**Why the `related_supplier_id` column:**
Provides full auditability — the owner can see not just that the manager spent KES 5,000 from the float, but specifically that it went to Nairobi Meats Ltd. This also enables future reconciliation reports that compare the manager's SUPPLIER_PAYMENT totals against the external supplier's PAYMENT credits.

**Why the WhatsApp statement format differs by supplier type:**
External suppliers need an accounts-receivable statement (how much do we owe them). Managers need a float accountability statement (how much cash they received and where it went). The same endpoint auto-detects `supplier.is_internal` and switches the template.

### New API Endpoints Summary (M8 / Phase 6)
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/suppliers/:id/statement` | Period statement (opening/closing balance + breakdown) |
| GET | `/api/suppliers/:id/statement/whatsapp` | WhatsApp deep-link with formatted statement body |

---

## Milestone 9 – Phase 7: Pay Run Autonomy & Manager Cash-In (Completed: 2026-04-13)

### What Was Built

**Database migration (`migrations/010_cash_in.sql`):**
- Expanded `transaction_type` ENUM on `unix_supplier_ledger` to include `CASH_IN`:
  ```sql
  ALTER TABLE unix_supplier_ledger
    MODIFY COLUMN transaction_type
      ENUM('PURCHASE', 'PAYMENT', 'SUPPLIER_PAYMENT', 'CASH_IN') NOT NULL;
  ```
- `CASH_IN` represents the owner depositing cash into the manager's float (bank transfer / cheque)

**Updated backend (`src/routes/pay_runs.js`):**
- `PATCH /api/pay-runs/:id/finalize` — new endpoint; transitions a `Draft` pay run directly to `Approved`, bypassing the Submit → WhatsApp → Approve three-step sequence. Returns 400 if the run is not currently in Draft status.
- `POST /api/pay-runs/:id/auto-populate` balance query fix: now credits **both** `PAYMENT` and `CASH_IN` transactions (previously only credited `PAYMENT`), ensuring the "amount to pay" is correctly calculated after a cash-in event.

**Updated backend (`src/routes/suppliers.js`):**
- All five balance queries updated: `CASH_IN` now treated as a **credit** (alongside `PAYMENT`) across the entire system — supplier list balances, debt alerts, auto-populate, statement opening balance, WhatsApp statement opening balance.
- Manual ledger POST now accepts `CASH_IN` type
- Statement endpoint: tracks `period_cash_ins` separately; includes in `closing_balance`; returns `period_cash_ins` field to Flutter
- WhatsApp Manager Float Statement updated to show the `CASH_IN` line as "💰 Cash Received from Bank" with its correct total

**Flutter `services/api.dart`:**
- `finalizePayRun(String id)` → `PATCH /api/pay-runs/$id/finalize`
- `recordCashIn(supplierId, {required amount, required transactionDate, description, referenceDoc})` — calls `addLedgerEntry` with type `CASH_IN`

**Flutter `screens/store/store_shell.dart`:**
- Pay Runs nav item now restricted to `s.isManager || s.isOwner` (was previously gated on `s.canApprovePayRun` capability which was broader); aligns Pay Runs as a management-level screen only

**Flutter `screens/store/pay_runs_screen.dart` (major revision):**
- Removed the three-step workflow methods: `_submit()`, `_sendWhatsApp()`, `_approve()`
- Replaced with single `_finalize()` method — shows a confirmation dialog listing suppliers to be paid, then calls `finalizePayRun()`
- `_RunDetailPanel` widget parameters simplified: removed `onSubmit`, `onSendWhatsApp`, `onApprove`; added single `onFinalize` callback
- Draft UI button changed from "Submit for Approval" to **"Finalize & Start Paying"** (`Icons.rocket_launch_rounded`)
- Legacy `Submitted` status rows (from before this phase) still render a minimal "Mark Approved" fallback button so historical data is not stranded
- Both mobile and desktop call sites updated

**Flutter `screens/store/supplier_ledger.dart`:**
- Internal supplier detail panel: blue **"Record Cash-In"** floating button (`Icons.account_balance_rounded`) visible only when `s.isInternal == true`
- `_AddEntryDialog`: extended for `CASH_IN` — deep-blue accent colour, bank icon, label changed to "Bank Ref / Cheque No.", button text "Save Cash-In"
- `_TypeBadge` widget: `CASH_IN` case added — blue colour, `Icons.account_balance_rounded` icon
- Amount column: `CASH_IN` displayed in blue (`Color(0xFF1565C0)`) to distinguish it visually from green payment credits

**Flutter `models/ledger_entry.dart`:**
- `isCashIn` getter added: `transactionType == 'CASH_IN'`
- `isDebit` remains `isPurchase || isSupplierPayment` — `CASH_IN` is a credit

### Architecture Decisions

**Why a single Finalize button replaces Submit → Approve:**
For a single-owner operation the three-step WhatsApp approval loop (Storekeeper submits → WhatsApp sent to owner → Owner approves in app) was over-engineered. The manager running pay runs is the same person with approval authority. Collapsing to one step removes friction without losing the audit trail (status field still transitions and timestamp is recorded).

**Why `CASH_IN` is a credit on the manager ledger:**
The manager receives float money from the bank. This increases their balance (they have more to spend). Crediting the account is the correct double-entry treatment — the owner "owes" the float to the manager, and a CASH_IN reduces that payable.

**Why balance queries needed updating in five places:**
MySQL ENUM comparisons are exact-match string literals. Adding a new enum value does not automatically include it in existing `= 'PAYMENT'` filters. Each query that computes a credit total had to be updated to `IN ('PAYMENT', 'CASH_IN')` to stay correct. Missing any one of them would silently under-count the manager's available float.

### New API Endpoints Summary (M9 / Phase 7)
| Method | Endpoint | Description |
|--------|----------|-------------|
| PATCH | `/api/pay-runs/:id/finalize` | Fast-track Draft → Approved in one step |

---

## Milestone 10 – Phase 8: Operations Polish, Inventory Control & Procurement Flexibility (Completed: 2026-04-14)

### What Was Built

**Database migration (`migrations/011_requisition_adjustments.sql`):**
```sql
ALTER TABLE unix_requisitions
  ADD COLUMN issued_quantity DECIMAL(10,3) NULL,
  ADD COLUMN issue_notes     VARCHAR(500)  NULL;
```
- `issued_quantity`: the actual quantity the storekeeper deducted (may differ from the requested `quantity`)
- `issue_notes`: storekeeper's note on issue (e.g. "Only 1.5 kg in stock") or rejection reason

**Updated backend (`src/routes/requisitions.js`):**
- `PATCH /:id/issue` now accepts optional `issued_quantity` (defaults to full requested `quantity` if omitted)
  - Validates: `issued_quantity > 0` and `issued_quantity <= current stock level`
  - Stock deduction uses `issued_quantity` not `quantity`
  - Stores `issued_quantity` and optional `issue_notes` on the row
  - Returns `issued_quantity` in the response JSON
- `PATCH /:id/reject` now accepts optional `reject_reason` body param; stored in `issue_notes`

**New backend (`src/routes/procurement.js`):**
- `POST /api/procurement/build-whatsapp` — accepts pre-built groups with user-adjusted quantities:
  ```json
  { "groups": [{ "purchaserId": "...", "purchaserName": "...", "purchaserPhone": "...", "items": [{ "name": "...", "unit": "...", "quantity": 2.5 }] }] }
  ```
  - Formats WhatsApp message per group using existing business-name/phone-normalisation/CRLF-encoding logic
  - Returns `{ ok: true, groups: [...originalFields, message, whatsapp_url] }`
  - Keeps all formatting server-side to avoid duplicating phone normalisation in Flutter

**Flutter `models/requisition.dart`:**
- Added `issuedQuantity` (`double?`) and `issueNotes` (`String?`) fields
- `fromJson` maps: `issued_quantity` → `issuedQuantity`, `issue_notes` → `issueNotes`

**Flutter `services/api.dart`:**
- `issueRequisition(id, issuedBy, {issuedQuantity?, issueNotes?})` — optional params forwarded to API
- `rejectRequisition(id, {reason?})` — optional reason param forwarded to API
- `buildProcurementWhatsApp(List<Map> groups)` → `POST /api/procurement/build-whatsapp`

**Flutter `screens/kitchen/kitchen_requisition.dart`:**
- Screen header title changed from hardcoded `'KITCHEN REQUESTS'` to dynamic:
  ```dart
  '${(staff.locationName?.isNotEmpty == true ? staff.locationName! : 'DEPARTMENT').toUpperCase()} REQUESTS'
  ```
  Supports any department (Kitchen, Bar, Laundry, etc.) without code changes.

**Flutter `screens/store/requisition_approval.dart` (major additions):**
- `_issue()` now opens `_IssueDialog` instead of firing immediately
  - Pre-fills quantity field with the original requested qty
  - Optional `issueNotes` text field ("Storekeeper note")
  - Form validation: quantity must be > 0
  - Passes `issuedQuantity` + `issueNotes` to `ApiService.issueRequisition()`
- `_reject()` now opens `_RejectDialog` instead of firing immediately
  - Optional free-text reason field
  - Passes reason to `ApiService.rejectRequisition()`
- `_RequisitionCard` updated:
  - Shows adjusted quantity in teal if `issuedQuantity != quantity` (e.g. "Issued: 1.5 kg of 2 kg requested")
  - Shows rejection reason from `issueNotes` when status is `Rejected`
- Two new dialog widgets: `_IssueDialog` (with `GlobalKey<FormState>` validation), `_RejectDialog`

**Flutter `screens/store/inventory_screen.dart`:**
- `_InventoryTable` gains `onLogWaste` callback parameter (`void Function(InventoryItem)`)
- Each inventory row gets an orange **"Log Waste / Write-off"** action button (`Icons.delete_sweep_rounded`)
- `_InventoryScreenState._showLogWasteDialog(item)` method opens `_LogWasteDialog`
- New `_LogWasteDialog` widget:
  - Shows current in-stock level
  - Quantity field with validation: must be > 0 and ≤ current stock
  - Optional reason/notes field
  - Calls `ApiService.instance.logWaste()` on submit
  - Refreshes inventory list on success

**Flutter `screens/store/procurement_screen.dart` (complete architectural rewrite):**
- **New data models (in-widget):**
  - `_EditableItem`: item name, unit, inStock, isAdHoc flag, `TextEditingController` for quantity
  - `_EditableGroup`: purchaserId, purchaserName, purchaserPhone, `List<_EditableItem>`; `addAdHocItem()` / `removeItem()` helpers
  - `_AdHocResult`: returned from `_AdHocItemDialog` (name, unit, quantity, targetGroup)
- **State management:**
  - `_editableGroups` replaces the previous immutable `_groups` list
  - `_generate()` converts API response into `_EditableGroup` objects with pre-seeded `TextEditingController`s
  - `dispose()` properly disposes all controllers (prevents memory leaks)
- **`_sendGroup(group)`**: reads current edited qty values, calls `buildProcurementWhatsApp`, receives back the formatted WhatsApp URL, opens via `url_launcher`
- **`_showAdHocDialog(group)`**: opens `_AdHocItemDialog`; on return, calls `group.addAdHocItem()` and `setState()`
- **`_EditableProcurementCard`** (StatefulWidget, replaces old StatelessWidget):
  - Per-item inline `TextField` bound to each `_EditableItem.qtyCtrl`
  - "Add Item" button at the bottom of each group card
  - Ad-hoc items show a teal `+` icon prefix and an `✕` remove button
  - "Send via WhatsApp" button per group card
- **`_AdHocItemDialog`**: item name field, unit dropdown (`kg/g/L/ml/pcs/dozen/bag/box/bunch`), quantity field, purchaser group selector (pre-selects the card's group)

### Architecture Decisions

**Why `issued_quantity` defaults to the full requested quantity server-side:**
The common case is full issuance. The storekeeper should only need to act when there is a discrepancy. Defaulting server-side means the existing API callers (e.g. old mobile clients without the dialog) continue to work unchanged.

**Why partial rejection reason goes into `issue_notes` (not a separate column):**
A rejected requisition has no `issued_quantity` to store — the column is NULL. Reusing `issue_notes` for the rejection reason keeps the schema lean (one nullable text column serves both purposes) and avoids an additional migration.

**Why `build-whatsapp` is a backend endpoint rather than client-side formatting:**
Phone number normalisation (07xx → 2547xx), business name lookup, and CRLF-encoded URL encoding are already implemented once in `procurement.js`. Duplicating this logic in Dart would create a maintenance burden and divergence risk. The endpoint accepts the adjusted quantities and returns ready-to-open URLs.

**Why procurement uses `TextEditingController` per item instead of a state map:**
Each item in a group is an independent editable field. Using a controller per item means Flutter's widget lifecycle manages focus, cursor position, and text state correctly. A shared state map by index is error-prone when items are added (ad-hoc) or reordered. Controllers are created alongside their data objects in `_generate()` and disposed together.

**Why the kitchen title is dynamic:**
The same `KitchenRequisitionScreen` widget is navigated to by Bar staff, Laundry staff, and Kitchen staff. Hardcoding "KITCHEN" was misleading. `staff.locationName` (already available in the auth context) drives the correct department label with zero additional API calls.

### New API Endpoints Summary (M10 / Phase 8)
| Method | Endpoint | Description |
|--------|----------|-------------|
| PATCH | `/api/requisitions/:id/issue` | Issue requisition with optional partial qty + notes |
| PATCH | `/api/requisitions/:id/reject` | Reject requisition with optional reason |
| POST | `/api/procurement/build-whatsapp` | Format procurement groups into WhatsApp deep-links |

---

## Milestone 11 – Phase 9: App Customization, Authentication Revamp & Go-Live Architecture (Completed: 2026-04-15)

### What Was Built

**Database migration (`migrations/012_feature_flags.sql`):**
```sql
CREATE TABLE IF NOT EXISTS unix_feature_flags (
  feature_key   VARCHAR(60)   NOT NULL PRIMARY KEY,
  enabled       TINYINT(1)    NOT NULL DEFAULT 1,
  label         VARCHAR(100)  NOT NULL DEFAULT '',
  description   VARCHAR(255)  NOT NULL DEFAULT '',
  updated_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
```
Seeded with 5 default flags (all enabled): `module_purchase_orders`, `module_procurement`, `module_pay_runs`, `module_variance`, `module_yield_config`. Uses `INSERT IGNORE` so re-running migrations is safe.

**New backend (`src/routes/feature_flags.js`):**
- `GET /api/feature-flags` — returns all flags as `[{ feature_key, enabled, label, description }]`
- `PUT /api/feature-flags/:key` — updates `enabled` (0 or 1) for a given key; 404 if key not found

**New backend (`src/routes/admin.js`):**
- `POST /api/admin/super-login` — validates `{ username, password }` against `SUPER_ADMIN_USERNAME` / `SUPER_ADMIN_PASSWORD` env vars; returns 503 if `SUPER_ADMIN_PASSWORD` is not set (admin disabled by default until configured); returns 401 on wrong credentials; returns `{ ok: true }` on success
- `POST /api/admin/go-live-wipe` — re-validates credentials on every call (no cached token); runs `SET FOREIGN_KEY_CHECKS = 0`, deletes from: `unix_po_details`, `unix_purchase_orders`, `unix_pay_run_details`, `unix_pay_runs`, `unix_supplier_ledger`, `unix_requisitions`; restores FK checks; logs to console; returns `{ ok, message, tablesCleared }`. Core uniCenta tables (`receipts`, `tickets`, `stockdiary`, `products`, etc.) are never referenced or touched.

**Updated `src/index.js`:**
- Registered `featureFlagsRouter` at `/api/feature-flags`
- Registered `adminRouter` at `/api/admin`

**Updated `.env.example`:**
- Added `SUPER_ADMIN_USERNAME` (default: `yunix_admin`) and `SUPER_ADMIN_PASSWORD` (no default — must be set explicitly to enable admin)

**New Flutter model (`flutter_app/lib/models/feature_flag.dart`):**
- `FeatureFlag` class: `featureKey`, `enabled` (mutable for optimistic UI toggle), `label`, `description`
- `fromJson` maps `enabled` from `int` (MySQL TINYINT) to `bool`

**Updated Flutter `services/api.dart`:**
- `getFeatureFlags()` → `GET /api/feature-flags` → `List<FeatureFlag>`
- `updateFeatureFlag(key, enabled)` → `PUT /api/feature-flags/$key`
- `superAdminLogin(username, password)` → `POST /api/admin/super-login` (throws `ApiException` on failure)
- `goLiveWipe(username, password)` → `POST /api/admin/go-live-wipe` → `Map<String, dynamic>`

**Rewritten `flutter_app/lib/screens/pin_login.dart` — Name Grid Login:**
- `initState()` now calls both `_loadBranding()` AND `_loadStaff()` in parallel
- Loading state → CircularProgressIndicator; error state → "Retry" button; empty state → guidance message
- Main view: `_StaffGrid` widget — `GridView.builder` with `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 160)`
- Each staff card: `CircleAvatar` with initial letter + role colour, name text, role label pill
  - Role colours: Owner = amber, Manager = cyan, Store = green, Kitchen = slate
- Tapping a card calls `_onSelectStaff()` → opens `_PinEntrySheet` as a `showModalBottomSheet` with `enableDrag: false`
- `_PinEntrySheet` (StatefulWidget): has its own `AnimationController` for shake, shows selected staff name, PIN dots, error message, and `_Numpad`; closes sheet on successful auth then calls `_navigate(staff)`
- The old direct-PIN-entry flow (no staff selection) is fully replaced

**Super Admin backdoor on login screen:**
- Logo (`GestureDetector`) counts rapid taps; 5 taps within 2 seconds triggers `_showSuperAdminModal()`
- `_tapTimer` resets the counter after 2 seconds of inactivity
- `_SuperAdminLoginSheet` (bottom sheet): username `TextField` + password `TextField` (with show/hide toggle), calls `superAdminLogin()`; on success navigates to `SuperAdminDashboard`; orange accent colour (`Color(0xFFFF6B35)`) to distinguish from staff login visually

**New `flutter_app/lib/screens/super_admin/super_admin_dashboard.dart`:**
- Standalone `Scaffold` (not inside `StoreShell`); dark navy theme (`Color(0xFF0D1B2A)`)
- `AppBar` with orange admin icon, "Exit to Login" back button navigates to `PinLoginScreen`
- `DefaultTabController` with 2 tabs:
  1. **Feature Flags tab** (`_FeatureFlagsTab`): loads flags via API; `SwitchListTile` per flag with optimistic toggle; reverts on API failure with a snack bar error
  2. **Go-Live Reset tab** (`_GoLiveTab`): warning card (KEPT vs WIPED tables), uniCenta protection notice, red "Clear Transactions & Go Live" button
- Go-Live wipe uses a **two-step confirmation**:
  1. Info dialog listing what gets wiped → "Continue" or "Cancel"
  2. Type-to-confirm dialog: user must type `GO LIVE` (case-sensitive) before the button activates
  3. Loading overlay while wipe runs
  4. Success dialog showing the server's confirmation message
- Admin credentials are passed from the login sheet to the dashboard widget and re-sent on every wipe call — no in-memory token storage

**Updated `flutter_app/lib/screens/store/store_shell.dart`:**
- Added `import '../../services/api.dart'`
- Added `Map<String, bool> _flags = {}` state
- `initState()` calls `_loadFeatureFlags()` immediately after selecting the default nav item
- `_loadFeatureFlags()` fetches from API, builds a `{ featureKey: enabled }` map via collection-for, then re-evaluates `_selected` in case the active screen was just disabled
- `_flag(key)` helper returns `_flags[key] ?? true` (defaults to enabled if not yet loaded — prevents nav flicker)
- `_navItems` now wraps flagged modules in `if (_flag('module_xxx'))` guards:
  - `module_yield_config` gates Yield Config
  - `module_purchase_orders` gates Purchase Orders
  - `module_procurement` gates Procurement
  - `module_variance` gates Variance
  - `module_pay_runs` gates Pay Runs
  - Suppliers and Inventory are **never** flag-gated (always visible if user has `canManageInventory`)
  - Requisitions and Settings are **never** flag-gated (always visible if user has the capability)

### Architecture Decisions

**Why feature flags default to `true` in the Flutter client before the API responds:**
The flags load asynchronously after login. Defaulting to `true` means the user sees their full nav immediately and any disabled modules disappear once the API responds (~100ms on LAN). The alternative (hiding all flagged modules until loaded) causes a jarring visual flash. The risk of a user briefly seeing a disabled module and tapping it before flags load is low and acceptable — the screen itself still renders safely.

**Why the Super Admin wipe re-validates credentials on every call instead of using a session token:**
Destructive actions should not be replayable with a stale token. Re-validating on the wipe endpoint means that even if someone finds the `goLiveWipe` API call in network logs and replays it, it requires the full credentials. It also keeps the system stateless — no token table needed.

**Why the type-to-confirm pattern (type "GO LIVE") for the wipe:**
A single OK/Cancel dialog can be accidentally accepted. Requiring the user to type a specific phrase proves intentionality and makes accidental wipes virtually impossible, even for super admins under pressure. This pattern is used by Heroku, Vercel, and GitHub for destructive actions.

**Why `unix_store_inventory` and `unix_suppliers` are NOT wiped:**
These are master data tables populated during onboarding (inventory setup, supplier onboarding). Wiping them on go-live would require the client to re-enter all their items and suppliers. Only *transactional* data (ledger entries, pay runs, requisitions, POs) represents the "practice run" that needs to be cleared.

**Why `SET FOREIGN_KEY_CHECKS = 0` instead of delete ordering:**
While the code does delete in the correct child-first order (`unix_po_details` before `unix_purchase_orders`, etc.), disabling FK checks provides a safety net: if a future migration adds a new child table and the wipe table list is not updated simultaneously, the FK check would cause a partial wipe failure leaving the DB in an inconsistent state. Disabling FK checks during the batch delete (within a no-transaction block) prevents this class of failure. No `conn.beginTransaction()` is used because `TRUNCATE`/`DELETE` with `FOREIGN_KEY_CHECKS=0` is idempotent and re-runnable.

### New API Endpoints Summary (M11 / Phase 9)
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/feature-flags` | List all feature flags with enabled status, label, description |
| PUT | `/api/feature-flags/:key` | Enable or disable a specific feature flag |
| POST | `/api/admin/super-login` | Validate super admin credentials (env-configured) |
| POST | `/api/admin/go-live-wipe` | Wipe transactional unix_ tables (credentials re-verified) |

---

## Milestone 12 – Phase 10: Roles, Capabilities & Expense Accounts (Completed: 2026-04-16)

### What Was Built

**Backend (`src/routes/auth.js`):**
- Added `ict_admin` to the valid roles enum in both `POST /api/auth/staff` and `PUT /api/auth/staff/:id` validators (previously only `kitchen | store | manager | owner`)

**Flutter `models/staff_member.dart`:**
- `roleLabel` switch: added `'ict_admin' => 'ICT Admin'`
- `isIctAdmin` getter added
- `kAllCapabilities` expanded with three new entries:
  - `('can_delete_inventory',        'Delete Inventory Item')`
  - `('can_manage_yield_config',     'Manage Yield Config')`
  - `('can_manage_procurement',      'Manage Procurement')`
  - `('can_manage_expense_accounts', 'Manage Expense Accounts')`
- `defaultCapabilities` updated:
  - `manager` now includes all 4 new capabilities
  - `owner` inherits all (via `kAllCapabilities.map`)
  - `ict_admin` role added → defaults to `['can_manage_settings']`

**Flutter `models/staff.dart`:**
- `isStore` updated: now also returns `true` for `ict_admin` (so ICT admins route to `StoreShell` not `KitchenHome`)
- `isIctAdmin` getter added
- Four new capability getters:
  - `canDeleteInventory` — `can_delete_inventory` capability OR `isManager || isOwner`
  - `canManageYieldConfig` — `can_manage_yield_config` capability OR `isManager || isOwner`
  - `canManageProcurement` — `can_manage_procurement` capability OR `isManager || isOwner`
  - `canManageExpenseAccounts` — `can_manage_expense_accounts` capability OR `isManager || isOwner`

**Flutter `screens/store/staff_management_screen.dart`:**
- `_kLocations` list: added `'Cleaning Staff'`
- Sort order map: added `'ict_admin': 4` (appears after Kitchen)
- `_StaffCard._roleColors`: added `'ict_admin': Color(0xFF0097A7)` (cyan-teal)
- Role choice chips: added `('ict_admin', '💻 ICT Admin')` chip in `_StaffFormDialog`

**Flutter `screens/pin_login.dart` (`_StaffGrid`):**
- `_roleColor`: added `'ict_admin' => Color(0xFF0097A7)` (matches staff management colour)
- `_roleLabel`: added `'ict_admin' => 'ICT Admin'`
- `'owner'` colour corrected to amber (`0xFFFFB300`) from slate grey it was previously

**New `flutter_app/lib/screens/store/expense_accounts_screen.dart`:**
Full master-detail screen for manager float management. Only visible when `staff.canManageExpenseAccounts`:
- **Left panel** (`_AccountList`): lists all internal suppliers with their float balance (Available/Overdrawn badges)
- **Right panel** (`_AccountDetail`):
  - Header: account name + "FLOAT ACCOUNT" badge, location, balance card (green/red based on sign)
  - Three action buttons:
    1. **Record Cash-In** (blue) → `_CashInDialog`: amount, date picker, bank ref, description → calls `ApiService.recordCashIn()`
    2. **Record Expense** (orange) → `_ExpenseDialog`: type toggle (Paid a Supplier / Ad-Hoc Purchase), amount, date, description, reference → calls `ApiService.addLedgerEntry()` with `SUPPLIER_PAYMENT` or `PURCHASE`
    3. **Send Float Statement** (WhatsApp green) → calls `getSupplierStatementWhatsApp()` and opens deep-link
  - `_LedgerSection`: scrollable list of all ledger entries with type icon/colour/badge, date, description, reference, signed amount
- `_EmptyState`: shown when no internal suppliers exist — guides admin to create one in the Suppliers screen
- Responsive: mobile stacks list→detail with back button, desktop uses side-by-side layout

**Updated `flutter_app/lib/screens/store/store_shell.dart`:**
- Added `expenseAccounts` to `_NavItem` enum
- Nav item: `if (s.canManageExpenseAccounts)` → `Icons.account_balance_wallet_rounded`, "Expense Accounts"
- `_body()`: routes `_NavItem.expenseAccounts` → `ExpenseAccountsScreen(staff: staff)`
- Settings nav condition simplified to `canManageStaff` only (Business Details removed from Settings)
- Import added: `expense_accounts_screen.dart`

**Updated `flutter_app/lib/screens/store/supplier_ledger.dart`:**
- Removed the "Record Cash-In" button (`ElevatedButton.icon` with `CASH_IN` action) from the internal supplier detail action bar — replaced with a comment directing to the Expense Accounts screen. This prevents Storekeepers (who can see Suppliers) from initiating float top-ups.

**Updated `flutter_app/lib/screens/store/settings_screen.dart`:**
- Removed the `canManageSettings` tab ("Business Details") from the tab list entirely
- Settings screen now shows **only** Staff Management (for users with `canManageStaff`)
- The `_BusinessDetailsTab` widget was migrated to the Super Admin Dashboard

**Updated `flutter_app/lib/screens/super_admin/super_admin_dashboard.dart`:**
- `DefaultTabController.length` changed from 2 → 3
- Added "Business Details" as the middle tab (`Icons.business_rounded`)
- Added full `_BusinessDetailsTab` StatefulWidget with:
  - Dark theme styling (matching the rest of the admin dashboard)
  - Fields: Business Name, Slogan, Owner Name, Owner Phone
  - Live preview card (same dark login screen preview from the old Settings screen)
  - Calls `ApiService.getSettings()` / `ApiService.updateSettings()` — no new API endpoints needed
  - Uses `_fieldDeco()` helper for consistent dark input styling
- Import added: `'../../config/theme.dart'`

### Architecture Decisions

**Why `ict_admin` routes to `StoreShell` instead of `KitchenHome`:**
Kitchen staff have a request-focused UI (submitting requisitions). ICT admins need access to Settings (staff management, system config). The `StoreShell` + capability gating system gives them exactly what they need with no kitchen clutter. Their default capability `can_manage_settings` means they see only the Settings nav item.

**Why `canManageExpenseAccounts` falls back to `isManager || isOwner` rather than just capability:**
The Cash-In and float management workflows are inherently manager/owner responsibilities. Requiring a specific capability for all existing managers would mean every existing manager record needs migration. The `|| isManager || isOwner` fallback ensures backwards compatibility — new fine-grained assignees (e.g. senior accountant as `store` role) get the capability explicitly, while all managers/owners automatically inherit it.

**Why Business Details moved to Super Admin only:**
Business branding (name, slogan, phone) rarely changes after onboarding. Having it in the regular Settings screen created a risk of accidental edits by any `canManageSettings` user. The Super Admin backdoor provides a cleaner separation: client staff manage staff access (Settings), the system engineer manages core configuration (Super Admin Dashboard).

**Why the Expense Accounts screen doesn't show the "Record Purchase" / "Send Order" buttons that the Supplier Ledger shows:**
Those buttons (Record Purchase, Send Order) are external-supplier workflows — ordering stock, logging invoices. Internal (float) accounts don't receive orders or invoice deliveries. Removing those from the Expense Accounts screen eliminates confusion and keeps the float management UX focused: Cash-In (receive funds) + Expense (spend funds) + Statement (review).

**Why Cash-In was removed from `supplier_ledger.dart` rather than just hidden:**
Leaving the button in `supplier_ledger.dart` with a capability check would still leak the concept of "Cash-In" to Storekeepers who browse internal suppliers. Removing it entirely from the supplier detail means Storekeepers see only standard trading actions (Purchase, Payment, Order) regardless of whether a supplier is internal or external.

### New API Endpoints Summary (M12 / Phase 10)
_No new API endpoints — all existing endpoints were reused:_
| Method | Endpoint | Used for |
|--------|----------|----------|
| GET | `/api/suppliers` | Load internal accounts (filtered client-side by `is_internal`) |
| GET | `/api/suppliers/:id/ledger` | Load float ledger history |
| POST | `/api/suppliers/:id/ledger` | Record Cash-In (`CASH_IN`) or Expense (`SUPPLIER_PAYMENT`/`PURCHASE`) |
| GET | `/api/suppliers/:id/statement/whatsapp` | Send float statement |
| GET | `/api/settings` | Load business details in Super Admin tab |
| PATCH | `/api/settings` | Save business details from Super Admin tab |

---

## Milestone 13 – Capabilities Audit, Cycle Count Gating, OTHER_EXPENSE, New Item Request (Completed: 2026-04-16)

### Summary
Five tasks implemented in Phase 11. No new screens — all existing screens refined.

---

### 1. Capabilities Audit & Cleanup (`staff.dart`, `staff_member.dart`)

**Pattern discipline enforced.** All capabilities now fall into one of two explicit patterns:
- **Pattern A** (no fallback): `canManageInventory`, `canDraftPO`, `canManageStaff`, `canManageSettings` — these must be explicitly assigned.
- **Pattern B** (capability OR manager/owner fallback): `canApproveRequisitions`, `canViewVariance`, `canApprovePayRun`, `canDeleteInventory`, `canManageYieldConfig`, `canManageProcurement`, `canManageCycleCount`, `canManageExpenseAccounts`.

**Changes:**
- Removed `can_log_waste` from `kAllCapabilities` and all `defaultCapabilities` — `canLogWaste => true` remains in `staff.dart` (every staff member can log waste).
- Renamed `can_draft_po` display label: `'Draft Purchase Orders'` → `'Manage Purchase Orders'`.
- Added `('can_manage_cycle_count', 'Manage Cycle Counts')` to `kAllCapabilities`.
- Added `canManageCycleCount` getter (Pattern B) to `staff.dart`.
- Applied Pattern B fallbacks to `canApproveRequisitions`, `canViewVariance`, `canApprovePayRun` (they previously had no fallback, which meant managers without the explicit cap were locked out).
- Updated `defaultCapabilities`:
  - `kitchen => []` (was `['can_log_waste']`)
  - `store => ['can_approve_requisitions', 'can_manage_inventory', 'can_draft_po']` (removed `can_view_variance` — variance access is now manager+)
  - `manager` gets `can_manage_cycle_count` added, `can_log_waste` removed
  - `owner` still gets everything in `kAllCapabilities`
  - `ict_admin` unchanged: `['can_manage_settings']`

---

### 2. Cycle Count Capability Gating (`inventory_screen.dart`)

- `_InventoryHeader`: renamed param `isManager` → `canManageCycleCount`; cycle count button now only visible when `widget.staff.canManageCycleCount` is true.
- `_InventoryTable`: added `canDelete` param; delete `_ActionBtn` wrapped in `if (canDelete)` — hidden (not just disabled) when the user lacks `can_delete_inventory`.

---

### 3. ICT Label Fix (`pin_login.dart`)

- `_StaffGrid._roleLabel`: `'ict_admin'` now returns `'ICT'` (was `'ICT Admin'`). Compact enough for the role badge in the name grid.
- `staff_member.dart.roleLabel` unchanged — `'ICT Admin'` is still used in Staff Management screen labels.

---

### 4. OTHER_EXPENSE Type (`expense_accounts_screen.dart`, `ledger_entry.dart`, `suppliers.js`, `migrations/014_other_expense.sql`)

**New transaction type** for miscellaneous float spending not linked to a supplier record (fuel, stationery, petty cash, etc.).

**Changes:**
- `ledger_entry.dart`: Added `bool get isOtherExpense`, updated `isDebit` to include it.
- `expense_accounts_screen.dart`:
  - `_ExpenseDialog`: Added third chip `('OTHER_EXPENSE', '📋 Other Expense')`; changed `Row` → `Wrap(spacing: 8, runSpacing: 8)` for responsive chip layout; description label is now 3-way conditional (`Supplier/Payee` | `Expense Description` | `Description`).
  - `_LedgerRow`: Added `OTHER_EXPENSE` branch — purple `0xFF7B1FA2`, `Icons.receipt_outlined`, label `'Other Expense'`.
- `suppliers.js`:
  - POST `/api/suppliers/:id/ledger`: Added `OTHER_EXPENSE` to allowed types.
  - GET `/api/suppliers/:id/ledger`: `isDebit` now includes `OTHER_EXPENSE`.
  - GET `/api/suppliers/`, GET `/api/suppliers/alerts/upcoming-debt`: `balance_due` query includes `OTHER_EXPENSE` in the debit sum.
  - GET `/api/suppliers/:id/statement` and `/statement/whatsapp`: `OTHER_EXPENSE` tracked separately in period totals; WhatsApp message includes `📋 Other Expenses` line.
- `migrations/014_other_expense.sql`: Expands `transaction_type` ENUM to include `OTHER_EXPENSE`.

---

### 5. Kitchen "Request New Item" Feature (`kitchen_requisition.dart`, `requisitions.js`, `requisition.dart`, `api.dart`, `requisition_approval.dart`, `migrations/015_nullable_requisition_item.sql`)

Allows kitchen staff to request items not yet in inventory. The request is stored as a regular requisition with `inventory_item_id = NULL` and structured notes.

**Pattern:** `[NEW ITEM REQUEST] Name: {name} | Qty: {qty} {unit} | Notes: {notes}`

**Changes:**
- `migrations/015_nullable_requisition_item.sql`: `ALTER TABLE unix_requisitions MODIFY COLUMN inventory_item_id VARCHAR(36) NULL`.
- `requisitions.js`:
  - GET routes: all `JOIN unix_store_inventory` changed to `LEFT JOIN` to include null-item requests.
  - POST `/api/requisitions`: Now accepts either `inventory_item_id` (normal) or `item_name + unit` (new item). Constructs structured notes string automatically.
  - PATCH `/:id/issue`: Skips stock check and deduction when `inventory_item_id IS NULL`.
- `requisition.dart`: `inventoryItemId` is now `String?`; added `isNewItemRequest` and `newItemName` getters (parses `Name:` from notes prefix).
- `api.dart`: Added `submitNewItemRequest({requestedBy, itemName, unit, qty, purpose, notes?})`.
- `kitchen_requisition.dart`:
  - `_showNewItemRequestDialog()`: Dialog with Item Name, Qty, Unit dropdown, Purpose/Notes fields.
  - `OutlinedButton.icon` "Request New Item (Not in Stock)" placed below the search bar in `_RequestForm`.
  - `onNewItemRequest` callback threaded through `_Body` → `_RequestForm`.
- `requisition_approval.dart`:
  - `_RequisitionCard`: `isNewItemRequest` check — teal `🆕` icon, `NEW ITEM` teal badge, displays parsed `newItemName`, Issue button becomes `'Approve'` in teal-green (`0xFF00796B`).

---

### API changes in Milestone 13

| Method | Endpoint | Change |
|--------|----------|--------|
| POST | `/api/suppliers/:id/ledger` | Added `OTHER_EXPENSE` to allowed types |
| POST | `/api/requisitions` | Now accepts `item_name + unit` for new-item requests; `inventory_item_id` is optional |
| PATCH | `/api/requisitions/:id/issue` | Skips stock deduction for new-item requests (`inventory_item_id IS NULL`) |

### Migrations in Milestone 13
- `014_other_expense.sql` — Expands `transaction_type` ENUM on `unix_supplier_ledger`
- `015_nullable_requisition_item.sql` — Makes `inventory_item_id` nullable on `unix_requisitions`

---

## Milestone 14 — Refine New Item Request Approval Workflow (Completed: 2026-04-16)

### Problem
The M13 "New Item Request" feature left an incorrect UX: clicking "Approve" on a `isNewItemRequest` requisition opened the standard `_IssueDialog` asking how many units to issue — which makes no sense when the item doesn't exist in inventory yet.

### Solution
A dedicated `_AddNewItemFromRequestDialog` replaces the standard issue flow for new-item requests. It performs a two-step atomic sequence: create the inventory item, then close the requisition.

---

### Changes — `flutter_app/lib/screens/store/requisition_approval.dart`

**`_issue()` method branching:**
```
if (req.isNewItemRequest)  → show _AddNewItemFromRequestDialog
else                       → show _IssueDialog (unchanged)
```
On `ok == true` from the dialog, the parent shows the success snackbar and refreshes the list.

**`_AddNewItemFromRequestDialog` (new `StatefulWidget`):**

Fields:
| Field | Pre-fill | Required |
|-------|----------|----------|
| Item Name | `req.newItemName` (parsed from notes) | ✓ |
| Category | — (dropdown: Meat/Vegetables/Dairy/Dry Goods/Beverages/Cleaning/Packaging/Other) | ✓ |
| Unit of Measure | `req.unitOfMeasure ?? req.itemUom`, snapped to UOM list | ✓ |
| Min Stock Level (Reorder Level) | — | ✓ |
| Target Procure Qty | — | ✓ (stored in item notes) |
| Current Stock | Locked to 0, read-only info row | hardcoded |

**Submit sequence (error-safe — issues only if create succeeds):**
1. `ApiService.createInventoryItem(body)` — stock = 0, reorder qty stored in `notes` field as `"Target order qty: {n} {uom}"`
2. `ApiService.issueRequisition(req.id, staffName, issueNotes: 'Added to inventory as new item')` — backend skips stock deduction (M13 behaviour)
3. Returns `true` to parent → success snackbar + list refresh

**Error handling:** If `createInventoryItem` throws, `issueRequisition` is never called — the requisition stays Pending and the error is shown inline in the dialog.

**Design notes:**
- Context banner shows who requested it and with what quantity
- Locked stock row prevents confusion about "why is stock 0?"
- Max width `400` consistent with other app dialogs
- `reorder_quantity` has no dedicated DB column — stored as structured text in `notes` rather than silently dropped. This matches the existing draft-PO calculation which derives target qty from `(reorder_level * 2) - stock`

### No backend changes required
All API endpoints used (`POST /api/inventory`, `PATCH /api/requisitions/:id/issue`) were already in place from prior milestones.

---

## Milestone 15 — Inventory UI Refinements & Price Advisory "Wow Factor" (Completed: 2026-04-16)

Two independent improvements across frontend and backend.

---

### Task 1 — Clickable Reorder Alert Filter

**Files changed:** `flutter_app/lib/screens/store/inventory_screen.dart`

**What was done:**
- Added `bool _reorderFilterActive = false` to `_InventoryScreenState`.
- Updated `_filtered` getter to include `!_reorderFilterActive || item.needsReorder` condition.
- Passed `reorderFilterActive` and `onToggleReorderFilter` callback to `_InventoryHeader`.
- Replaced the static `_StatChip` for reorder count with a custom `AnimatedContainer` wrapped in `InkWell`.
  - When filter is **inactive**: chip has red tinted background, warning icon, label `"X need reorder"`.
  - When filter is **active**: chip turns solid red with white text + a close `×` icon — visually communicates "filter is on, click to clear".
  - `Tooltip` tells the user exactly what will happen before they click.
  - Animation uses `AnimatedContainer` (200ms) for a smooth colour/border transition.

---

### Task 2 — Price-Change Advisory "Wow Factor"

#### Backend — `src/routes/inventory.js` (PATCH /:id/adjust)

**New logic block** executes only when all conditions are met:
- `newCost != null && oldCost != null` (cost data available)
- `newCost > oldCost` (it's an actual increase, not decrease or no-change)
- `Number(delta) > 0` (it's a delivery, not a write-off — write-offs shouldn't trigger advisories)

**Query pattern:**
```sql
SELECT yc.portions_per_unit, p.id, p.name, p.pricesell
FROM unix_yield_config yc
LEFT JOIN products p ON yc.unicenta_product_id = p.id
WHERE yc.inventory_item_id = ?
  AND yc.portions_per_unit > 0
```
Uses `LEFT JOIN` so yield config rows with orphaned `unicenta_product_id` don't cause an exception — they're filtered out in JS with `.filter(r => r.product_name != null)`.

**Response shape** (only included when there are matched impacted products):
```json
{
  "priceWarning": {
    "itemName": "Pork",
    "oldCost": 150,
    "newCost": 200,
    "percentage": 33,
    "impactedProducts": [
      {
        "productName": "Roast Pork",
        "sellPrice": 500,
        "portionsPerUnit": 4,
        "costRisePerPortion": 12.50
      }
    ]
  }
}
```

**Failure safety:** The entire yield config block is wrapped in `try/catch`. If the `products` table is unreachable or the join fails (e.g., cross-schema permission issue), a `console.warn` is emitted and `priceWarning` stays `null` — the stock receipt still succeeds and returns `{ ok: true }`.

#### Frontend API — `flutter_app/lib/services/api.dart`

Changed `adjustStock` return type from `Future<void>` to `Future<Map<String, dynamic>?>`. Callers receive the full JSON body so they can inspect `response['priceWarning']`.

#### Frontend Math Fix — `_AdjustStockDialog._save()`

Before this fix, `newCostPerUnit` was never passed in delivery mode.  
Now: `newCostPerUnit = totalCost / amount` is computed whenever `_isDelivery && totalCost != null && amt > 0` and passed to `adjustStock()`. This enables both cost history logging and the price advisory.

#### Frontend UI — `_PriceAdvisoryDialog` (new widget)

Triggered in `_save()` after a successful `adjustStock` call that returns a `priceWarning`. The stock dialog does **not** immediately pop — it first awaits the advisory dialog, then pops with `true`.

**Design decisions:**
- `Dialog` (not `AlertDialog`) for full visual control — custom `ConstrainedBox(maxWidth: 480)`.
- **Gradient header** in deep amber/orange (`#E65100 → #F57C00`) — warm warning colour, not alarming red. Contains the "⚠️ Price Increase Detected" headline and item name subtext.
- **Cost jump summary** card shows old cost (strikethrough) → new cost (bold orange) + percentage badge. Uses amber tinted background (`#FFF3E0`) to reinforce the warning palette.
- **Impacted products list** — one card per product with restaurant menu icon, product name, sell price, portions-per-unit, and cost rise per portion (right-aligned, orange).
- **Advisory note** in light purple tinted box (to differentiate from warning) — italic, non-prescriptive language: "Consider advising management to review POS selling prices to maintain target margins."
- **"Got it — Stock recorded"** full-width green button dismisses the advisory. Green reinforces that the stock receive succeeded; the advisory is informational, not blocking.
- `barrierDismissible: false` — forces the manager to acknowledge the advisory (one tap, no accidental dismiss).

**Edge case:** If `priceWarning` is `null` (no yield config entries, or the query failed), the advisory is skipped entirely and the adjust dialog closes normally — zero friction for items not linked to any POS product.

---

### Design Note to Architect (Gemini)

The `_PriceAdvisoryDialog` uses two `NumberFormat` instances (`costFmt` with 2 decimals for per-portion cost, `costFmt0` with 0 decimals for headline prices). This is intentional — KES headline prices are always round integers in the POS, but per-portion cost rises will often be fractional (e.g., KES 12.50/portion).

The `products` table is assumed to be in the same MySQL database as the unix_ tables. If uniCenta is on a separate schema or database, a `db_prefix.products` reference or a cross-schema connection setting may be needed. The `LEFT JOIN` gracefully handles missing rows if the table doesn't exist in this context (query error caught in the outer try/catch).
