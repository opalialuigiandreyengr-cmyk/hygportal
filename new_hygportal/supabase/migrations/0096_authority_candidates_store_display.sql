-- Add store details to approver assignment candidates for desktop display.

drop function if exists public.hr_admin_authority_candidates(text, text);

create or replace function public.hr_admin_authority_candidates(
  p_username text default null,
  p_password text default null
)
returns table (
  employee_id uuid,
  employee_no text,
  full_name text,
  position_id uuid,
  position_name text,
  position_level int,
  function_id uuid,
  function_name text,
  store_id uuid,
  store_name text,
  company_id uuid,
  company_name text,
  department_id uuid,
  department_name text,
  current_authority_level int
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.hr_admin_has_access(p_username, p_password) then
    raise exception 'Admin access is required.';
  end if;

  return query
  select
    e.id,
    e.employee_no,
    trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)) as full_name,
    p.id as position_id,
    p.name as position_name,
    p.authority_level as position_level,
    f.id as function_id,
    f.name as function_name,
    s.id as store_id,
    coalesce(s.name, 'N/A') as store_name,
    c.id as company_id,
    c.name as company_name,
    d.id as department_id,
    d.name as department_name,
    aa.authority_level as current_authority_level
  from public.employees e
  join lateral (
    select *
    from public.employee_assignments ea
    where ea.employee_id = e.id
      and ea.is_primary = true
      and ea.effective_to is null
    order by ea.created_at desc
    limit 1
  ) ea on true
  join public.positions p on p.id = ea.position_id
  join public.functions f on f.id = ea.function_id
  join public.companies c on c.id = ea.company_id
  left join public.stores s on s.id = ea.store_id
  left join public.departments d on d.id = ea.department_id
  left join lateral (
    select authority_level
    from public.authority_assignments current_aa
    where current_aa.employee_id = e.id
      and current_aa.function_id = ea.function_id
      and current_aa.store_id is not distinct from ea.store_id
      and current_aa.is_active = true
      and current_aa.effective_to is null
    order by current_aa.created_at desc
    limit 1
  ) aa on true
  where e.employment_status = 'active'
  order by e.last_name, e.first_name;
end;
$$;

grant execute on function public.hr_admin_authority_candidates(text, text) to anon, authenticated;

notify pgrst, 'reload schema';
