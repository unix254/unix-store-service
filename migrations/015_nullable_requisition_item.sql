-- Migration 015: Allow NULL inventory_item_id on unix_requisitions.
-- A NULL item_id signals a "New Item Request" from the kitchen — the requested
-- item does not yet exist in the inventory. The item name and details are encoded
-- in the notes column using the prefix: [NEW ITEM REQUEST] Name: ... | Qty: ... | Notes: ...
-- The store team reviews these and manually adds the item to inventory if approved.

USE unicentapos;

ALTER TABLE unix_requisitions
  MODIFY COLUMN inventory_item_id VARCHAR(36) NULL;
