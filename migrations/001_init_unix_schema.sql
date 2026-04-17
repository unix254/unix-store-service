-- ============================================================
-- Yunix Store Controller – Initial Schema (unix_ namespace)
-- Safe to run on every startup: uses CREATE TABLE IF NOT EXISTS
-- READ-ONLY rule: NO inserts/updates to legacy uniCenta tables
-- ============================================================

USE unicentapos;

-- ─────────────────────────────────────────────────────────────
-- 1. SUPPLIERS
--    Profiles for all food/supply vendors.
--    payment_day: e.g. 'Monday' – day of week the owner pays
--    lead_time_days: how many days ahead to reorder
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS store_suppliers (
  id              VARCHAR(36)   NOT NULL,
  name            VARCHAR(255)  NOT NULL,
  phone           VARCHAR(30)   NULL,
  location        VARCHAR(255)  NULL,
  payment_day     VARCHAR(20)   NULL,
  lead_time_days  INT           NULL DEFAULT 1,
  notes           TEXT          NULL,
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- 2. STORE INVENTORY
--    Bulk stock items held in the store (e.g. "Whole Chicken 1kg").
--    These are NOT the same as uniCenta products (which are menu items).
--    reorder_level: when stock drops to this level, raise a reorder alert.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS store_inventory (
  id                VARCHAR(36)   NOT NULL,
  name              VARCHAR(255)  NOT NULL,
  category          VARCHAR(100)  NULL,
  unit_of_measure   VARCHAR(30)   NOT NULL DEFAULT 'pcs',
  quantity_in_stock DECIMAL(12,3) NOT NULL DEFAULT 0.000,
  reorder_level     DECIMAL(12,3) NULL,
  cost_per_unit     DECIMAL(12,2) NULL,
  supplier_id       VARCHAR(36)   NULL,
  notes             TEXT          NULL,
  created_at        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT fk_inventory_supplier
    FOREIGN KEY (supplier_id) REFERENCES store_suppliers(id)
    ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- 3. SUPPLIER LEDGER
--    Running balance per supplier.
--    PURCHASE = increases debt (we owe them money).
--    PAYMENT  = decreases debt (we paid them).
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS store_supplier_ledger (
  id                VARCHAR(36)   NOT NULL,
  supplier_id       VARCHAR(36)   NOT NULL,
  transaction_type  ENUM('PURCHASE','PAYMENT') NOT NULL,
  amount            DECIMAL(12,2) NOT NULL,
  description       VARCHAR(500)  NULL,
  reference_doc     VARCHAR(100)  NULL,
  transaction_date  DATE          NOT NULL,
  created_at        DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT fk_ledger_supplier
    FOREIGN KEY (supplier_id) REFERENCES store_suppliers(id)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- 4. REQUISITIONS
--    Internal stock movements: Store → Kitchen / Barista.
--    purpose distinguishes 'Sales' stock from 'Staff Meal' costs.
--    This is the critical column for the Usage Variance engine.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS store_requisitions (
  id                VARCHAR(36)   NOT NULL,
  inventory_item_id VARCHAR(36)   NOT NULL,
  quantity          DECIMAL(12,3) NOT NULL,
  unit_of_measure   VARCHAR(30)   NULL,
  requested_by      VARCHAR(100)  NOT NULL,
  purpose           ENUM('Sales','Staff Meal','Wastage','Other') NOT NULL DEFAULT 'Sales',
  status            ENUM('Pending','Approved','Issued','Rejected') NOT NULL DEFAULT 'Pending',
  notes             TEXT          NULL,
  requested_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  issued_at         DATETIME      NULL,
  issued_by         VARCHAR(100)  NULL,
  PRIMARY KEY (id),
  CONSTRAINT fk_req_inventory
    FOREIGN KEY (inventory_item_id) REFERENCES store_inventory(id)
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- 5. YIELD CONFIG
--    Maps a bulk store item to a uniCenta POS product with a portion factor.
--    Example: 1 Whole Chicken (store_inventory) → 8 × "Chicken Portion" (products.id)
--    This powers the "Usage Variance" engine: Sales × (1/portions_per_unit)
--    = expected store consumption vs actual store issues.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS store_yield_config (
  id                   VARCHAR(36)   NOT NULL,
  inventory_item_id    VARCHAR(36)   NOT NULL,
  unicenta_product_id  VARCHAR(255)  NOT NULL,
  portions_per_unit    DECIMAL(10,3) NOT NULL,
  notes                VARCHAR(500)  NULL,
  created_at           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_yield (inventory_item_id, unicenta_product_id),
  CONSTRAINT fk_yield_inventory
    FOREIGN KEY (inventory_item_id) REFERENCES store_inventory(id)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
