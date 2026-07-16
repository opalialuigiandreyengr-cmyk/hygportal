-- Include position authority levels in the department-position catalog so
-- approval route role pickers can use Departments + Positions as one source.

drop function if exists public.admin_department_position_catalog();

create or replace function public.admin_department_position_catalog()
returns table (
  department_id uuid,
  department_name text,
  position_id uuid,
  position_name text,
  authority_level int,
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
    coalesce(p.authority_level, 1) as authority_level,
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
  group by d.id, d.name, p.id, p.name, p.authority_level
  order by d.name, coalesce(p.authority_level, 1), p.name;
end;
$$;

grant execute on function public.admin_department_position_catalog() to authenticated;

notify pgrst, 'reload schema';
