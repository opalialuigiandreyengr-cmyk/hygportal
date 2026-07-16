create or replace function public.manager_my_team_directory()
returns table (
  employee_id uuid,
  employee_no text,
  full_name text,
  photo_url text,
  employment_status text,
  department_name text,
  position_name text,
  time_schedule text,
  day_off text
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_manager_employee_id uuid;
  v_manager_store_id uuid;
  v_manager_position text;
begin
  select up.employee_id
  into v_manager_employee_id
  from public.user_profiles up
  where up.auth_user_id = auth.uid()
    and up.is_active = true;

  if v_manager_employee_id is null then
    raise exception 'Your login is not linked to an active employee profile.';
  end if;

  select ea.store_id, p.name
  into v_manager_store_id, v_manager_position
  from public.employee_assignments ea
  join public.positions p on p.id = ea.position_id
  where ea.employee_id = v_manager_employee_id
    and ea.is_primary = true
    and ea.effective_from <= current_date
    and (ea.effective_to is null or ea.effective_to >= current_date)
  order by ea.effective_from desc, ea.created_at desc
  limit 1;

  if lower(trim(coalesce(v_manager_position, ''))) <> 'store manager' then
    raise exception 'Store Manager access is required.';
  end if;

  if v_manager_store_id is null then
    return;
  end if;

  return query
  select
    e.id as employee_id,
    e.employee_no,
    nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), '') as full_name,
    e.photo_url,
    e.employment_status,
    d.name as department_name,
    p.name as position_name,
    epd.time_schedule,
    epd.day_off
  from public.employee_assignments ea
  join public.employees e on e.id = ea.employee_id
  left join public.departments d on d.id = ea.department_id
  left join public.positions p on p.id = ea.position_id
  left join public.employee_profile_details epd on epd.employee_id = e.id
  where ea.store_id = v_manager_store_id
    and ea.employee_id <> v_manager_employee_id
    and ea.is_primary = true
    and ea.effective_from <= current_date
    and (ea.effective_to is null or ea.effective_to >= current_date)
  order by e.last_name, e.first_name;
end;
$$;

grant execute on function public.manager_my_team_directory() to authenticated;
