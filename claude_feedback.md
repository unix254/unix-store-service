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
- The `can_access_bi` capability needs to be granted in the DB for existing store-keeper staff who should see the BI Hub (managers/owners get it via role fallback). A one-time SQL like `UPDATE unix_staff SET capabilities = JSON_ARRAY_APPEND(capabilities, '$', 'can_access_bi') WHERE role IN ('store') AND JSON_CONTAINS(capabilities, '"can_view_variance"')` can be used if needed.
- The BI Hub will render fine on tablets (>= 800px) and on mobile (drawer-based nav). The tab labels might need testing on very small screens — they can be made icon-only if text overflows.
