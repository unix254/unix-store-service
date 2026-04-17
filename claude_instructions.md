# Milestone 16: Business Intelligence (BI) Hub & Price Impact Overhaul

**Context:**
In the previous milestone, a "Wow Factor" Price Advisory modal was added to the `adjustStock` dialog, and a "Price Impact" section was added to the `variance_screen.dart`. 
After reviewing this in the staging environment, the product owner has decided on a strategic pivot:
1. **Remove the real-time modal:** Storekeepers receiving stock shouldn't be interrupted with POS pricing decisions. We do not want real-time popup alerts.
2. **Remove the inline section in Variance:** The Variance Dashboard should remain focused purely on physical stock variances (lost items, waste, etc.). Remove the "Price Impact – Recent Cost Changes" UI entirely from `variance_screen.dart`.
3. **Establish a Dedicated BI Hub:** We want to organize analytics logically. Create a new top-level sidebar module called **Business Intelligence (BI)**. This module will house three tabs/sub-sections:
   - **Variance Dashboard** (existing, but cleaned up)
   - **Yield Config** (existing)
   - **Price Impact Advisory** (new, dedicated screen)

---

### Task 1: Security & Capabilities (`canAccessBI`)
- **Backend:** In the appropriate user role/capability configurations (e.g. `staff.js`), introduce a new boolean capability flag: `canAccessBI`. 
- **Frontend Security (`staff_member.dart`):** Add `canAccessBI` to the staff model.
- **Deprecation:** You can gracefully remove or ignore `canManageYield` and `canViewVariance` (if they exist) and consolidate the access rules. Any user currently authorized for reports should get `canAccessBI`. The entire BI Hub should be gated by this single capability.

### Task 2: Build the BI Hub Shell (`bi_shell.dart`)
- **Create `lib/screens/store/bi_shell.dart`**: This should be a wrapper screen (perhaps with a `DefaultTabController` and `TabBar`) containing 3 tabs:
  1. Variance Dashboard
  2. Yield Config
  3. Price Impact Advisory
- **Sidebar Integration:** In the main app shell (`store_shell.dart` or equivalent), remove the separate sidebar entries for "Yield Config" and "Variance Dashboard". Replace them with a single **Business Intelligence (BI)** entry with a nice chart/analytics icon. Clicking it opens the new `bi_shell.dart`.

### Task 3: Cleanup Existing UI
- **`inventory_screen.dart` (`_AdjustStockDialog`)**: Strip out the logic that explicitly triggers the `_PriceAdvisoryDialog`. The stock receive process should just complete silently and cleanly again. You can keep the `costRisePerPortion` math in the backend if you want, but it will primarily be moved to the reporting endpoint.
- **`variance_screen.dart`**: Completely delete the "Price Impact — Recent Cost Changes" section at the bottom of the screen.

### Task 4: The Dedicated Price Impact Advisory Screen
- **Backend (`inventory.js`)**: Extend or heavily modify the `GET /api/inventory/inflation-summary` endpoint (or create a new one). It must calculate cumulated cost changes over a timeframe (e.g., last 30 days) and explicitly `JOIN` to `unix_yield_config` and uniCenta's `products` table. It should return a clean array of impacted items, their old/new costs, the affected POS products, their current sell price, and the expected cost-rise per portion.
- **Frontend (`price_impact_screen.dart`)**: Build a beautiful, professional, high-density data table displaying this payload. Use Yunix's premium visual aesthetics.

### Task 5: WhatsApp Integration
- On the new `price_impact_screen.dart`, add a prominent button: **"Send Analysis via WhatsApp"**.
- When clicked, it should open a simple dialog asking for a target Phone Number (or select a management group if you prefer).
- **Backend Route:** Create a new POST endpoint (e.g., `/api/inventory/send-price-impact`) that:
  1. Runs the same query as the report.
  2. Formats the data into a clean, readable text string (using markdown/emojis suitable for WhatsApp).
  3. Dispatches it to the `mpesa-service` WhatsApp router (just like the Yunix Wash Z-Reports).

**Important:** Please review the Git changes you made for Milestone 15 to ensure you cleanly revert the `_PriceAdvisoryDialog` in `inventory_screen.dart` while preserving the clickable `Reorder Alerts` filter which the user absolutely loved!
