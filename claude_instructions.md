# Phase 9: App Customization, Authentication Revamp & Go-Live Architecture

## Overview
As the application prepares for wider deployment across multiple clients with different operational models, we need a flexible SaaS-like architecture. This phase introduces dynamic feature toggling, a more robust POS login experience, and a "Super Admin" toolkit to configure the client and seamlessly transition them from training/boarding to a live "opening day" state.

Please implement the following four major features:

### 1. Dynamic Module Toggles (Feature Flags)
* **Objective:** Allow the app to adapt its UI based on the client's preferred workflow. For example, a Fast Casual cafe might use `Procurement` but hide `Purchase Orders`.
* **Action (Backend):** Create a robust way to store feature toggles in the database (e.g., a `unix_feature_flags` table with key-value pairs like `feature_key="purchase_orders", enabled=true`). Create endpoints to `GET` and `PUT` these flags.
* **Action (Frontend):** In `store_shell.dart`, fetch these settings on load. Use them to conditionally render sidebar navigation items (Hide the `Purchase Orders` button if it is disabled, etc.).

### 2. Name Grid Login (POS Standard)
* **Objective:** Move away from a bare UI that only shows a PIN pad to prevent staff from accidentally locking each other out or logging into the wrong account.
* **Action:** Redesign the login screen. It should first display a visual grid/list of active staff members (potentially grouped by category or role). 
* **Action:** The user taps their name, and *only then* does the 4-digit PIN pad overlay appear to authenticate that specific user.

### 3. The Super Admin "Backdoor"
* **Objective:** Create a secure entry point for System Maintainers/Engineers without cluttering the staff login grid.
* **Action:** Hide a gesture on the new Login Screen (e.g., tapping the company logo 5 times rapidly or long-pressing it for 3 seconds).
* **Action:** Triggering the gesture should slide up a hidden "Super Admin Login" modal that requires a strong Master Password or Master Username/Password (not a 4 digit PIN, but a dedicated env-configured or DB-stored admin credential).

### 4. Super Admin Dashboard & "Go-Live" Wipe
* **Objective:** Provide a dashboard exclusively for the Super Admin to configure the client's app and handle onboarding resets.
* **Action (UI):** Once the Super Admin logs in via the backdoor, they should see a separate dashboard screen.
* **Action (Settings Tab):** Provide a UI in this dashboard to toggle the Feature Flags (from Step 1) on/off.
* **Action (Database Reset Tab):** Add a highly restricted, red **"Clear Transactions & Go Live"** button.
* **Action (Backend Wipe Script):** Build a new backend endpoint for wiping *only transactional data*. 
  * **Keep (Master Data):** `products`, `categories`, `unix_suppliers`, `unix_business_settings`, `people`, `roles`, etc.
  * **Wipe (Transactional Data):** ONLY `unix_` prefixed transactional tables such as `unix_pay_runs`, `unix_pay_run_details`, `unix_supplier_ledger`, `unix_requisitions`. Do NOT wipe or modify ANY core Unicenta tables (like `receipts`, `tickets`, `stockdiary`, etc).
  * *Note:* You must carefully handle foreign key constraints during the wipe, ensuring that opening the doors on "Go-Live" day starts the client with a clean slate for the store system.

## Goals for Claude
Please internalize this architecture. Your implementation must keep the codebase unified (we do not want multiple forks) but highly configurable via the database. Ensure the "Go Live Wipe" script is heavily audited and STRICTLY restricted to only `unix_` transactional tables.
