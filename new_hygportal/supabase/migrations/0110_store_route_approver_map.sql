-- Compute the store route map in SQL using the exact store -> cluster -> area
-- logic from the Store / Cluster / Area master data.

drop function if exists public.hr_admin_store_route_scopes(text, text);

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
  cluster_name text,
  route_approvers jsonb
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
  with store_scopes as (
    select distinct
      d.id as department_id,
      d.name as department_name,
      s.id as store_id,
      s.name as store_name,
      s.company_id,
      coalesce(s.area_id, cl.area_id) as area_id,
      coalesce(a.name, cluster_area.name, 'N/A') as area_name,
      s.cluster_id,
      coalesce(cl.name, 'N/A') as cluster_name
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
  )
  select
    scope.department_id,
    scope.department_name,
    scope.store_id,
    scope.store_name,
    scope.area_id,
    scope.area_name,
    scope.cluster_id,
    scope.cluster_name,
    coalesce((
      select jsonb_object_agg(level_approvers.level_key, level_approvers.names)
      from (
        select
          l.authority_level::text as level_key,
          coalesce((
            select jsonb_agg(named_approvers.full_name order by named_approvers.full_name)
            from (
              select distinct
                upper(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix))) as full_name
              from public.employees e
              join lateral (
                select *
                from public.employee_assignments employee_scope
                where employee_scope.employee_id = e.id
                  and employee_scope.is_primary = true
                  and employee_scope.effective_to is null
                order by employee_scope.created_at desc
                limit 1
              ) ea on true
              join public.positions p on p.id = ea.position_id
              left join public.stores employee_store on employee_store.id = ea.store_id
              left join public.clusters employee_cluster
                on employee_cluster.id = coalesce(ea.cluster_id, employee_store.cluster_id)
              left join lateral (
                select current_aa.*
                from public.authority_assignments current_aa
                where current_aa.employee_id = e.id
                  and current_aa.function_id = ea.function_id
                  and current_aa.is_active = true
                  and current_aa.effective_from <= current_date
                  and (current_aa.effective_to is null or current_aa.effective_to >= current_date)
                order by current_aa.created_at desc
                limit 1
              ) aa on true
              where e.employment_status = 'active'
                and coalesce(aa.authority_level, p.authority_level, 1) = l.authority_level
                and (
                  l.approver_position_id is null
                  or ea.position_id = l.approver_position_id
                )
                and (
                  (l.authority_level = 2 and coalesce(ea.store_id, aa.store_id) = scope.store_id)
                  or (
                    l.authority_level = 4
                    and scope.cluster_id is not null
                    and coalesce(ea.cluster_id, employee_store.cluster_id, aa.cluster_id) = scope.cluster_id
                  )
                  or (
                    l.authority_level = 5
                    and scope.area_id is not null
                    and coalesce(ea.area_id, employee_store.area_id, employee_cluster.area_id, aa.area_id) = scope.area_id
                  )
                  or (
                    l.authority_level not in (2, 4, 5)
                    and coalesce(ea.company_id, aa.company_id) = scope.company_id
                  )
                )
            ) named_approvers
          ), '[]'::jsonb) as names
        from public.department_approval_ladders l
        where l.department_id = scope.department_id
          and l.authority_level > 1
      ) level_approvers
    ), '{}'::jsonb) as route_approvers
  from store_scopes scope
  order by scope.department_name, scope.store_name;
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
        coalesce(ea.store_id, v_authority_store_id),
        coalesce(ea.cluster_id, s.cluster_id, v_authority_cluster_id),
        coalesce(ea.area_id, s.area_id, cl.area_id, v_authority_area_id)
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
