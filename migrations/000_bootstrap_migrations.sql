-- Migration 000: Bootstrap the store_migrations tracking table.
-- Seeds all previously-applied migration files (001–013) so the new
-- tracked runner does not attempt to re-run them on restart.
-- Migrations 014 and 015 are NOT seeded here — they run fresh on next startup.

CREATE TABLE IF NOT EXISTS store_migrations (
  filename     VARCHAR(255) NOT NULL PRIMARY KEY,
  applied_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Only insert the legacy files as "already applied" IF the original unix schema was 
-- already deployed (which we detect by the existence of yunix_staff).
-- This protects fresh production installations from skipping crucial migrations.
INSERT IGNORE INTO store_migrations (filename)
SELECT m.filename FROM (
  SELECT '001_init_unix_schema.sql' AS filename
  UNION SELECT '002_add_staff_pins.sql'
  UNION SELECT '003_milestone6.sql'
  UNION SELECT '004_purchase_orders.sql'
  UNION SELECT '005_add_owner_role.sql'
  UNION SELECT '006_business_settings.sql'
  UNION SELECT '007_owner_contact.sql'
  UNION SELECT '008_internal_suppliers.sql'
  UNION SELECT '009_supplier_statements.sql'
  UNION SELECT '010_cash_in.sql'
  UNION SELECT '011_requisition_adjustments.sql'
  UNION SELECT '012_feature_flags.sql'
  UNION SELECT '013_add_ict_admin_role.sql'
) AS m
WHERE EXISTS (
  SELECT 1 FROM information_schema.tables 
  WHERE table_schema = DATABASE() AND table_name = 'yunix_staff'
);
