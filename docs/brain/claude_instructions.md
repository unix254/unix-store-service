# Claude Implementation Instructions: Phase 12

> **Before starting:** Read `docs-active/claude_feedback.md` fully to understand all previous work. Then implement the milestone below, updating `claude_feedback.md` with a new ## Milestone 14 section when done.

---

## MILESTONE 14 — Refine "New Item Request" Approval Workflow

### Problem Context
In Milestone 13, we added the ability for the Kitchen to request items not currently in stock (New Item Requests). These appear in the Requisitions screen with a `🆕 NEW ITEM` badge.
Currently, when a Storekeeper clicks "Approve" on a new item request, it opens the standard `_IssueDialog` asking how much to issue. This is incorrect. The purpose of a new item request is to prompt the storekeeper to **add the item to the inventory system** (with 0 stock and a configured minimum level) so that it automatically gets picked up in the next procurement run.

We need a streamlined, one-click workflow to convert a New Item Request directly into a new Inventory Item and close the requisition.

### Required Workflow Changes

**File:** `flutter_app/lib/screens/store/requisition_approval.dart`

When the user clicks "Approve" on a requisition where `isNewItemRequest` is `true`:
1. **DO NOT** show the standard `_IssueDialog`.
2. **DO** show a custom `_AddNewItemFromRequestDialog` right there on the requisitions screen.

### The `_AddNewItemFromRequestDialog` Design

This dialog should act as a mini "Add Inventory Item" form, pre-filled with the data from the kitchen's request. 

**Fields to include (same as `inventory_screen.dart`'s add item dialog):**
- **Item Name:** Pre-filled with `requisition.newItemName` (from the notes string). Editable.
- **Category:** Dropdown (same categories as inventory: `Meat`, `Vegetables`, `Dairy`, `Dry Goods`, `Beverages`, `Cleaning`, `Packaging`, `Other`). Required.
- **Unit of Measure:** Pre-filled with the unit from the request's notes (or `requisition.unitOfMeasure` if available), but allowing the user to select from the standard units list if they want to correct it. Required.
- **Reorder Level (Min Level):** Numeric input. Required. Explain in a helper text: *"Set this so the system triggers a purchase in the next procurement run."*
- **Reorder Quantity (Target Procure Qty):** Numeric input. Required.
- **Current Stock:** Hardcoded/locked to `0` (or hidden and defaults to 0). This item is out of stock; that's why they requested it.

**Action Buttons:**
- "Cancel" 
- "Add to Inventory & Approve" (Teal/Green button)

### Submit Action Sequence

When the storekeeper submits the `_AddNewItemFromRequestDialog`:
1. Show a loading state (spinner).
2. **Call API 1:** `ApiService.instance.addInventory(...)` passing the filled details (Current stock = 0).
3. **Call API 2:** `ApiService.instance.issueRequisition(...)` for this requisition. 
   - Since `inventory_item_id` is null on the requisition, the backend automatically skips stock checking/deduction (this was built in M13).
   - Pass `issuedBy: staff.name`, and `notes: 'Added to inventory as new item'`.
   - Leave `issuedQuantity` as null or pass the original requested quantity (the backend defaults to original quantity, which is fine since deduction is skipped).
4. **On Success:** Close the dialog, show a `showSuccess` snackbar ("Item added to inventory and request approved"), and refresh the requisitions list.
5. **On Error:** Show the error message in the dialog or as a snackbar and stop loading.

### Code Organization

- You don't need to change `api.dart` or any backend routes for this; the backend already supports `POST /api/inventory` (add inventory) and `PATCH /api/requisitions/:id/issue` (issue requisition).
- Simply import `InventoryItem` and ensure you can make the `addInventory` POST call from the screen.
- Ensure the dialog looks clean and has a maximum width of `400` so it looks good on tablets and web, consistent with other dialogs in the app.

---

### Quality Standards
- Do not break the standard requisition approval flow. Regular requisitions must still open the `_IssueDialog`.
- Ensure robust error handling if the `addInventory` call fails (the requisition should NOT be marked as issued if adding to inventory fails).
- After finishing, document the changes in `docs-active/claude_feedback.md` under `# Milestone 14`.
