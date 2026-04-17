-- ============================================================
-- Yunix Store Controller – Business Settings
-- Creates yunix_settings key-value store and seeds defaults.
-- Also grants can_manage_settings to existing managers/owners.
-- ============================================================

USE unicentapos;

-- ─────────────────────────────────────────────────────────────
-- 1. Settings table
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS yunix_settings (
  id            INT          NOT NULL AUTO_INCREMENT,
  setting_key   VARCHAR(100) NOT NULL,
  setting_value TEXT         NOT NULL DEFAULT '',
  updated_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                             ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_setting_key (setting_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- 2. Seed default values (idempotent)
-- ─────────────────────────────────────────────────────────────
INSERT INTO yunix_settings (setting_key, setting_value) VALUES
  ('business_name', 'Yunix Store'),
  ('slogan',        'Premium Restaurant Management')
ON DUPLICATE KEY UPDATE setting_key = setting_key;

-- ─────────────────────────────────────────────────────────────
-- 3. Grant can_manage_settings to existing managers & owners
--    (only if not already present and capabilities is not null)
-- ─────────────────────────────────────────────────────────────
UPDATE yunix_staff
  SET capabilities = JSON_ARRAY_APPEND(capabilities, '$', 'can_manage_settings')
  WHERE role IN ('manager', 'owner')
    AND capabilities IS NOT NULL
    AND JSON_SEARCH(capabilities, 'one', 'can_manage_settings') IS NULL;
