-- Migration 004: Purchase Orders Maker-Checker workflow

-- Purchase Order header
CREATE TABLE IF NOT EXISTS store_purchase_orders (
  id          VARCHAR(36)  NOT NULL PRIMARY KEY,
  status      ENUM('DRAFT','PENDING_APPROVAL','APPROVED','SENT') NOT NULL DEFAULT 'DRAFT',
  created_by  VARCHAR(255) NULL,
  approved_by VARCHAR(255) NULL,
  notes       TEXT         NULL,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  approved_at DATETIME     NULL
);

-- Purchase Order line items
CREATE TABLE IF NOT EXISTS store_po_details (
  id                 VARCHAR(36)    NOT NULL PRIMARY KEY,
  po_id              VARCHAR(36)    NOT NULL,
  inventory_item_id  VARCHAR(36)    NOT NULL,
  supplier_id        VARCHAR(36)    NULL,
  suggested_qty      DECIMAL(10,3)  NOT NULL DEFAULT 0,
  approved_qty       DECIMAL(10,3)  NOT NULL DEFAULT 0,
  CONSTRAINT fk_pod_po FOREIGN KEY (po_id) REFERENCES store_purchase_orders(id) ON DELETE CASCADE
);
