-- Resolve approval route scope from the current store/cluster/area setup.
-- This lets Cluster and Area Managers apply to stores in their scope even when
-- they are not assigned to an individual store.

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
  v_authority_store_id uuid;
  v_authority_cluster_id uuid;
  v_authority_area_id uuid;
begin
  select *
  into v_assignment
  from public.employee_assignments
  where id = p_assignment_id;

  if v_assignment.id is null then
    return;
  end if;

  if v_assignment.store_id is not null then
    select
      coalesce(s.area_id, cl.area_id, v_assignment.area_id),
      coalesce(s.cluster_id, v_assignment.cluster_id)
    into v_assignment.area_id, v_assignment.cluster_id
    from public.stores s
    left join public.clusters cl on cl.id = s.cluster_id
    where s.id = v_assignment.store_id;
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
          v_required_position_id is not null
          or v_level >= 7
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
      v_authority_store_id := v_authority.store_id;
      v_authority_cluster_id := v_authority.cluster_id;
      v_authority_area_id := v_authority.area_id;

      select
        coalesce(v_authority_store_id, ea.store_id),
        coalesce(v_authority_cluster_id, ea.cluster_id, s.cluster_id),
        coalesce(v_authority_area_id, ea.area_id, s.area_id, cl.area_id)
      into v_authority_store_id, v_authority_cluster_id, v_authority_area_id
      from public.employee_assignments ea
      left join public.stores s on s.id = ea.store_id
      left join public.clusters cl on cl.id = coalesce(ea.cluster_id, s.cluster_id)
      where ea.employee_id = v_authority.employee_id
        and ea.is_primary = true
        and ea.effective_to is null
      order by ea.created_at desc
      limit 1;

      v_authority.store_id := v_authority_store_id;
      v_authority.cluster_id := v_authority_cluster_id;
      v_authority.area_id := v_authority_area_id;

      if (
        v_required_position_id is not null
        and (
          (v_level = 2 and v_authority.store_id is not null and v_authority.store_id = v_assignment.store_id)
          or (v_level = 4 and v_authority.cluster_id is not null and v_authority.cluster_id = v_assignment.cluster_id)
          or (v_level = 5 and v_authority.area_id is not null and v_authority.area_id = v_assignment.area_id)
          or v_level not in (2, 4, 5)
        )
      )
        or v_level >= 7
        or public.scope_matches_assignment(v_level, v_assignment, v_authority) then
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

grant execute on function public.find_request_approver(uuid, uuid, int, uuid, uuid[]) to authenticated;

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
  area_id uuid,
  area_name text,
  cluster_id uuid,
  cluster_name text,
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
    scope_a.id as area_id,
    coalesce(scope_a.name, 'N/A') as area_name,
    scope_cl.id as cluster_id,
    coalesce(scope_cl.name, 'N/A') as cluster_name,
    scope_s.id as store_id,
    coalesce(scope_s.name, 'N/A') as store_name,
    c.id as company_id,
    c.name as company_name,
    d.id as department_id,
    d.name as department_name,
    coalesce(aa.authority_level, p.authority_level, 1) as current_authority_level
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
  left join public.departments d on d.id = ea.department_id
  left join lateral (
    select
      current_aa.authority_level,
      current_aa.area_id,
      current_aa.cluster_id,
      current_aa.store_id
    from public.authority_assignments current_aa
    where current_aa.employee_id = e.id
      and current_aa.function_id = ea.function_id
      and current_aa.is_active = true
      and current_aa.effective_to is null
    order by current_aa.created_at desc
    limit 1
  ) aa on true
  left join public.stores scope_s on scope_s.id = coalesce(aa.store_id, ea.store_id)
  left join public.clusters scope_cl on scope_cl.id = coalesce(aa.cluster_id, ea.cluster_id, scope_s.cluster_id)
  left join public.areas scope_a on scope_a.id = coalesce(aa.area_id, ea.area_id, scope_s.area_id, scope_cl.area_id)
  where e.employment_status = 'active'
  order by e.last_name, e.first_name;
end;
$$;

grant execute on function public.hr_admin_authority_candidates(text, text) to anon, authenticated;

notify pgrst, 'reload schema';
