-- Migration 016: Rename legacy unix_ tables to store_/yunix_ prefix scheme.
-- This migration is a NO-OP on fresh installs (tables won't exist yet).
-- On existing staging/production servers it renames data-bearing tables in-place
-- so no data is lost when the app boots with the new prefix architecture.
--
-- Execution order matters: rename child tables before parent renames where FKs exist.
-- MariaDB RENAME TABLE is atomic and does not require data movement.

-- ─── STORE-ISOLATED TABLES ────────────────────────────────────────────────────

-- store_pay_run_details before store_pay_runs (FK child first)
RENAME TABLE IF EXISTS unix_pay_run_details TO store_pay_run_details;
RENAME TABLE IF EXISTS unix_pay_runs TO store_pay_runs;

-- store_po_details before store_purchase_orders (FK child first)
RENAME TABLE IF EXISTS unix_po_details TO store_po_details;
RENAME TABLE IF EXISTS unix_purchase_orders TO store_purchase_orders;

-- store_cost_history references store_inventory (child before parent)
RENAME TABLE IF EXISTS unix_cost_history TO store_cost_history;

-- store_yield_config references store_inventory (child before parent)
RENAME TABLE IF EXISTS unix_yield_config TO store_yield_config;

-- store_requisitions references store_inventory (child before parent)
RENAME TABLE IF EXISTS unix_requisitions TO store_requisitions;

-- store_procurement_logs (standalone)
RENAME TABLE IF EXISTS unix_procurement_logs TO store_procurement_logs;

-- store_supplier_ledger references store_suppliers (child before parent)
RENAME TABLE IF EXISTS unix_supplier_ledger TO store_supplier_ledger;

-- store_inventory references store_suppliers (child before parent)
-- NOTE: old name was unix_store_inventory (redundant 'store'), new name drops it
RENAME TABLE IF EXISTS unix_store_inventory TO store_inventory;

-- store_suppliers (parent — rename after all children)
RENAME TABLE IF EXISTS unix_suppliers TO store_suppliers;

-- ─── SHARED ECOSYSTEM TABLES ──────────────────────────────────────────────────

RENAME TABLE IF EXISTS unix_feature_flags TO yunix_feature_flags;
RENAME TABLE IF EXISTS unix_settings TO yunix_settings;
RENAME TABLE IF EXISTS unix_staff TO yunix_staff;

-- ─── MIGRATION TRACKING TABLE ─────────────────────────────────────────────────
-- Renamed last: the store_migrations table tracks this very migration.
-- After this rename the new boot logic reads from store_migrations correctly.
RENAME TABLE IF EXISTS unix_migrations TO store_migrations;
