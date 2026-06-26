create table if not exists public.department_positions (
  department_id uuid not null references public.departments(id) on delete cascade,
  position_id uuid not null references public.positions(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (department_id, position_id)
);

alter table public.department_positions enable row level security;

drop policy if exists "Authenticated users can read department positions" on public.department_positions;
create policy "Authenticated users can read department positions"
on public.department_positions for select
to authenticated
using (true);

insert into public.department_positions (department_id, position_id)
select distinct ea.department_id, ea.position_id
from public.employee_assignments ea
where ea.department_id is not null
  and ea.position_id is not null
on conflict do nothing;

with default_departments(name) as (
  values
    ('IT'),
    ('Maintenance'),
    ('Logistics'),
    ('Accounting'),
    ('Inventory'),
    ('Operations'),
    ('HR'),
    ('Marketing'),
    ('Admin'),
    ('Customer Service')
)
insert into public.functions (name, code)
select
  name,
  upper(regexp_replace(name, '[^a-zA-Z0-9]+', '_', 'g'))
from default_departments
on conflict (name) do nothing;

with default_departments(name) as (
  values
    ('IT'),
    ('Maintenance'),
    ('Logistics'),
    ('Accounting'),
    ('Inventory'),
    ('Operations'),
    ('HR'),
    ('Marketing'),
    ('Admin'),
    ('Customer Service')
)
insert into public.departments (name, function_id)
select d.name, f.id
from default_departments d
left join public.functions f on lower(f.name) = lower(d.name)
on conflict (name) do nothing;

with default_positions(name) as (
  values
    ('Crew'),
    ('Supervisor'),
    ('Store Manager'),
    ('Department Manager'),
    ('Cluster Manager'),
    ('Area Manager'),
    ('Operations Manager'),
    ('Operations Director'),
    ('Finance Director'),
    ('General Manager'),
    ('Staff'),
    ('IT Staff'),
    ('Officer'),
    ('Specialist'),
    ('Analyst'),
    ('Coordinator'),
    ('Assistant'),
    ('Team Leader'),
    ('Auditor'),
    ('Training Officer'),
    ('Director')
)
insert into public.positions (name, authority_level)
select name, public.position_level_for_profile(name)
from default_positions
on conflict (name) do nothing;

with default_mappings(department_name, position_name) as (
  values
    ('Operations', 'Crew'),
    ('Operations', 'Supervisor'),
    ('Operations', 'Store Manager'),
    ('Operations', 'Cluster Manager'),
    ('Operations', 'Area Manager'),
    ('Operations', 'Operations Manager'),
    ('Operations', 'Operations Director'),
    ('IT', 'IT Staff'),
    ('IT', 'Staff'),
    ('IT', 'Specialist'),
    ('IT', 'Analyst'),
    ('IT', 'Officer'),
    ('Maintenance', 'Staff'),
    ('Maintenance', 'Supervisor'),
    ('Maintenance', 'Coordinator'),
    ('Logistics', 'Staff'),
    ('Logistics', 'Coordinator'),
    ('Logistics', 'Supervisor'),
    ('Accounting', 'Staff'),
    ('Accounting', 'Analyst'),
    ('Accounting', 'Officer'),
    ('Accounting', 'Finance Director'),
    ('Inventory', 'Staff'),
    ('Inventory', 'Coordinator'),
    ('Inventory', 'Supervisor'),
    ('HR', 'Staff'),
    ('HR', 'Officer'),
    ('HR', 'Coordinator'),
    ('Marketing', 'Staff'),
    ('Marketing', 'Specialist'),
    ('Marketing', 'Coordinator'),
    ('Admin', 'Staff'),
    ('Admin', 'Assistant'),
    ('Admin', 'Officer'),
    ('Customer Service', 'Staff'),
    ('Customer Service', 'Team Leader'),
    ('Customer Service', 'Supervisor')
)
insert into public.department_positions (department_id, position_id)
select d.id, p.id
from default_mappings m
join public.departments d on lower(d.name) = lower(m.department_name)
join public.positions p on lower(p.name) = lower(m.position_name)
on conflict do nothing;

delete from public.department_positions dp
using public.departments d
where dp.department_id = d.id
  and d.name in ('Training', 'Purchasing', 'Warehouse', 'Payroll', 'Audit')
  and not exists (
    select 1
    from public.employee_assignments ea
    where ea.department_id = d.id
  );

delete from public.departments d
where d.name in ('Training', 'Purchasing', 'Warehouse', 'Payroll', 'Audit')
  and not exists (
    select 1
    from public.employee_assignments ea
    where ea.department_id = d.id
  );

create or replace function public.admin_department_position_catalog()
returns table (
  department_id uuid,
  department_name text,
  position_id uuid,
  position_name text,
  employee_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Admin access is required.';
  end if;

  return query
  select
    d.id,
    d.name,
    p.id,
    p.name,
    count(distinct ea.employee_id) as employee_count
  from public.departments d
  left join public.department_positions dp
    on dp.department_id = d.id
  left join public.positions p
    on p.id = dp.position_id
   and p.is_active = true
  left join public.employee_assignments ea
    on ea.department_id = d.id
   and ea.position_id = p.id
   and ea.is_primary = true
   and ea.effective_to is null
  where d.is_active = true
  group by d.id, d.name, p.id, p.name
  order by d.name, p.name;
end;
$$;

grant execute on function public.admin_department_position_catalog() to authenticated;

create or replace function public.admin_position_catalog()
returns table (
  position_id uuid,
  position_name text,
  employee_count bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Admin access is required.';
  end if;

  return query
  select
    p.id,
    p.name,
    count(distinct ea.employee_id) as employee_count
  from public.positions p
  left join public.employee_assignments ea
    on ea.position_id = p.id
   and ea.is_primary = true
   and ea.effective_to is null
  where p.is_active = true
  group by p.id, p.name
  order by p.name;
end;
$$;

grant execute on function public.admin_position_catalog() to authenticated;

create or replace function public.admin_create_department(
  p_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_department_id uuid;
  v_function_id uuid;
  v_name text := nullif(trim(p_name), '');
begin
  if not public.is_super_admin() then
    raise exception 'Admin access is required.';
  end if;

  if v_name is null then
    raise exception 'Department name is required.';
  end if;

  select id into v_function_id
  from public.functions
  where lower(name) = lower(v_name)
  limit 1;

  if v_function_id is null then
    insert into public.functions (name, code)
    values (v_name, upper(regexp_replace(v_name, '[^a-zA-Z0-9]+', '_', 'g')))
    returning id into v_function_id;
  end if;

  select id into v_department_id
  from public.departments
  where lower(name) = lower(v_name)
  limit 1;

  if v_department_id is null then
    insert into public.departments (name, function_id)
    values (v_name, v_function_id)
    returning id into v_department_id;
  end if;

  insert into public.audit_logs (action, entity_type, entity_id, metadata)
  values (
    'admin_create_department',
    'department',
    v_department_id,
    jsonb_build_object('name', v_name)
  );

  return v_department_id;
end;
$$;

grant execute on function public.admin_create_department(text) to authenticated;

create or replace function public.admin_create_position(
  p_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_position_id uuid;
  v_name text := nullif(trim(p_name), '');
begin
  if not public.is_super_admin() then
    raise exception 'Admin access is required.';
  end if;

  if v_name is null then
    raise exception 'Position name is required.';
  end if;

  select id into v_position_id
  from public.positions
  where lower(name) = lower(v_name)
  limit 1;

  if v_position_id is null then
    insert into public.positions (name, authority_level)
    values (v_name, public.position_level_for_profile(v_name))
    returning id into v_position_id;
  end if;

  insert into public.audit_logs (action, entity_type, entity_id, metadata)
  values (
    'admin_create_position',
    'position',
    v_position_id,
    jsonb_build_object('name', v_name)
  );

  return v_position_id;
end;
$$;

grant execute on function public.admin_create_position(text) to authenticated;

create or replace function public.admin_assign_department_position(
  p_department_id uuid,
  p_position_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Admin access is required.';
  end if;

  if p_department_id is null or p_position_id is null then
    raise exception 'Department and position are required.';
  end if;

  insert into public.department_positions (department_id, position_id)
  values (p_department_id, p_position_id)
  on conflict do nothing;

  insert into public.audit_logs (action, entity_type, entity_id, metadata)
  values (
    'admin_assign_department_position',
    'department',
    p_department_id,
    jsonb_build_object('position_id', p_position_id)
  );

  return p_department_id;
end;
$$;

grant execute on function public.admin_assign_department_position(uuid, uuid) to authenticated;

create or replace function public.admin_remove_department_position(
  p_department_id uuid,
  p_position_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Admin access is required.';
  end if;

  if p_department_id is null or p_position_id is null then
    raise exception 'Department and position are required.';
  end if;

  delete from public.department_positions
  where department_id = p_department_id
    and position_id = p_position_id;

  insert into public.audit_logs (action, entity_type, entity_id, metadata)
  values (
    'admin_remove_department_position',
    'department',
    p_department_id,
    jsonb_build_object('position_id', p_position_id)
  );

  return p_department_id;
end;
$$;

grant execute on function public.admin_remove_department_position(uuid, uuid) to authenticated;

create or replace function public.employee_assignment_options()
returns table (
  department_name text,
  position_name text
)
language sql
security definer
set search_path = public
as $$
  select
    d.name as department_name,
    p.name as position_name
  from public.departments d
  left join public.department_positions dp
    on dp.department_id = d.id
  left join public.positions p
    on p.id = dp.position_id
   and p.is_active = true
  where d.is_active = true
  order by d.name, p.name;
$$;

grant execute on function public.employee_assignment_options() to anon, authenticated;
