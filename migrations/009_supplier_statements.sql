-- ============================================================
-- Yunix Store Controller – Phase 6
-- Supplier Statements & Manager Ledger Optimization
-- ============================================================

USE unicentapos;

-- ─────────────────────────────────────────────────────────────
-- 1. Expand transaction_type ENUM to include SUPPLIER_PAYMENT
--    SUPPLIER_PAYMENT: used on a manager's (internal) ledger
--    when they use business cash to pay an external supplier.
--    Distinct from PURCHASE (ad-hoc petty cash buy by manager).
-- ─────────────────────────────────────────────────────────────
ALTER TABLE unix_supplier_ledger
  MODIFY COLUMN transaction_type
    ENUM('PURCHASE', 'PAYMENT', 'SUPPLIER_PAYMENT', 'CASH_IN') NOT NULL;

-- ─────────────────────────────────────────────────────────────
-- 2. Add related_supplier_id to link cross-ledger entries
--    When a manager pays an external supplier, this column
--    stores the external supplier's id so the manager can see
--    which supplier their cash went to.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE unix_supplier_ledger
  ADD COLUMN IF NOT EXISTS related_supplier_id VARCHAR(36) NULL;

ALTER TABLE unix_supplier_ledger
  DROP FOREIGN KEY IF EXISTS fk_ledger_related_supplier;

ALTER TABLE unix_supplier_ledger
  ADD CONSTRAINT fk_ledger_related_supplier
  FOREIGN KEY (related_supplier_id) REFERENCES unix_suppliers(id)
  ON DELETE SET NULL;
