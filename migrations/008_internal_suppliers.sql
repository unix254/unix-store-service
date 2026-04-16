-- ============================================================
-- Yunix Store Controller – Internal Suppliers & Procurement
-- Adds manager expense accounts, default purchaser routing,
-- and procurement list logging.
-- ============================================================

USE unicentapos;

-- ─────────────────────────────────────────────────────────────
-- 1. Mark suppliers as Internal Expense Accounts
--    is_internal = 1 means this supplier record represents
--    a manager who holds company cash (not an external vendor).
-- ─────────────────────────────────────────────────────────────
ALTER TABLE unix_suppliers
  ADD COLUMN IF NOT EXISTS is_internal TINYINT(1) NOT NULL DEFAULT 0;

-- ─────────────────────────────────────────────────────────────
-- 2. Default Purchaser on inventory items
--    Points to an internal supplier (manager) who is responsible
--    for buying this item. Used to route procurement lists.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE unix_store_inventory
  ADD COLUMN IF NOT EXISTS default_purchaser_id VARCHAR(36) NULL;

ALTER TABLE unix_store_inventory
  DROP FOREIGN KEY IF EXISTS fk_inventory_purchaser;

ALTER TABLE unix_store_inventory
  ADD CONSTRAINT fk_inventory_purchaser
  FOREIGN KEY (default_purchaser_id) REFERENCES unix_suppliers(id)
  ON DELETE SET NULL;

-- ─────────────────────────────────────────────────────────────
-- 3. Pay run detail: payment tracking columns
--    payment_source_id: internal supplier (manager) who paid
--    payment_reference: MPesa code or bank ref
-- ─────────────────────────────────────────────────────────────
ALTER TABLE unix_pay_run_details
  ADD COLUMN IF NOT EXISTS payment_source_id  VARCHAR(36)  NULL,
  ADD COLUMN IF NOT EXISTS payment_reference  VARCHAR(100) NULL,
  ADD COLUMN IF NOT EXISTS disbursed_by       VARCHAR(100) NULL,
  ADD COLUMN IF NOT EXISTS disbursed_at       DATETIME     NULL;

-- ─────────────────────────────────────────────────────────────
-- 4. Procurement logs
--    Audit trail for every generated procurement list.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS unix_procurement_logs (
  id            VARCHAR(36)   NOT NULL,
  generated_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  generated_by  VARCHAR(100)  NULL,
  item_count    INT           NOT NULL DEFAULT 0,
  groups_json   JSON          NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
