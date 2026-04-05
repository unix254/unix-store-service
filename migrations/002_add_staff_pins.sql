-- ============================================================
-- Yunix Store Controller – Staff PIN Auth
-- Simple PIN-based role routing (no passwords, no emails).
-- Roles: 'kitchen' → Kitchen Tablet UI | 'store'/'manager' → Desktop UI
-- ============================================================

USE unicentapos;

CREATE TABLE IF NOT EXISTS unix_staff (
  id         VARCHAR(36)                          NOT NULL,
  name       VARCHAR(100)                         NOT NULL,
  pin        CHAR(4)                              NOT NULL,
  role       ENUM('kitchen','store','manager')    NOT NULL DEFAULT 'kitchen',
  active     TINYINT(1)                           NOT NULL DEFAULT 1,
  created_at DATETIME                             NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_pin (pin)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed default staff so the system is usable immediately after first deploy.
-- Owner should change these PINs after first login.
INSERT IGNORE INTO unix_staff (id, name, pin, role) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Store Keeper', '1111', 'store'),
  ('00000000-0000-0000-0000-000000000002', 'Manager',      '9999', 'manager'),
  ('00000000-0000-0000-0000-000000000003', 'Kitchen Staff', '2222', 'kitchen');
