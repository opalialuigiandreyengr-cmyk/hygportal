-- Resolve explicitly selected route roles from the employee's active position
-- when no authority_assignments row exists yet.

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
  v_search_end_level int;
  v_level int;
  v_authority public.authority_assignments;
  v_required_position_id uuid;
  v_has_configured_ladder boolean := false;
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

  select l.approver_position_id, true
  into v_required_position_id, v_has_configured_ladder
  from public.department_approval_ladders l
  where l.department_id = v_assignment.department_id
    and l.authority_level = v_search_start_level
  limit 1;

  v_search_end_level := case
    when v_has_configured_ladder then v_search_start_level
    else 8
  end;

  for v_level in v_search_start_level..v_search_end_level loop
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

    if v_required_position_id is not null then
      select ea.employee_id, up.id
      into approver_employee_id, approver_user_profile_id
      from public.employee_assignments ea
      left join public.stores s
        on s.id = ea.store_id
      left join public.clusters cl
        on cl.id = coalesce(ea.cluster_id, s.cluster_id)
      left join public.user_profiles up
        on up.employee_id = ea.employee_id
      where ea.position_id = v_required_position_id
        and ea.employee_id <> p_requester_employee_id
        and not (ea.employee_id = any(p_used_employee_ids))
        and ea.is_primary = true
        and ea.effective_from <= current_date
        and ea.effective_to is null
        and (
          (v_level = 2 and ea.store_id is not null and ea.store_id = v_assignment.store_id)
          or (v_level = 4 and coalesce(ea.cluster_id, s.cluster_id) is not null and coalesce(ea.cluster_id, s.cluster_id) = v_assignment.cluster_id)
          or (v_level = 5 and coalesce(ea.area_id, s.area_id, cl.area_id) is not null and coalesce(ea.area_id, s.area_id, cl.area_id) = v_assignment.area_id)
          or v_level not in (2, 4, 5)
        )
      order by ea.created_at asc
      limit 1;

      if approver_employee_id is not null then
        resolved_level := v_level;
        return next;
        return;
      end if;
    end if;
  end loop;
end;
$$;

grant execute on function public.find_request_approver(uuid, uuid, int, uuid, uuid[]) to authenticated;

with affected_steps as (
  select
    ras.id as step_id,
    ras.request_id,
    r.submitted_by_employee_id,
    ea.id as assignment_id,
    ea.function_id,
    route.approver_level as expected_level,
    array_remove(array_agg(prev.assigned_approver_employee_id) filter (where prev.assigned_approver_employee_id is not null), null) as used_employee_ids
  from public.request_approval_steps ras
  join public.requests r
    on r.id = ras.request_id
  join public.employee_assignments ea
    on ea.employee_id = r.submitted_by_employee_id
   and ea.is_primary = true
   and ea.effective_to is null
  join public.approval_level_routes route
    on route.department_id = ea.department_id
   and route.requester_level = r.requester_level
   and route.step_order = ras.step_order
  left join public.request_approval_steps prev
    on prev.request_id = ras.request_id
   and prev.step_order < ras.step_order
  where route.approver_position_id is not null
    and ras.required_level = route.approver_level
    and ras.assigned_approver_employee_id is null
    and ras.status in ('waiting', 'pending', 'admin_fallback')
  group by ras.id, ras.request_id, r.submitted_by_employee_id, ea.id, ea.function_id, route.approver_level
),
resolved as (
  select
    affected_steps.step_id,
    approver.approver_employee_id,
    approver.approver_user_profile_id
  from affected_steps
  join lateral public.find_request_approver(
    affected_steps.assignment_id,
    affected_steps.function_id,
    affected_steps.expected_level,
    affected_steps.submitted_by_employee_id,
    coalesce(affected_steps.used_employee_ids, '{}'::uuid[])
  ) approver on true
)
update public.request_approval_steps ras
set assigned_approver_employee_id = resolved.approver_employee_id,
    assigned_approver_user_id = resolved.approver_user_profile_id,
    status = case when ras.status = 'admin_fallback' then 'pending' else ras.status end,
    skipped_reason = null
from resolved
where ras.id = resolved.step_id;

notify pgrst, 'reload schema';
