# TECHNICAL SPECIFICATION (MVP)

## 1. STACK
- **Backend**: Node.js (Express) running in Docker.
- **Database**: Local MariaDB (Existing `unicentapos` database).
- **Frontend**: Flutter Web (PWA) for a premium, cross-platform feel.
- **Reporting**: Metabase for cross-table "Sales vs. Issues" analysis.

## 2. DATABASE ARCHITECTURE
- **Namespace**: All new tables MUST use the `unix_` prefix.
- **Integration**: The `unix-store-service` will use SQL JOINs to passively read from uniCenta's `ticketlines` and `products`. 
- **Safety**: Strict Read-Only rule for existing uniCenta database tables. No `INSERT` or `UPDATE` operations are permitted on legacy tables. This guarantees the POS will not crash or experience Java errors due to our sidecar.

## 3. PROPOSED SCHEMAS (AGENT TO REFINE)
- `unix_store_inventory`: Bulk stock levels, lead times, and units mapping.
- `unix_suppliers`: Supplier profiles, locations, and scheduled payment targets (e.g., 'Monday').
- `unix_supplier_ledger`: Tracks running balance. `PURCHASE` (increases debt) and `PAYMENT` (decreases debt).
- `unix_requisitions`: Internal movement logs (Store -> Kitchen/Barista). Includes a `purpose` column (e.g., "Sales", "Staff Meal", "Wastage").
- `unix_yield_config`: User-configurable approximation table. Maps a `unix_store_inventory` item to a defined Number of Portions. Maps `unicenta_product_id` to Portions Consumed.