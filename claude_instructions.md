# Milestone 17: Database Prefix & Microservice Isolation

**Context:**
Currently, our backend tables all use the `unix_` prefix. However, as the ecosystem grows (e.g., M-Pesa Service, Yunix Wash), multiple companion apps connect to the same central MariaDB `unicentapos` database.
Using the same `unix_` prefix puts us at risk of catastrophic migration collisions (where one service might accidentally modify or drop tables belonging to another). 

We are moving to a **Hybrid Prefix Architecture**:
1. **`store_`**: For tables completely isolated and belonging only to this `unix-store-service`.
2. **`yunix_`**: For core ecosystem tables that multiple services (like the Waiter app and Store app) share.

---

### Task 1: Update Existing Migration History (`migrations/`)
You need to do a massive rename in the actual raw migration files (`000` through `014` or wherever we are at map). 
Find and replace all `unix_` instances in the `migrations/` folder SQL files based on this mapping:

**Store-specific tables (Change `unix_[name]` to `store_[name]`):**
- `unix_migrations` -> `store_migrations`  *(CRITICAL: this ensures our backend doesn't read the M-Pesa migration table)*
- `unix_store_inventory` -> `store_inventory` *(Drop the redundant 'store', just store_inventory)*
- `unix_suppliers` -> `store_suppliers`
- `unix_supplier_ledger` -> `store_supplier_ledger`
- `unix_requisitions` -> `store_requisitions`
- `unix_yield_config` -> `store_yield_config`
- `unix_cost_history` -> `store_cost_history`
- `unix_pay_runs` -> `store_pay_runs`
- `unix_pay_run_details` -> `store_pay_run_details`
- `unix_purchase_orders` -> `store_purchase_orders`
- `unix_po_details` -> `store_po_details`
- `unix_procurement_logs` -> `store_procurement_logs`

**Shared Eco-system Tables (Change `unix_[name]` to `yunix_[name]`):**
- `unix_staff` -> `yunix_staff`
- `unix_settings` -> `yunix_settings`
- `unix_feature_flags` -> `yunix_feature_flags`

*(Note: Carefully ensure you don't break string matching rules in SQL. Just rename the tables).*

### Task 2: Create a State-Saving Migration Hook
Because the client's staging server is *already* running with the old `unix_` tables, if we just push this, the backend will boot up, panic, and create empty `store_` tables, losing all their data!
- Create a new migration file (e.g. `015_rename_existing_tables_for_isolation.sql`).
- In this file, write safe `RENAME TABLE` SQL commands that check if the old `unix_` table exists, and if so, renames it. 
- *Caveat:* Since MariaDB doesn't natively support `RENAME TABLE IF EXISTS` easily without procedural logic, write concise, safe `ALTER TABLE` / `RENAME` scripts wrapped carefully, or use Node.js migration framework logic to catch/ignore "table doesn't exist" errors if it's already renamed. 
  - Actually, we do migrations in JS inside `db.js`. Please ensure that when the Node.js app boots, before it runs migrations tracked in `store_migrations`, it executes a hardcoded raw SQL script converting the old tables so no data is lost!

### Task 3: Global Backend Refactoring (`src/`)
- Run a global workspace search across `src/**/*.js`.
- Replace all references to the old `unix_` table names with their respective `store_` or `yunix_` names exactly matching the map in Task 1.

### Task 4: Global Frontend Verification (`flutter_app/`)
- Ensure our Flutter Dart code doesn't have hardcoded `unix_` logic (it shouldn't, as it communicates via JSON models/APIs, but double check things like the capability arrays or yield mappings).

### Important Note for Claude:
After completing this, please ensure the backend starts successfully and doesn't crash on Boot due to the migration engine looking for the new `store_migrations` table! Write your completion details natively into `claude_feedback.md`.
