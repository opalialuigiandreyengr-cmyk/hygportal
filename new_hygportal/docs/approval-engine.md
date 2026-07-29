# Approval Engine

The approval engine is the main upgrade from the Flask app.

## Rule Summary

```text
Overtime     = 2 approvers
Offset Earn  = 2 approvers
Use Offset   = 1 approver + credit validation
Leave        = 1 approver
```

The approver must match:

```text
authority level
function
scope
active assignment date
not the requester
not already used in the same request
```

## Base Approval Matrix

```text
Requester Level | Step 1 Approver        | Step 2 Approver
Level 1         | Level 2 Store Manager  | Level 4 Cluster Manager
Level 2         | Level 4 Cluster Manager| Level 5 Area Manager
Level 3         | Level 6 Ops Manager    | Level 7 Ops Director
Level 4         | Level 5 Area Manager   | Level 6 Ops Manager
Level 5         | Level 6 Ops Manager    | Level 7 Ops Director
Level 6         | Level 7 Ops Director   | Level 8 GM
Level 7         | Level 8 GM             | -
Level 8         | Admin fallback         | -
```

Request type decides how many steps are used.

## Scope Matching

```text
Level 2 -> same store
Level 3 -> same department / company
Level 4 -> same cluster
Level 5 -> same area
Level 6 -> same company
Level 7 -> same company
Level 8 -> same company or group
```

## Missing Approver Escalation

If a required approver is missing, the system escalates to the next available higher approver.

Example:

```text
Crew files overtime.
Required: Level 2, then Level 4.

No Level 2 Store Manager exists.

Resolved:
Step 1: Level 4 Cluster Manager
Step 2: Level 5 Area Manager
```

If no approver is found up to Level 8, create an admin fallback step.

## Duplicate Prevention

The same employee cannot approve the same request twice.

If Step 1 and Step 2 resolve to the same employee, Step 2 escalates upward.

## Self Approval Prevention

The requester cannot approve their own request.

If the resolver finds the requester as approver, it skips and escalates upward.

## Submission Flow

```text
1. Get requester's active employee assignment
2. Read requester's authority level from position
3. Read request type settings
4. Get approval route rows for requester level
5. Use only N steps based on request_type.approval_count
6. Resolve actual approver for each step
7. Create request_approval_steps
8. Mark first step as pending
9. Mark later steps as waiting
10. Notify first approver
```

## Approve Flow

```text
1. Check current user owns the pending approval step
2. Mark current step as approved
3. Find next waiting step
4. If next step exists, mark it pending and notify approver
5. If no next step exists, mark request approved
6. Apply final side effects
```

Final side effects:

```text
offset_earn -> add offset hours
use_offset  -> deduct offset hours
leave       -> mark approved
overtime    -> mark approved
```

## Reject Flow

```text
1. Check current user owns the pending approval step
2. Require rejection reason
3. Mark step rejected
4. Mark request rejected
5. Cancel remaining waiting steps
6. Notify requester
```

## Use Offset Validation

Before submission:

```text
if requested_hours > current_offset_balance:
    block submission
```

After final approval:

```text
deduct requested_hours
create offset transaction
```

