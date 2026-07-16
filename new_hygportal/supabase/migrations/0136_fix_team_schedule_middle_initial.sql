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
    and coalesce(up.is_active, true) = true;

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
    nullif(trim(concat_ws(
      ' ',
      nullif(trim(e.first_name), ''),
      case
        when lower(trim(coalesce(e.middle_name, ''))) in ('', 'n/a', 'na') then null
        else upper(left(trim(e.middle_name), 1)) || '.'
      end,
      nullif(trim(e.last_name), ''),
      nullif(trim(coalesce(e.suffix, '')), '')
    )), '') as full_name,
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
    and ea.is_primary = true
    and ea.effective_from <= current_date
    and (ea.effective_to is null or ea.effective_to >= current_date)
  order by
    case when e.id = v_manager_employee_id then 0 else 1 end,
    e.last_name,
    e.first_name;
end;
$$;

create or replace function public.manager_my_team_schedules()
returns table (
  id uuid,
  schedule_date text,
  employee_id uuid,
  employee_name text,
  from_time text,
  to_time text,
  is_day_off boolean,
  notes text
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
    and coalesce(up.is_active, true) = true;

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
    mts.id,
    mts.schedule_date::text,
    e.id as employee_id,
    nullif(trim(concat_ws(
      ' ',
      nullif(trim(e.first_name), ''),
      case
        when lower(trim(coalesce(e.middle_name, ''))) in ('', 'n/a', 'na') then null
        else upper(left(trim(e.middle_name), 1)) || '.'
      end,
      nullif(trim(e.last_name), ''),
      nullif(trim(coalesce(e.suffix, '')), '')
    )), '') as employee_name,
    case when mts.from_time is null then null else to_char(mts.from_time, 'HH24:MI') end as from_time,
    case when mts.to_time is null then null else to_char(mts.to_time, 'HH24:MI') end as to_time,
    mts.is_day_off,
    mts.notes
  from public.manager_team_schedules mts
  join public.employees e on e.id = mts.employee_id
  join public.employee_assignments ea on ea.employee_id = e.id
  where ea.store_id = v_manager_store_id
    and ea.is_primary = true
    and ea.effective_from <= current_date
    and (ea.effective_to is null or ea.effective_to >= current_date)
  order by
    case when e.id = v_manager_employee_id then 0 else 1 end,
    e.last_name,
    e.first_name,
    mts.schedule_date;
end;
$$;

notify pgrst, 'reload schema';
