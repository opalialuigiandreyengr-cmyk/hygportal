-- Core seed data for the new HYG Portal.

insert into public.functions (name, code) values
  ('Operations', 'operations'),
  ('Store', 'store'),
  ('HR', 'hr'),
  ('Payroll', 'payroll'),
  ('Finance', 'finance'),
  ('IT', 'it'),
  ('Purchasing', 'purchasing'),
  ('Logistics', 'logistics'),
  ('Maintenance', 'maintenance'),
  ('Admin', 'admin')
on conflict (code) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Crew', 1, id from public.functions where code = 'store'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Staff', 1, id from public.functions where code = 'operations'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Assistant', 1, id from public.functions where code = 'operations'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Officer', 2, id from public.functions where code = 'operations'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Specialist', 2, id from public.functions where code = 'operations'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Analyst', 2, id from public.functions where code = 'operations'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Coordinator', 2, id from public.functions where code = 'operations'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Team Leader', 2, id from public.functions where code = 'operations'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Supervisor', 2, id from public.functions where code = 'operations'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Store Manager', 3, id from public.functions where code = 'store'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Department Manager', 3, id from public.functions where code = 'operations'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Cluster Manager', 4, id from public.functions where code = 'operations'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Area Manager', 5, id from public.functions where code = 'operations'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Operations Manager', 5, id from public.functions where code = 'operations'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Auditor', 2, id from public.functions where code = 'finance'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Training Officer', 2, id from public.functions where code = 'hr'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Director', 7, id from public.functions where code = 'operations'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Operations Director', 7, id from public.functions where code = 'operations'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'General Manager', 8, id from public.functions where code = 'operations'
on conflict (name) do nothing;

insert into public.positions (name, authority_level, default_function_id)
select 'Finance Director', 8, id from public.functions where code = 'finance'
on conflict (name) do nothing;

insert into public.request_types (
  code,
  name,
  required_function_id,
  approval_count,
  requires_offset_credit_check,
  affects_offset_balance
)
select 'overtime', 'Overtime', id, 2, false, 'none'
from public.functions where code = 'operations'
on conflict (code) do nothing;

insert into public.request_types (
  code,
  name,
  required_function_id,
  approval_count,
  requires_offset_credit_check,
  affects_offset_balance
)
select 'offset_earn', 'Offset Earn', id, 2, false, 'earn'
from public.functions where code = 'operations'
on conflict (code) do nothing;

insert into public.request_types (
  code,
  name,
  required_function_id,
  approval_count,
  requires_offset_credit_check,
  affects_offset_balance
)
select 'use_offset', 'Use Offset', id, 1, true, 'use'
from public.functions where code = 'operations'
on conflict (code) do nothing;

insert into public.request_types (
  code,
  name,
  required_function_id,
  approval_count,
  requires_offset_credit_check,
  affects_offset_balance
)
select 'leave', 'Leave', id, 1, false, 'none'
from public.functions where code = 'operations'
on conflict (code) do nothing;

insert into public.approval_level_routes (requester_level, step_order, approver_level) values
  (1, 1, 2),
  (1, 2, 4),
  (2, 1, 4),
  (2, 2, 5),
  (3, 1, 6),
  (3, 2, 7),
  (4, 1, 5),
  (4, 2, 6),
  (5, 1, 6),
  (5, 2, 7),
  (6, 1, 7),
  (6, 2, 8),
  (7, 1, 8)
on conflict do nothing;
