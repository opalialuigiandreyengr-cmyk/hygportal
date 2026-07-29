create table if not exists public.manager_team_schedules (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  schedule_date date not null,
  from_time time,
  to_time time,
  is_day_off boolean not null default false,
  notes text,
  created_by_employee_id uuid references public.employees(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint manager_team_schedules_one_per_day unique (employee_id, schedule_date),
  constraint manager_team_schedules_time_check check (
    is_day_off = true or (from_time is not null and to_time is not null)
  )
);

create index if not exists manager_team_schedules_employee_date_idx
  on public.manager_team_schedules (employee_id, schedule_date);

alter table public.manager_team_schedules enable row level security;

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
    nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), '') as employee_name,
    case when mts.from_time is null then null else to_char(mts.from_time, 'HH24:MI') end as from_time,
    case when mts.to_time is null then null else to_char(mts.to_time, 'HH24:MI') end as to_time,
    mts.is_day_off,
    mts.notes
  from public.manager_team_schedules mts
  join public.employees e on e.id = mts.employee_id
  join public.employee_assignments ea on ea.employee_id = e.id
  where ea.store_id = v_manager_store_id
    and ea.employee_id <> v_manager_employee_id
    and ea.is_primary = true
    and ea.effective_from <= current_date
    and (ea.effective_to is null or ea.effective_to >= current_date)
  order by e.last_name, e.first_name, mts.schedule_date;
end;
$$;

create or replace function public.manager_save_team_schedules(
  p_employee_ids uuid[],
  p_schedule_date date,
  p_from_time text,
  p_to_time text,
  p_is_day_off boolean,
  p_notes text
)
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
  v_invalid_count int;
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
    raise exception 'No assigned store found.';
  end if;

  if p_schedule_date is null then
    raise exception 'Schedule date is required.';
  end if;

  if p_employee_ids is null or cardinality(p_employee_ids) = 0 then
    raise exception 'Select at least one employee.';
  end if;

  if coalesce(p_is_day_off, false) = false
    and (nullif(trim(coalesce(p_from_time, '')), '') is null or nullif(trim(coalesce(p_to_time, '')), '') is null) then
    raise exception 'Enter from and to time.';
  end if;

  select count(*)
  into v_invalid_count
  from unnest(p_employee_ids) selected(employee_id)
  where not exists (
    select 1
    from public.employee_assignments ea
    where ea.employee_id = selected.employee_id
      and ea.store_id = v_manager_store_id
      and ea.employee_id <> v_manager_employee_id
      and ea.is_primary = true
      and ea.effective_from <= current_date
      and (ea.effective_to is null or ea.effective_to >= current_date)
  );

  if v_invalid_count > 0 then
    raise exception 'One or more selected employees are outside your assigned store.';
  end if;

  insert into public.manager_team_schedules (
    employee_id,
    schedule_date,
    from_time,
    to_time,
    is_day_off,
    notes,
    created_by_employee_id,
    updated_at
  )
  select
    selected.employee_id,
    p_schedule_date,
    case when coalesce(p_is_day_off, false) then null else nullif(trim(p_from_time), '')::time end,
    case when coalesce(p_is_day_off, false) then null else nullif(trim(p_to_time), '')::time end,
    coalesce(p_is_day_off, false),
    nullif(trim(coalesce(p_notes, '')), ''),
    v_manager_employee_id,
    now()
  from unnest(p_employee_ids) selected(employee_id)
  on conflict (employee_id, schedule_date)
  do update set
    from_time = excluded.from_time,
    to_time = excluded.to_time,
    is_day_off = excluded.is_day_off,
    notes = excluded.notes,
    created_by_employee_id = excluded.created_by_employee_id,
    updated_at = now();

  return query
  select * from public.manager_my_team_schedules();
end;
$$;

create or replace function public.manager_delete_team_schedule(p_schedule_id uuid)
returns void
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

  delete from public.manager_team_schedules mts
  where mts.id = p_schedule_id
    and exists (
      select 1
      from public.employee_assignments ea
      where ea.employee_id = mts.employee_id
        and ea.store_id = v_manager_store_id
        and ea.employee_id <> v_manager_employee_id
        and ea.is_primary = true
        and ea.effective_from <= current_date
        and (ea.effective_to is null or ea.effective_to >= current_date)
    );
end;
$$;

grant execute on function public.manager_my_team_schedules() to authenticated;
grant execute on function public.manager_save_team_schedules(uuid[], date, text, text, boolean, text) to authenticated;
grant execute on function public.manager_delete_team_schedule(uuid) to authenticated;

notify pgrst, 'reload schema';
