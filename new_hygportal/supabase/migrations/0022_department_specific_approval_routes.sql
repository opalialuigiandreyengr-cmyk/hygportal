alter table public.approval_level_routes
add column if not exists department_id uuid references public.departments(id);

alter table public.approval_level_routes
drop constraint if exists approval_level_routes_requester_level_step_order_key;

create unique index if not exists approval_level_routes_global_unique
on public.approval_level_routes (requester_level, step_order)
where department_id is null;

create unique index if not exists approval_level_routes_department_unique
on public.approval_level_routes (department_id, requester_level, step_order)
where department_id is not null;

create or replace function public.scope_matches_assignment(
  p_level int,
  p_assignment public.employee_assignments,
  p_authority public.authority_assignments
)
returns boolean
language plpgsql
stable
as $$
begin
  if p_level = 2 then
    return p_authority.store_id is not null and p_authority.store_id = p_assignment.store_id;
  elsif p_level = 3 then
    return (
      p_authority.company_id = p_assignment.company_id
      and (
        p_authority.department_id is null
        or p_assignment.department_id is null
        or p_authority.department_id = p_assignment.department_id
      )
    );
  elsif p_level = 4 then
    return (
      (p_assignment.cluster_id is not null and p_authority.cluster_id = p_assignment.cluster_id)
      or (p_assignment.cluster_id is null and p_authority.company_id = p_assignment.company_id)
    );
  elsif p_level = 5 then
    return (
      (p_assignment.area_id is not null and p_authority.area_id = p_assignment.area_id)
      or (p_assignment.area_id is null and p_authority.company_id = p_assignment.company_id)
    );
  else
    return p_authority.company_id is not null and p_authority.company_id = p_assignment.company_id;
  end if;
end;
$$;

with route_overrides(department_name, requester_level, step_order, approver_level) as (
  values
    ('Operations', 1, 1, 3),
    ('Operations', 1, 2, 4),
    ('IT', 1, 1, 3),
    ('IT', 1, 2, 5),
    ('Maintenance', 1, 1, 3),
    ('Maintenance', 1, 2, 5),
    ('Logistics', 1, 1, 3),
    ('Logistics', 1, 2, 5),
    ('Accounting', 1, 1, 3),
    ('Accounting', 1, 2, 5),
    ('Inventory', 1, 1, 3),
    ('Inventory', 1, 2, 5),
    ('HR', 1, 1, 3),
    ('HR', 1, 2, 5),
    ('Marketing', 1, 1, 3),
    ('Marketing', 1, 2, 5),
    ('Admin', 1, 1, 3),
    ('Admin', 1, 2, 5),
    ('Customer Service', 1, 1, 3),
    ('Customer Service', 1, 2, 5)
)
insert into public.approval_level_routes (
  department_id,
  requester_level,
  step_order,
  approver_level
)
select
  d.id,
  r.requester_level,
  r.step_order,
  r.approver_level
from route_overrides r
join public.departments d on lower(d.name) = lower(r.department_name)
on conflict do nothing;
