# Supabase Setup

## 1. Create Tables

Open the Supabase project dashboard:

```text
https://dkabosehgvldiwtdmvxh.supabase.co
```

Then go to:

```text
SQL Editor -> New query
```

Copy and run:

```text
new_hygportal/supabase/migrations/0001_initial_schema.sql
```

## 2. Seed Core Data

After the schema succeeds, open another SQL query and run:

```text
new_hygportal/supabase/seed/0001_core_seed.sql
```

This creates:

```text
functions
positions
request types
approval level routes
```

## 3. Apply RLS Policies

Run:

```text
new_hygportal/supabase/migrations/0002_rls_policies.sql
```

This lets the mobile app read the logged-in user's own `user_profiles`, employee record, assignment, and reference data.

## 4. Add Request Submission Functions

Run:

```text
new_hygportal/supabase/migrations/0003_submit_time_request.sql
```

This creates the first request RPC used by the mobile app:

```text
submit_time_request
```

## 5. Link A Test Login To An Employee

After creating a test account from the mobile app, create one employee and one user profile linked to the Supabase Auth user.

Use this helper template:

```text
new_hygportal/supabase/seed/0002_test_employee_link.sql
```

Before running it, replace:

```text
CHANGE_THIS_TO_YOUR_LOGIN_EMAIL
```

with the email you used in the mobile app.

The app currently shows:

```text
Database setup needed
```

when tables do not exist.

It shows:

```text
Profile not linked
```

when the login exists but has no `user_profiles` row yet.

## 6. Seed Test Approvers

Run:

```text
new_hygportal/supabase/seed/0003_test_approvers.sql
```

This creates:

```text
TEST-SM-0001 = Level 2 Store Manager for Test Store
TEST-CM-0001 = Level 4 Cluster Manager for Test Cluster
```

After this, a new overtime request from `TEST-0001` should create:

```text
Step 1 pending -> Test Store Manager
Step 2 waiting -> Test Cluster Manager
```

## 7. Add Approval Actions

Run:

```text
new_hygportal/supabase/migrations/0004_approval_actions.sql
```

This creates:

```text
get_my_pending_approvals
decide_approval_step
```

## 8. Link Store Manager Login

Create this account in the mobile app and confirm the email:

```text
test.store.manager@example.com
```

Then run:

```text
new_hygportal/supabase/seed/0004_link_test_store_manager.sql
```

After that, logging in as the Store Manager should show pending approvals for Step 1.

## 9. Add Employee Request History

Run:

```text
new_hygportal/supabase/migrations/0005_my_requests.sql
```

This creates:

```text
get_my_requests
```

## 10. Add Dashboard Summary

Run:

```text
new_hygportal/supabase/migrations/0006_dashboard_summary.sql
```

This creates:

```text
get_my_dashboard_summary
```

## 11. Add Leave Submission

Run:

```text
new_hygportal/supabase/migrations/0007_submit_leave_request.sql
```

This creates:

```text
submit_leave_request
```

## 12. Add ESARF Schedule Fields

Run:

```text
new_hygportal/supabase/migrations/0008_esarf_fields.sql
```

This adds Flask ESARF-style fields to time requests:

```text
time_schedule
day_off
payroll_class
transaction_type
```
