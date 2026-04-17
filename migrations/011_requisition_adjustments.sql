-- ============================================================
-- Yunix Store Controller – Phase 8
-- Flexible Requisition Issuance
-- ============================================================

USE unicentapos;

-- issued_quantity: the actual amount the storekeeper chose to issue
--   (may differ from the originally requested quantity).
-- issue_notes: reason text attached by the storekeeper when
--   adjusting quantity or rejecting a requisition.
ALTER TABLE store_requisitions
  ADD COLUMN IF NOT EXISTS issued_quantity DECIMAL(10,3) NULL,
  ADD COLUMN IF NOT EXISTS issue_notes     VARCHAR(500)  NULL;
