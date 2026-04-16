-- Migration 012: Feature Flags table for dynamic module toggling
CREATE TABLE IF NOT EXISTS unix_feature_flags (
  feature_key   VARCHAR(60)   NOT NULL PRIMARY KEY,
  enabled       TINYINT(1)    NOT NULL DEFAULT 1,
  label         VARCHAR(100)  NOT NULL DEFAULT '',
  description   VARCHAR(255)  NOT NULL DEFAULT '',
  updated_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Seed default flags — all enabled by default (INSERT IGNORE = safe re-run)
INSERT IGNORE INTO unix_feature_flags (feature_key, enabled, label, description) VALUES
  ('module_purchase_orders', 1, 'Purchase Orders',  'Enable the Purchase Orders workflow (maker-checker PO drafting and approval)'),
  ('module_procurement',     1, 'Procurement',       'Enable the Procurement screen (purchaser-based shopping lists via WhatsApp)'),
  ('module_pay_runs',        1, 'Pay Runs',           'Enable Pay Runs (scheduled supplier payment management for managers)'),
  ('module_variance',        1, 'Variance Report',   'Enable the Usage Variance dashboard (expected vs actual ingredient consumption)'),
  ('module_yield_config',    1, 'Yield Config',       'Enable the Yield / Portion configuration screen');
