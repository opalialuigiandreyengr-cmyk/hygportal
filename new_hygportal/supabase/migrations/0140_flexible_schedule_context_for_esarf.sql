drop function if exists public.employee_my_flexible_schedule(date);

create or replace function public.employee_my_flexible_schedule(p_schedule_date date)
returns table (
  id uuid,
  schedule_date text,
  from_time text,
  to_time text,
  is_day_off boolean,
  notes text,
  previous_from_time text,
  previous_to_time text,
  previous_day_off_date text
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
    exact_schedule.id,
    exact_schedule.schedule_date::text,
    case when exact_schedule.from_time is null then null else to_char(exact_schedule.from_time, 'HH24:MI') end as from_time,
    case when exact_schedule.to_time is null then null else to_char(exact_schedule.to_time, 'HH24:MI') end as to_time,
    exact_schedule.is_day_off,
    exact_schedule.notes,
    case when previous_work.from_time is null then null else to_char(previous_work.from_time, 'HH24:MI') end as previous_from_time,
    case when previous_work.to_time is null then null else to_char(previous_work.to_time, 'HH24:MI') end as previous_to_time,
    previous_day_off.schedule_date::text as previous_day_off_date
  from public.manager_team_schedules exact_schedule
  left join lateral (
    select mts.from_time, mts.to_time
    from public.manager_team_schedules mts
    where mts.employee_id = v_employee_id
      and mts.schedule_date < p_schedule_date
      and mts.is_day_off = false
      and mts.from_time is not null
      and mts.to_time is not null
    order by mts.schedule_date desc
    limit 1
  ) previous_work on true
  left join lateral (
    select mts.schedule_date
    from public.manager_team_schedules mts
    where mts.employee_id = v_employee_id
      and mts.schedule_date < p_schedule_date
      and mts.is_day_off = true
    order by mts.schedule_date desc
    limit 1
  ) previous_day_off on true
  where exact_schedule.employee_id = v_employee_id
    and exact_schedule.schedule_date = p_schedule_date
  limit 1;
end;
$$;

grant execute on function public.employee_my_flexible_schedule(date) to authenticated;

notify pgrst, 'reload schema';
