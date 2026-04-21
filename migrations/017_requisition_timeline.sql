-- Migration 017: Immutable requisition audit timeline.
-- Stores both system-generated status-change events and user comments.
-- No UPDATE or DELETE permitted on this table by design.

CREATE TABLE IF NOT EXISTS store_requisition_timeline (
  id              VARCHAR(36)                      NOT NULL,
  requisition_id  VARCHAR(36)                      NOT NULL,
  entry_type      ENUM('system', 'comment')        NOT NULL DEFAULT 'system',
  actor_name      VARCHAR(100)                     NULL,
  message         TEXT                             NOT NULL,
  created_at      DATETIME                         NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  INDEX idx_timeline_req (requisition_id),
  CONSTRAINT fk_timeline_req
    FOREIGN KEY (requisition_id) REFERENCES store_requisitions(id)
    ON DELETE CASCADE
);
