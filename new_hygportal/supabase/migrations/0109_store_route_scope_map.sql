-- Provide store route rows from store master scope, not employee candidate rows,
-- and remove the broad selected Cluster/Area Manager fallback.

create or replace function public.hr_admin_store_route_scopes(
  p_username text default null,
  p_password text default null
)
returns table (
  department_id uuid,
  department_name text,
  store_id uuid,
  store_name text,
  area_id uuid,
  area_name text,
  cluster_id uuid,
  cluster_name text
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
  select distinct
    d.id,
    d.name,
    s.id,
    s.name,
    coalesce(s.area_id, cl.area_id),
    coalesce(a.name, cluster_area.name, 'N/A'),
    s.cluster_id,
    coalesce(cl.name, 'N/A')
  from public.employee_assignments ea
  join public.departments d on d.id = ea.department_id
  join public.stores s on s.id = ea.store_id
  left join public.clusters cl on cl.id = s.cluster_id
  left join public.areas a on a.id = s.area_id
  left join public.areas cluster_area on cluster_area.id = cl.area_id
  where ea.is_primary = true
    and ea.effective_to is null
    and d.is_active = true
    and s.is_active = true
  order by d.name, s.name;
end;
$$;

grant execute on function public.hr_admin_store_route_scopes(text, text) to anon, authenticated;

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

notify pgrst, 'reload schema';
