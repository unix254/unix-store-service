-- ============================================================
-- Yunix Store Controller – Milestone 6 Schema Additions
-- Phase 2: Role Capabilities, Multi-Location, Pay Runs,
--          Purchase Orders, Waste Log, Cost History
-- All ALTER TABLE uses IF NOT EXISTS for idempotency (MariaDB 10.3+)
-- ============================================================

USE unicentapos;

-- ─────────────────────────────────────────────────────────────
-- 1. STAFF: capabilities (JSON array) + location_name
--    capabilities: e.g. ["can_approve_requisitions","can_manage_staff"]
--    location_name: e.g. 'Kitchen', 'Rooftop', 'Barista'
-- ─────────────────────────────────────────────────────────────
ALTER TABLE yunix_staff
  ADD COLUMN IF NOT EXISTS capabilities  JSON         NULL,
  ADD COLUMN IF NOT EXISTS location_name VARCHAR(100) NULL;

-- Seed default capabilities based on existing roles
UPDATE yunix_staff SET capabilities = '["can_log_waste"]'
  WHERE role = 'kitchen' AND capabilities IS NULL;

UPDATE yunix_staff SET capabilities = '["can_approve_requisitions","can_manage_inventory","can_draft_po","can_view_variance"]'
  WHERE role = 'store' AND capabilities IS NULL;

UPDATE yunix_staff SET capabilities = '["can_approve_requisitions","can_manage_inventory","can_draft_po","can_approve_payrun","can_log_waste","can_manage_staff","can_view_variance"]'
  WHERE role = 'manager' AND capabilities IS NULL;

-- ─────────────────────────────────────────────────────────────
-- 2. REQUISITIONS: requester_location
-- ─────────────────────────────────────────────────────────────
ALTER TABLE store_requisitions
  ADD COLUMN IF NOT EXISTS requester_location VARCHAR(100) NULL;

-- ─────────────────────────────────────────────────────────────
-- 3. STORE INVENTORY: lead_time_days (how many days stock needed in advance)
-- ─────────────────────────────────────────────────────────────
ALTER TABLE store_inventory
  ADD COLUMN IF NOT EXISTS lead_time_days INT NULL DEFAULT NULL;

-- ─────────────────────────────────────────────────────────────
-- 4. COST HISTORY
--    Logs each time cost_per_unit changes on a delivery receive.
--    Powers the "Inflation Heatmap" widget on the Variance screen.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS store_cost_history (
  id                VARCHAR(36)    NOT NULL,
  inventory_item_id VARCHAR(36)    NOT NULL,
  old_cost          DECIMAL(12,2)  NULL,
  new_cost          DECIMAL(12,2)  NOT NULL,
  changed_by        VARCHAR(100)   NULL,
  changed_at        DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  CONSTRAINT fk_costhist_item
    FOREIGN KEY (inventory_item_id) REFERENCES store_inventory(id)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- 5. PAY RUNS
--    Header record for a daily payment session.
--    approval_token: UUID used in WhatsApp deep link for owner review.
--    status: Draft → Submitted → Approved → Disbursed
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS store_pay_runs (
  id              VARCHAR(36)   NOT NULL,
  run_date        DATE          NOT NULL,
  status          ENUM('Draft','Submitted','Approved','Disbursed') NOT NULL DEFAULT 'Draft',
  approval_token  VARCHAR(36)   NOT NULL,
  total_requested DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  total_approved  DECIMAL(12,2) NOT NULL DEFAULT 0.00,
  created_by      VARCHAR(100)  NULL,
  notes           TEXT          NULL,
  created_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_payrun_token (approval_token)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─────────────────────────────────────────────────────────────
-- 6. PAY RUN DETAILS
--    One row per supplier in a pay run.
--    requested_amount: what is owed (from ledger balance)
--    approved_amount: what owner chooses to pay (partial ok)
--    status: Included (will pay) | Postponed (skip this run) | Paid (disbursed)
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS store_pay_run_details (
  id               VARCHAR(36)   NOT NULL,
  pay_run_id       VARCHAR(36)   NOT NULL,
  supplier_id      VARCHAR(36)   NOT NULL,
  requested_amount DECIMAL(12,2) NOT NULL,
  approved_amount  DECIMAL(12,2) NOT NULL,
  status           ENUM('Included','Postponed','Paid') NOT NULL DEFAULT 'Included',
  notes            VARCHAR(500)  NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_detail_run_supplier (pay_run_id, supplier_id),
  CONSTRAINT fk_detail_payrun
    FOREIGN KEY (pay_run_id) REFERENCES store_pay_runs(id)
    ON DELETE CASCADE,
  CONSTRAINT fk_detail_supplier
    FOREIGN KEY (supplier_id) REFERENCES store_suppliers(id)
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
