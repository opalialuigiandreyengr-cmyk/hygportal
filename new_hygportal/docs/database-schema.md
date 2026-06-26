# Database Schema Draft

This is the MVP Supabase/Postgres schema draft.

## Organization

```text
companies
- id uuid primary key
- name text not null
- code text unique
- is_active boolean default true
- created_at timestamptz

areas
- id uuid primary key
- company_id uuid references companies(id)
- name text not null
- is_active boolean default true
- created_at timestamptz

clusters
- id uuid primary key
- company_id uuid references companies(id)
- area_id uuid references areas(id)
- name text not null
- is_active boolean default true
- created_at timestamptz

stores
- id uuid primary key
- company_id uuid references companies(id)
- area_id uuid references areas(id)
- cluster_id uuid references clusters(id)
- name text not null
- code text
- address text
- is_active boolean default true
- created_at timestamptz
```

## People And Access

```text
functions
- id uuid primary key
- name text not null unique
- code text unique

positions
- id uuid primary key
- name text not null unique
- authority_level int not null
- default_function_id uuid references functions(id)
- is_active boolean default true

employees
- id uuid primary key
- employee_no text unique
- first_name text not null
- middle_name text
- last_name text not null
- suffix text
- birth_date date
- gender text
- civil_status text
- email text
- phone text
- photo_url text
- employment_status text default 'active'
- created_at timestamptz
- updated_at timestamptz

user_profiles
- id uuid primary key
- auth_user_id uuid references auth.users(id)
- employee_id uuid references employees(id)
- app_role text default 'employee'
- is_active boolean default true
- created_at timestamptz
```

`app_role` controls app access only. Approval authority comes from `authority_assignments`.

## Assignments

```text
employee_assignments
- id uuid primary key
- employee_id uuid references employees(id)
- company_id uuid references companies(id)
- area_id uuid references areas(id)
- cluster_id uuid references clusters(id)
- store_id uuid references stores(id)
- department_id uuid nullable
- position_id uuid references positions(id)
- function_id uuid references functions(id)
- effective_from date not null
- effective_to date
- is_primary boolean default true
- created_at timestamptz

authority_assignments
- id uuid primary key
- employee_id uuid references employees(id)
- function_id uuid references functions(id)
- authority_level int not null
- company_id uuid references companies(id)
- area_id uuid references areas(id)
- cluster_id uuid references clusters(id)
- store_id uuid references stores(id)
- department_id uuid nullable
- effective_from date not null
- effective_to date
- is_active boolean default true
- created_at timestamptz
```

Transfers should close the old assignment by setting `effective_to`, then create a new assignment.

## Request Configuration

```text
request_types
- id uuid primary key
- code text not null unique
- name text not null
- required_function_id uuid references functions(id)
- approval_count int not null
- requires_offset_credit_check boolean default false
- affects_offset_balance text
- is_active boolean default true

approval_level_routes
- id uuid primary key
- requester_level int not null
- step_order int not null
- approver_level int not null
```

Seed request types:

```text
overtime      approval_count 2   affects_offset_balance none
offset_earn   approval_count 2   affects_offset_balance earn
use_offset    approval_count 1   affects_offset_balance use
leave         approval_count 1   affects_offset_balance none
```

Seed approval routes:

```text
1 -> step 1 level 2
1 -> step 2 level 4
2 -> step 1 level 4
2 -> step 2 level 5
3 -> step 1 level 6
3 -> step 2 level 7
4 -> step 1 level 5
4 -> step 2 level 6
5 -> step 1 level 6
5 -> step 2 level 7
6 -> step 1 level 7
6 -> step 2 level 8
7 -> step 1 level 8
```

## Requests

```text
requests
- id uuid primary key
- request_type_id uuid references request_types(id)
- submitted_by_employee_id uuid references employees(id)
- submitted_by_user_id uuid references user_profiles(id)
- company_id uuid references companies(id)
- area_id uuid references areas(id)
- cluster_id uuid references clusters(id)
- store_id uuid references stores(id)
- requester_position_id uuid references positions(id)
- requester_level int not null
- status text default 'pending'
- submitted_at timestamptz
- final_approved_at timestamptz
- rejected_at timestamptz
- rejected_reason text
- created_at timestamptz
- updated_at timestamptz

request_approval_steps
- id uuid primary key
- request_id uuid references requests(id)
- step_order int not null
- required_function_id uuid references functions(id)
- required_level int not null
- assigned_approver_employee_id uuid references employees(id)
- assigned_approver_user_id uuid references user_profiles(id)
- status text default 'waiting'
- acted_at timestamptz
- remarks text
- skipped_reason text
- created_at timestamptz
```

Request statuses:

```text
pending
approved
rejected
cancelled
needs_admin_review
```

Approval step statuses:

```text
waiting
pending
approved
rejected
skipped
cancelled
admin_fallback
```

## Request Details

```text
time_request_details
- id uuid primary key
- request_id uuid references requests(id)
- date_from date not null
- date_to date not null
- time_from time not null
- time_to time not null
- total_hours numeric not null
- reason text

leave_request_details
- id uuid primary key
- request_id uuid references requests(id)
- leave_type text
- leave_category text
- start_date date not null
- end_date date not null
- total_days numeric
- reason text
```

`time_request_details` is used by overtime, offset earn, and use offset.

## Balances

```text
offset_balances
- id uuid primary key
- employee_id uuid references employees(id)
- balance_hours numeric default 0
- updated_at timestamptz

offset_transactions
- id uuid primary key
- employee_id uuid references employees(id)
- request_id uuid references requests(id)
- transaction_type text
- hours numeric not null
- balance_after numeric not null
- created_at timestamptz
```

Offset transaction types:

```text
earn
use
adjustment
```

## Notifications And Audit

```text
notifications
- id uuid primary key
- employee_id uuid references employees(id)
- user_profile_id uuid references user_profiles(id)
- title text not null
- message text not null
- link_type text
- link_id uuid
- is_read boolean default false
- created_at timestamptz

audit_logs
- id uuid primary key
- actor_user_profile_id uuid references user_profiles(id)
- action text not null
- entity_type text not null
- entity_id uuid
- metadata jsonb
- created_at timestamptz
```

