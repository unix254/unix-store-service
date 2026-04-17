-- Migration 013: Add ict_admin to the yunix_staff role ENUM
-- Safe to re-run: only alters if ict_admin is not already in the ENUM.

SET @col_type = (
  SELECT COLUMN_TYPE
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME   = 'yunix_staff'
    AND COLUMN_NAME  = 'role'
);

SET @needs_update = IF(
  LOCATE('ict_admin', @col_type) = 0,
  'ALTER TABLE yunix_staff MODIFY COLUMN role ENUM(''kitchen'', ''store'', ''manager'', ''owner'', ''ict_admin'') NOT NULL',
  'SELECT 1'
);

PREPARE stmt FROM @needs_update;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
