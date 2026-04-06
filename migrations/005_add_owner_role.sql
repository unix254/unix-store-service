-- ============================================================
-- Yunix Store Controller – Add 'owner' role
-- Extends unix_staff.role ENUM to include 'owner'.
-- Run this once against the live database.
-- ============================================================

USE unicentapos;

ALTER TABLE unix_staff
  MODIFY COLUMN role ENUM('kitchen','store','manager','owner') NOT NULL DEFAULT 'kitchen';

-- Seed full capabilities for any existing owner-role rows that lack them
UPDATE unix_staff
  SET capabilities = '["can_approve_requisitions","can_manage_inventory","can_draft_po","can_approve_payrun","can_log_waste","can_manage_staff","can_view_variance"]'
  WHERE role = 'owner' AND capabilities IS NULL;
