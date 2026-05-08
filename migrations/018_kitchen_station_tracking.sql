-- Migration 018: Kitchen Station Tracking & True Variance Engine (v1.2.0)
--
-- Adds the concept of named kitchen stations (e.g., Main Kitchen, Barista Station)
-- as distinct inventory locations with their own virtual bin tracking.
-- Closing and opening stock counts per station unlock the true variance formula:
--   true_consumption = opening + transfers_in − waste − closing_stock
-- When no snapshots exist for a period, the system falls back to the v1.1
-- estimate formula automatically — zero disruption for existing live clients.

-- ── 1. Store Stations ──────────────────────────────────────────────────────────
-- Named prep/service stations within a branch (NOT branch-level locations).
-- Future: a yunix_branches table will sit above this as the parent.

CREATE TABLE IF NOT EXISTS store_stations (
  id          VARCHAR(36)   NOT NULL,
  name        VARCHAR(100)  NOT NULL,
  description VARCHAR(255)  NULL,
  is_active   TINYINT(1)    NOT NULL DEFAULT 1,
  created_at  DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_station_name (name)
);

-- ── 2. Kitchen Stock Snapshots ─────────────────────────────────────────────────
-- One record per (station, business-date, type) pair.
-- CLOSING = night team physical count. OPENING = morning team confirmation count.
-- status: DRAFT → SUBMITTED → CONFIRMED (storekeeper locks it).

CREATE TABLE IF NOT EXISTS store_kitchen_snapshots (
  id                  VARCHAR(36)                       NOT NULL,
  station_id          VARCHAR(36)                       NOT NULL,
  snapshot_date       DATE                              NOT NULL,
  snapshot_type       ENUM('CLOSING','OPENING')         NOT NULL,
  status              ENUM('DRAFT','SUBMITTED','CONFIRMED') NOT NULL DEFAULT 'SUBMITTED',
  counted_by          VARCHAR(100)                      NOT NULL,
  counted_at          DATETIME                          NOT NULL DEFAULT CURRENT_TIMESTAMP,
  confirmed_by        VARCHAR(100)                      NULL,
  confirmed_at        DATETIME                          NULL,
  is_peak_hours       TINYINT(1)                        NOT NULL DEFAULT 0,
  notes               TEXT                              NULL,
  PRIMARY KEY (id),
  INDEX idx_snap_station_date  (station_id, snapshot_date, snapshot_type),
  INDEX idx_snap_status        (status),
  CONSTRAINT fk_snap_station
    FOREIGN KEY (station_id) REFERENCES store_stations(id)
    ON DELETE CASCADE
);

-- ── 3. Kitchen Snapshot Line Items ─────────────────────────────────────────────
-- One row per inventory item counted in a snapshot.
-- counted_quantity is the raw blind count entered by kitchen staff.

CREATE TABLE IF NOT EXISTS store_kitchen_snapshot_items (
  id                  VARCHAR(36)    NOT NULL,
  snapshot_id         VARCHAR(36)    NOT NULL,
  inventory_item_id   VARCHAR(36)    NOT NULL,
  counted_quantity    DECIMAL(12,3)  NOT NULL DEFAULT 0.000,
  notes               VARCHAR(500)   NULL,
  PRIMARY KEY (id),
  INDEX idx_snap_items_snapshot   (snapshot_id),
  INDEX idx_snap_items_inventory  (inventory_item_id),
  CONSTRAINT fk_snap_item_snapshot
    FOREIGN KEY (snapshot_id) REFERENCES store_kitchen_snapshots(id)
    ON DELETE CASCADE,
  CONSTRAINT fk_snap_item_inventory
    FOREIGN KEY (inventory_item_id) REFERENCES store_inventory(id)
);

-- ── 4. Risk Tier on Inventory ──────────────────────────────────────────────────
-- Controls UX during opening confirmation:
--   High / Standard → blind recount required
--   Low             → show current balance, one-tap confirm
-- NULL = auto-classify by cost_per_unit (> 300 KES = High, 50-300 = Standard, < 50 = Low)

ALTER TABLE store_inventory
  ADD COLUMN IF NOT EXISTS risk_tier ENUM('High','Standard','Low') NULL DEFAULT NULL;
