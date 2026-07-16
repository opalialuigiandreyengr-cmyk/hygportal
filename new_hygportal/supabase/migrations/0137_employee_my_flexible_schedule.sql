create or replace function public.employee_my_flexible_schedule(p_schedule_date date)
returns table (
  id uuid,
  schedule_date text,
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
  v_employee_id uuid;
begin
  select up.employee_id
  into v_employee_id
  from public.user_profiles up
  where up.auth_user_id = auth.uid()
    and coalesce(up.is_active, true) = true;

  if v_employee_id is null then
    raise exception 'Your login is not linked to an active employee profile.';
  end if;

  if p_schedule_date is null then
    return;
  end if;

  return query
  select
    mts.id,
    mts.schedule_date::text,
    case when mts.from_time is null then null else to_char(mts.from_time, 'HH24:MI') end as from_time,
    case when mts.to_time is null then null else to_char(mts.to_time, 'HH24:MI') end as to_time,
    mts.is_day_off,
    mts.notes
  from public.manager_team_schedules mts
  where mts.employee_id = v_employee_id
    and mts.schedule_date = p_schedule_date
  limit 1;
end;
$$;

grant execute on function public.employee_my_flexible_schedule(date) to authenticated;

notify pgrst, 'reload schema';
