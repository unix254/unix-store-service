-- Migration 014: Add OTHER_EXPENSE to the store_supplier_ledger transaction_type ENUM.
-- OTHER_EXPENSE is a catch-all debit for miscellaneous float spending not linked to a
-- supplier record (e.g. fuel, stationery, petty cash). Used exclusively on internal
-- (manager) accounts. Treated as a debit just like PURCHASE / SUPPLIER_PAYMENT.

USE unicentapos;

ALTER TABLE store_supplier_ledger
  MODIFY COLUMN transaction_type
    ENUM('PURCHASE', 'PAYMENT', 'SUPPLIER_PAYMENT', 'CASH_IN', 'OTHER_EXPENSE') NOT NULL;
