-- Treat Level 1 as the default bottom/requester level, not an approver route step.

update public.positions
set authority_level = 1
where authority_level is null;

delete from public.department_approval_ladders
where authority_level <= 1;

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
    coalesce(p.authority_level, 1) as position_level,
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

create or replace function public.hr_admin_position_authority_levels(
  p_username text default null,
  p_password text default null
)
returns table (
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
  if not public.hr_admin_has_access(p_username, p_password) then
    raise exception 'Admin access is required.';
  end if;

  return query
  select
    p.id,
    p.name,
    coalesce(p.authority_level, 1) as authority_level,
    count(distinct ea.employee_id) as employee_count
  from public.positions p
  left join public.employee_assignments ea
    on ea.position_id = p.id
   and ea.is_primary = true
   and ea.effective_to is null
  where p.is_active = true
  group by p.id, p.name, p.authority_level
  order by coalesce(p.authority_level, 1), p.name;
end;
$$;

create or replace function public.hr_admin_clear_position_authority_level(
  p_username text default null,
  p_password text default null,
  p_position_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.hr_admin_has_access(p_username, p_password) then
    raise exception 'Admin access is required.';
  end if;

  if p_position_id is null then
    raise exception 'Position is required.';
  end if;

  update public.positions
  set authority_level = 1
  where id = p_position_id;

  insert into public.audit_logs (action, entity_type, entity_id, metadata)
  values (
    'hr_admin_clear_position_authority_level',
    'position',
    p_position_id,
    jsonb_build_object('authority_level', 1)
  );

  return p_position_id;
end;
$$;

create or replace function public.hr_admin_department_approval_ladders(
  p_username text default null,
  p_password text default null
)
returns table (
  department_id uuid,
  department_name text,
  route_levels int[]
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
    d.id,
    d.name,
    coalesce(
      array_agg(l.authority_level order by l.authority_level)
        filter (where l.authority_level > 1),
      '{}'::int[]
    ) as route_levels
  from public.departments d
  left join public.department_approval_ladders l on l.department_id = d.id
  where d.is_active = true
  group by d.id, d.name
  order by d.name;
end;
$$;

create or replace function public.hr_admin_set_department_approval_ladder(
  p_username text default null,
  p_password text default null,
  p_department_id uuid default null,
  p_levels int[] default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_level int;
  v_requester_level int;
  v_step_one int;
  v_step_two int;
begin
  if not public.hr_admin_has_access(p_username, p_password) then
    raise exception 'Admin access is required.';
  end if;

  if p_department_id is null then
    raise exception 'Department is required.';
  end if;

  delete from public.department_approval_ladders
  where department_id = p_department_id;

  for v_level in
    select distinct level_value
    from unnest(coalesce(p_levels, '{}'::int[])) as level_value
    where level_value between 2 and 8
    order by level_value
  loop
    insert into public.department_approval_ladders (department_id, authority_level)
    values (p_department_id, v_level)
    on conflict do nothing;
  end loop;

  delete from public.approval_level_routes
  where department_id = p_department_id;

  for v_requester_level in 1..8 loop
    select authority_level
    into v_step_one
    from public.department_approval_ladders
    where department_id = p_department_id
      and authority_level > v_requester_level
    order by authority_level
    limit 1;

    select authority_level
    into v_step_two
    from public.department_approval_ladders
    where department_id = p_department_id
      and authority_level > coalesce(v_step_one, v_requester_level)
    order by authority_level
    limit 1;

    if v_step_one is not null then
      insert into public.approval_level_routes (department_id, requester_level, step_order, approver_level)
      values (p_department_id, v_requester_level, 1, v_step_one);
    end if;

    if v_step_two is not null then
      insert into public.approval_level_routes (department_id, requester_level, step_order, approver_level)
      values (p_department_id, v_requester_level, 2, v_step_two);
    end if;
  end loop;

  insert into public.audit_logs (action, entity_type, entity_id, metadata)
  values (
    'hr_admin_set_department_approval_ladder',
    'department',
    p_department_id,
    jsonb_build_object('levels', coalesce(p_levels, '{}'::int[]))
  );

  return p_department_id;
end;
$$;

grant execute on function public.hr_admin_authority_candidates(text, text) to anon, authenticated;
grant execute on function public.hr_admin_position_authority_levels(text, text) to anon, authenticated;
grant execute on function public.hr_admin_clear_position_authority_level(text, text, uuid) to anon, authenticated;
grant execute on function public.hr_admin_department_approval_ladders(text, text) to anon, authenticated;
grant execute on function public.hr_admin_set_department_approval_ladder(text, text, uuid, int[]) to anon, authenticated;

notify pgrst, 'reload schema';
