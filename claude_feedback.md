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
