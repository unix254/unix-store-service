-- ============================================================
-- Yunix Store Controller – Phase 7
-- Manager Cash-In Tracking
-- ============================================================

USE unicentapos;

-- ─────────────────────────────────────────────────────────────
-- Expand transaction_type ENUM to include CASH_IN.
-- CASH_IN is a credit entry used exclusively on internal supplier
-- (manager) ledgers to record bank withdrawals / float top-ups.
-- It reduces the manager's outstanding balance, just like PAYMENT.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE store_supplier_ledger
  MODIFY COLUMN transaction_type
    ENUM('PURCHASE', 'PAYMENT', 'SUPPLIER_PAYMENT', 'CASH_IN') NOT NULL;
