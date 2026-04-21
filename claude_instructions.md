# Milestone: Procurement Item Removal / Postponement

**Context & Business Goal:**
When the system generates a suggested procurement list (items that have fallen below their reorder thresholds), it currently allows the user to adjust the suggested quantities. However, sometimes the user doesn't want to order a specific suggested item right now (e.g. postponing ordering Cheese). Currently, there's no way to explicitly drop or remove an item from the draft procurement list before finalizing the order. 
We need a way to explicitly "remove" or "postpone" an item from this draft list, similar to the exclusion functionality that already exists in the Payruns screen.

**Instructions for Claude (The Engineer):**
1. **Locate the Procurement Screen**: Find the screen/widget in the Flutter app where the suggested procurement list is displayed and finalized (likely `procurement_screen.dart` or similar).
2. **Review Existing Pattern**: Check how item removal/exclusion is handled in the Payruns screen to maintain UI consistency across the ecosystem.
3. **Implement Removal UI**: Add an intuitive UI element (e.g., a trailing minus/delete icon button, a swipe-to-dismiss action, or an "exclude" checkbox) to the suggested procurement item cards. 
4. **Implement State Management**: When the user clicks remove/postpone on an item, it should be removed from the active draft list so that it is NOT submitted to the backend, NOT saved to the database, and NOT included in the final WhatsApp/PDF sent to the supplier.
5. **Feedback Loop**: Please execute the changes and log your architectural choices and completion details natively into `claude_feedback.md`.
