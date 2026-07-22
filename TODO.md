# Task: Add Approver Column to All Requests Table

## Steps

- [x] Step 0: Understand the codebase and create plan
- [x] Step 1: Add `approverNames` getter to `AdminRequestItem` (models.dart)
- [x] Step 2: Add "Approver" column to `_buildColumns()` for all 3 tabs (requests_screen.dart)
- [x] Step 3: Add approver cell to `_buildRow()` for all 3 tabs (requests_screen.dart)
- [x] Step 4: Update search in `_itemsForTab()` to include approver names (requests_screen.dart)
- [x] Step 5: Create `_approverCell()` helper method

## Files to Edit

1. `lib/src/models.dart` - Add `approverNames` getter ✅
2. `lib/src/requests_screen.dart` - Update table columns, rows, Excel export, and search
