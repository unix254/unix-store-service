# Milestone 21: Operational UI Polish & Filters

Claude, great work on Phase 1. Before we move on to building out the Metabase dashboards and PDF generators, we have a few UX and operational improvements to implement based on user feedback.

Please knock out the following tasks in the Flutter App (and backend where necessary):

## Task 1: Requisitions Auto-Refresh & Error Handling
1. **Reduce Polling:** In the Requisitions screen (both Store and Kitchen sides if applicable), change the auto-refresh `Timer.periodic` from 30 seconds to 30 minutes to reduce server load (requisitions are infrequent, so 30m is plenty).
2. **Graceful Error Handling:** Currently, if the device briefly loses network during a background poll, it throws a red `ClientException failed to fetch uri` error that makes the app look broken. 
3. **Fix:** Wrap the background fetch in a try-catch. If it fails due to network/socket issues, fail silently (do not disrupt the UI). Optionally, show a subtle "Offline" icon or muted snackbar, but absolutely no red error screens for background polling failures.

## Task 2: Supplier List UI Fix (Large Screens)
1. **The Bug:** On large screens (desktop/tablet), the middle column/tab of the Supplier list showing the Supplier Name crushes the text into a vertical, single-letter column if the supplier has the "Internal" tag. (It tries to wrap awkwardly instead of taking available space).
2. **The Fix:** Inspect the `Row` or layout widget rendering the Supplier Name and the "Internal" badge. Use `Expanded` or `Flexible` with `TextOverflow.ellipsis` on the name text so it takes up the remaining space gracefully without shrinking to zero width and wrapping vertically.

## Task 3: Expense Accounts / Supplier Statement Filters
1. **The Requirement:** Users need to be able to filter the Ledger/Statement entries by date range, especially as the list of entries grows long over time. This is primarily for expense accounts, but applies to the general supplier ledger view.
2. **Backend Update:** Check `src/routes/suppliers.js` (`GET /api/suppliers/:id/ledger`). If it doesn't already, modify it to accept optional `?from=YYYY-MM-DD&to=YYYY-MM-DD` query parameters and filter the SQL accordingly.
3. **Frontend Update:** Add a Date Range filter UI (similar to what you just built for the Variance screen) to the statement/ledger view. Let the user select "This Month", "Last Month", "Custom", etc., and reload the ledger entries based on the selection.
4. **WhatsApp Integration:** Ensure that if a filter is active, the "Send Statement to WhatsApp" feature respects the filtered dates (i.e., it only sends the entries visible on the screen, and maybe updates the message header to say "Statement for period: [Dates]").

## Task 4: Variance Print Placeholder
1. On the **Variance Screen** header, add a "Print Report" or "Download PDF" icon button (maybe next to the refresh button).
2. Tapping it should do nothing but show a premium YUNIX-styled Snackbar or Dialog saying "PDF Report generation coming soon." (We will implement the actual PDF engine in a later milestone).

## Deliverables
Execute these changes in the codebase. When complete, log your implementation details into `C:\PROJECTS\unix-store-service\claude_feedback.md`.
