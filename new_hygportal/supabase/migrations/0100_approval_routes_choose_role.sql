-- Allow approval routes to target a specific role/position within an authority level.

alter table public.department_approval_ladders
add column if not exists approver_position_id uuid references public.positions(id);

alter table public.approval_level_routes
add column if not exists approver_position_id uuid references public.positions(id);

drop function if exists public.hr_admin_department_approval_ladders(text, text);

create or replace function public.hr_admin_department_approval_ladders(
  p_username text default null,
  p_password text default null
)
returns table (
  department_id uuid,
  department_name text,
  route_levels int[],
  route_roles jsonb
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
    ) as route_levels,
    coalesce(
      jsonb_object_agg(
        l.authority_level::text,
        jsonb_build_object(
          'position_id', p.id,
          'position_name', p.name
        )
      ) filter (where l.authority_level > 1 and p.id is not null),
      '{}'::jsonb
    ) as route_roles
  from public.departments d
  left join public.department_approval_ladders l on l.department_id = d.id
  left join public.positions p on p.id = l.approver_position_id
  where d.is_active = true
  group by d.id, d.name
  order by d.name;
end;
$$;

drop function if exists public.hr_admin_set_department_approval_ladder(text, text, uuid, int[]);

create or replace function public.hr_admin_set_department_approval_ladder(
  p_username text default null,
  p_password text default null,
  p_department_id uuid default null,
  p_levels int[] default null,
  p_roles jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_level int;
  v_role_id uuid;
  v_requester_level int;
  v_step_one_level int;
  v_step_one_position_id uuid;
  v_step_two_level int;
  v_step_two_position_id uuid;
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
    v_role_id := nullif(p_roles ->> v_level::text, '')::uuid;

    if v_role_id is not null and not exists (
      select 1
      from public.positions p
      join public.department_positions dp on dp.position_id = p.id
      where p.id = v_role_id
        and p.is_active = true
        and p.authority_level = v_level
        and dp.department_id = p_department_id
    ) then
      raise exception 'Selected role must be active, assigned to this department, and assigned to Level %.', v_level;
    end if;

    insert into public.department_approval_ladders (
      department_id,
      authority_level,
      approver_position_id
    )
    values (p_department_id, v_level, v_role_id)
    on conflict (department_id, authority_level) do update
    set approver_position_id = excluded.approver_position_id;
  end loop;

  delete from public.approval_level_routes
  where department_id = p_department_id;

  for v_requester_level in 1..8 loop
    select authority_level, approver_position_id
    into v_step_one_level, v_step_one_position_id
    from public.department_approval_ladders
    where department_id = p_department_id
      and authority_level > v_requester_level
    order by authority_level
    limit 1;

    select authority_level, approver_position_id
    into v_step_two_level, v_step_two_position_id
    from public.department_approval_ladders
    where department_id = p_department_id
      and authority_level > coalesce(v_step_one_level, v_requester_level)
    order by authority_level
    limit 1;

    if v_step_one_level is not null then
      insert into public.approval_level_routes (
        department_id,
        requester_level,
        step_order,
        approver_level,
        approver_position_id
      )
      values (
        p_department_id,
        v_requester_level,
        1,
        v_step_one_level,
        v_step_one_position_id
      );
    end if;

    if v_step_two_level is not null then
      insert into public.approval_level_routes (
        department_id,
        requester_level,
        step_order,
        approver_level,
        approver_position_id
      )
      values (
        p_department_id,
        v_requester_level,
        2,
        v_step_two_level,
        v_step_two_position_id
      );
    end if;
  end loop;

  insert into public.audit_logs (action, entity_type, entity_id, metadata)
  values (
    'hr_admin_set_department_approval_ladder',
    'department',
    p_department_id,
    jsonb_build_object(
      'levels', coalesce(p_levels, '{}'::int[]),
      'roles', coalesce(p_roles, '{}'::jsonb)
    )
  );

  return p_department_id;
end;
$$;

drop function if exists public.admin_department_approval_ladders();

create or replace function public.admin_department_approval_ladders()
returns table (
  department_id uuid,
  department_name text,
  route_levels int[],
  route_roles jsonb
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
    coalesce(
      array_agg(l.authority_level order by l.authority_level)
        filter (where l.authority_level > 1),
      '{}'::int[]
    ) as route_levels,
    coalesce(
      jsonb_object_agg(
        l.authority_level::text,
        jsonb_build_object(
          'position_id', p.id,
          'position_name', p.name
        )
      ) filter (where l.authority_level > 1 and p.id is not null),
      '{}'::jsonb
    ) as route_roles
  from public.departments d
  left join public.department_approval_ladders l on l.department_id = d.id
  left join public.positions p on p.id = l.approver_position_id
  where d.is_active = true
  group by d.id, d.name
  order by d.name;
end;
$$;

drop function if exists public.admin_set_department_approval_ladder(uuid, int[]);

create or replace function public.admin_set_department_approval_ladder(
  p_department_id uuid,
  p_levels int[],
  p_roles jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_level int;
  v_role_id uuid;
  v_requester_level int;
  v_step_one_level int;
  v_step_one_position_id uuid;
  v_step_two_level int;
  v_step_two_position_id uuid;
begin
  if not public.is_super_admin() then
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
    v_role_id := nullif(p_roles ->> v_level::text, '')::uuid;

    if v_role_id is not null and not exists (
      select 1
      from public.positions p
      join public.department_positions dp on dp.position_id = p.id
      where p.id = v_role_id
        and p.is_active = true
        and p.authority_level = v_level
        and dp.department_id = p_department_id
    ) then
      raise exception 'Selected role must be active, assigned to this department, and assigned to Level %.', v_level;
    end if;

    insert into public.department_approval_ladders (
      department_id,
      authority_level,
      approver_position_id
    )
    values (p_department_id, v_level, v_role_id)
    on conflict (department_id, authority_level) do update
    set approver_position_id = excluded.approver_position_id;
  end loop;

  delete from public.approval_level_routes
  where department_id = p_department_id;

  for v_requester_level in 1..8 loop
    select authority_level, approver_position_id
    into v_step_one_level, v_step_one_position_id
    from public.department_approval_ladders
    where department_id = p_department_id
      and authority_level > v_requester_level
    order by authority_level
    limit 1;

    select authority_level, approver_position_id
    into v_step_two_level, v_step_two_position_id
    from public.department_approval_ladders
    where department_id = p_department_id
      and authority_level > coalesce(v_step_one_level, v_requester_level)
    order by authority_level
    limit 1;

    if v_step_one_level is not null then
      insert into public.approval_level_routes (
        department_id,
        requester_level,
        step_order,
        approver_level,
        approver_position_id
      )
      values (
        p_department_id,
        v_requester_level,
        1,
        v_step_one_level,
        v_step_one_position_id
      );
    end if;

    if v_step_two_level is not null then
      insert into public.approval_level_routes (
        department_id,
        requester_level,
        step_order,
        approver_level,
        approver_position_id
      )
      values (
        p_department_id,
        v_requester_level,
        2,
        v_step_two_level,
        v_step_two_position_id
      );
    end if;
  end loop;

  insert into public.audit_logs (action, entity_type, entity_id, metadata)
  values (
    'admin_set_department_approval_ladder',
    'department',
    p_department_id,
    jsonb_build_object(
      'levels', coalesce(p_levels, '{}'::int[]),
      'roles', coalesce(p_roles, '{}'::jsonb)
    )
  );

  return p_department_id;
end;
$$;

create or replace function public.find_request_approver(
  p_assignment_id uuid,
  p_required_function_id uuid,
  p_starting_level int,
  p_requester_employee_id uuid,
  p_used_employee_ids uuid[] default '{}'
)
returns table (
  approver_employee_id uuid,
  approver_user_profile_id uuid,
  resolved_level int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.employee_assignments;
  v_requester_level int;
  v_search_start_level int;
  v_level int;
  v_authority public.authority_assignments;
  v_required_position_id uuid;
begin
  select *
  into v_assignment
  from public.employee_assignments
  where id = p_assignment_id;

  if v_assignment.id is null then
    return;
  end if;

  select p.authority_level
  into v_requester_level
  from public.positions p
  where p.id = v_assignment.position_id
  limit 1;

  v_search_start_level := greatest(
    coalesce(p_starting_level, 1),
    coalesce(v_requester_level, 0) + 1
  );

  select l.approver_position_id
  into v_required_position_id
  from public.department_approval_ladders l
  where l.department_id = v_assignment.department_id
    and l.authority_level = v_search_start_level
  limit 1;

  for v_level in v_search_start_level..8 loop
    for v_authority in
      select aa.*
      from public.authority_assignments aa
      where aa.authority_level = v_level
        and (
          v_level >= 7
          or aa.function_id = p_required_function_id
        )
        and (
          v_required_position_id is null
          or v_level > v_search_start_level
          or exists (
            select 1
            from public.employee_assignments ea
            where ea.employee_id = aa.employee_id
              and ea.position_id = v_required_position_id
              and ea.is_primary = true
              and ea.effective_to is null
          )
        )
        and aa.is_active = true
        and aa.effective_from <= current_date
        and (aa.effective_to is null or aa.effective_to >= current_date)
        and aa.employee_id <> p_requester_employee_id
        and not (aa.employee_id = any(p_used_employee_ids))
      order by aa.created_at asc
    loop
      if v_level >= 7 or public.scope_matches_assignment(v_level, v_assignment, v_authority) then
        approver_employee_id := v_authority.employee_id;
        select up.id
        into approver_user_profile_id
        from public.user_profiles up
        where up.employee_id = v_authority.employee_id
        limit 1;
        resolved_level := v_level;
        return next;
        return;
      end if;
    end loop;
  end loop;
end;
$$;

grant execute on function public.hr_admin_department_approval_ladders(text, text) to anon, authenticated;
grant execute on function public.hr_admin_set_department_approval_ladder(text, text, uuid, int[], jsonb) to anon, authenticated;
grant execute on function public.admin_department_approval_ladders() to authenticated;
grant execute on function public.admin_set_department_approval_ladder(uuid, int[], jsonb) to authenticated;
grant execute on function public.find_request_approver(uuid, uuid, int, uuid, uuid[]) to authenticated;

notify pgrst, 'reload schema';
