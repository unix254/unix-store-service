-- ============================================================
-- Yunix Store Controller – Owner Contact Settings
-- Seeds owner_name and owner_phone keys into unix_settings.
-- Used by the pay run WhatsApp approval message.
-- ============================================================

USE unicentapos;

INSERT INTO unix_settings (setting_key, setting_value) VALUES
  ('owner_name',  ''),
  ('owner_phone', '')
ON DUPLICATE KEY UPDATE setting_key = setting_key;
