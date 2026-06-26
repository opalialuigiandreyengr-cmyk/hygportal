-- New HYG Portal initial Supabase schema draft.
-- Existing Flask app stays untouched and is only used as reference.

create extension if not exists "pgcrypto";

create table public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.areas (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.clusters (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  area_id uuid not null references public.areas(id),
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.stores (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  area_id uuid not null references public.areas(id),
  cluster_id uuid not null references public.clusters(id),
  name text not null,
  code text,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.functions (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  code text unique
);

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  function_id uuid references public.functions(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.positions (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  authority_level int not null check (authority_level between 1 and 8),
  default_function_id uuid references public.functions(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.employees (
  id uuid primary key default gen_random_uuid(),
  employee_no text unique,
  first_name text not null,
  middle_name text,
  last_name text not null,
  suffix text,
  birth_date date,
  gender text,
  civil_status text,
  email text,
  phone text,
  photo_url text,
  employment_status text not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  employee_id uuid unique references public.employees(id),
  app_role text not null default 'employee',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint user_profiles_app_role_check check (
    app_role in ('employee', 'hr', 'admin', 'super_admin')
  )
);

create table public.employee_assignments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id),
  company_id uuid not null references public.companies(id),
  area_id uuid references public.areas(id),
  cluster_id uuid references public.clusters(id),
  store_id uuid references public.stores(id),
  department_id uuid references public.departments(id),
  position_id uuid not null references public.positions(id),
  function_id uuid not null references public.functions(id),
  effective_from date not null,
  effective_to date,
  is_primary boolean not null default true,
  created_at timestamptz not null default now(),
  constraint employee_assignments_dates_check check (
    effective_to is null or effective_to >= effective_from
  )
);

create table public.authority_assignments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id),
  function_id uuid not null references public.functions(id),
  authority_level int not null check (authority_level between 1 and 8),
  company_id uuid references public.companies(id),
  area_id uuid references public.areas(id),
  cluster_id uuid references public.clusters(id),
  store_id uuid references public.stores(id),
  department_id uuid references public.departments(id),
  effective_from date not null,
  effective_to date,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint authority_assignments_dates_check check (
    effective_to is null or effective_to >= effective_from
  )
);

create table public.request_types (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  required_function_id uuid not null references public.functions(id),
  approval_count int not null check (approval_count between 1 and 2),
  requires_offset_credit_check boolean not null default false,
  affects_offset_balance text not null default 'none',
  is_active boolean not null default true,
  constraint request_types_offset_effect_check check (
    affects_offset_balance in ('none', 'earn', 'use')
  )
);

create table public.approval_level_routes (
  id uuid primary key default gen_random_uuid(),
  department_id uuid references public.departments(id),
  requester_level int not null check (requester_level between 1 and 8),
  step_order int not null check (step_order between 1 and 2),
  approver_level int not null check (approver_level between 1 and 8),
  unique (department_id, requester_level, step_order)
);

create table public.requests (
  id uuid primary key default gen_random_uuid(),
  request_type_id uuid not null references public.request_types(id),
  submitted_by_employee_id uuid not null references public.employees(id),
  submitted_by_user_id uuid references public.user_profiles(id),
  company_id uuid not null references public.companies(id),
  area_id uuid references public.areas(id),
  cluster_id uuid references public.clusters(id),
  store_id uuid references public.stores(id),
  requester_position_id uuid not null references public.positions(id),
  requester_level int not null check (requester_level between 1 and 8),
  status text not null default 'pending',
  submitted_at timestamptz not null default now(),
  final_approved_at timestamptz,
  rejected_at timestamptz,
  rejected_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint requests_status_check check (
    status in ('pending', 'approved', 'rejected', 'cancelled', 'needs_admin_review')
  )
);

create table public.request_approval_steps (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests(id) on delete cascade,
  step_order int not null,
  required_function_id uuid not null references public.functions(id),
  required_level int not null check (required_level between 1 and 8),
  assigned_approver_employee_id uuid references public.employees(id),
  assigned_approver_user_id uuid references public.user_profiles(id),
  status text not null default 'waiting',
  acted_at timestamptz,
  remarks text,
  skipped_reason text,
  created_at timestamptz not null default now(),
  unique (request_id, step_order),
  constraint request_approval_steps_status_check check (
    status in ('waiting', 'pending', 'approved', 'rejected', 'skipped', 'cancelled', 'admin_fallback')
  )
);

create table public.time_request_details (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.requests(id) on delete cascade,
  date_from date not null,
  date_to date not null,
  time_from time not null,
  time_to time not null,
  total_hours numeric(8, 2) not null check (total_hours > 0),
  reason text,
  constraint time_request_details_dates_check check (date_to >= date_from)
);

create table public.leave_request_details (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.requests(id) on delete cascade,
  leave_type text,
  leave_category text,
  start_date date not null,
  end_date date not null,
  total_days numeric(8, 2),
  reason text,
  constraint leave_request_details_dates_check check (end_date >= start_date)
);

create table public.offset_balances (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null unique references public.employees(id),
  balance_hours numeric(8, 2) not null default 0,
  updated_at timestamptz not null default now()
);

create table public.offset_transactions (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id),
  request_id uuid references public.requests(id),
  transaction_type text not null,
  hours numeric(8, 2) not null,
  balance_after numeric(8, 2) not null,
  created_at timestamptz not null default now(),
  constraint offset_transactions_type_check check (
    transaction_type in ('earn', 'use', 'adjustment')
  )
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid references public.employees(id),
  user_profile_id uuid references public.user_profiles(id),
  title text not null,
  message text not null,
  link_type text,
  link_id uuid,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_profile_id uuid references public.user_profiles(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb,
  created_at timestamptz not null default now()
);

create index idx_employee_assignments_employee_active
  on public.employee_assignments(employee_id, effective_from, effective_to);

create index idx_authority_assignments_lookup
  on public.authority_assignments(function_id, authority_level, company_id, area_id, cluster_id, store_id);

create index idx_requests_submitter
  on public.requests(submitted_by_employee_id, status, submitted_at desc);

create index idx_request_approval_steps_approver
  on public.request_approval_steps(assigned_approver_employee_id, status, created_at desc);

create index idx_notifications_user_read
  on public.notifications(user_profile_id, is_read, created_at desc);
