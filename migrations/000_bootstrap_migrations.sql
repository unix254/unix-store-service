-- Migration 000: Bootstrap the unix_migrations tracking table.
-- Seeds all previously-applied migration files (001–013) so the new
-- tracked runner does not attempt to re-run them on restart.
-- Migrations 014 and 015 are NOT seeded here — they run fresh on next startup.

CREATE TABLE IF NOT EXISTS unix_migrations (
  filename     VARCHAR(255) NOT NULL PRIMARY KEY,
  applied_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT IGNORE INTO unix_migrations (filename) VALUES
  ('001_init_unix_schema.sql'),
  ('002_add_staff_pins.sql'),
  ('003_milestone6.sql'),
  ('004_purchase_orders.sql'),
  ('005_add_owner_role.sql'),
  ('006_business_settings.sql'),
  ('007_owner_contact.sql'),
  ('008_internal_suppliers.sql'),
  ('009_supplier_statements.sql'),
  ('010_cash_in.sql'),
  ('011_requisition_adjustments.sql'),
  ('012_feature_flags.sql'),
  ('013_add_ict_admin_role.sql');
