-- Migration 0154: Refresh assigned approvers and verify non-banned status

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

  for v_level in v_search_start_level..8 loop
    v_required_position_id := null;
    v_has_configured_ladder := false;

    select l.approver_position_id, true
    into v_required_position_id, v_has_configured_ladder
    from public.department_approval_ladders l
    where l.department_id = v_assignment.department_id
      and l.authority_level = v_level
    limit 1;

    for v_authority in
      select aa.*
      from public.authority_assignments aa
      where aa.authority_level = v_level
        and (
          v_has_configured_ladder
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
              and ea.effective_from <= current_date
              and (ea.effective_to is null or ea.effective_to >= current_date)
          )
        )
        and aa.is_active = true
        and aa.effective_from <= current_date
        and (aa.effective_to is null or aa.effective_to >= current_date)
        and aa.employee_id <> p_requester_employee_id
        and not (aa.employee_id = any(p_used_employee_ids))
        -- Verify candidate approver is ACTIVE and NOT BANNED
        and exists (
          select 1 from public.employees e
          left join public.user_profiles up on up.employee_id = e.id
          left join auth.users au on au.id = up.auth_user_id
          where e.id = aa.employee_id
            and lower(trim(coalesce(e.employment_status, 'active'))) not in ('banned', 'inactive', 'terminated', 'resigned')
            and coalesce(up.is_active, true) = true
            and (au.banned_until is null or au.banned_until <= now())
        )
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
        and ea.effective_from <= current_date
        and (ea.effective_to is null or ea.effective_to >= current_date)
      order by ea.created_at desc
      limit 1;

      v_authority.store_id := v_authority_store_id;
      v_authority.cluster_id := v_authority_cluster_id;
      v_authority.area_id := v_authority_area_id;

      if (
        v_has_configured_ladder
        and (
          (v_level = 2 and v_authority.store_id is not null and v_authority.store_id = v_assignment.store_id)
          or (v_level = 4 and v_authority.cluster_id is not null and v_authority.cluster_id = v_assignment.cluster_id)
          or (v_level = 5 and v_authority.area_id is not null and v_authority.area_id = v_assignment.area_id)
          or v_level not in (2, 4, 5)
        )
      )
        or (
          not v_has_configured_ladder
          and (
            v_level >= 7
            or public.scope_matches_assignment(v_level, v_assignment, v_authority)
          )
        ) then
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
        and (ea.effective_to is null or ea.effective_to >= current_date)
        and (
          (v_level = 2 and ea.store_id is not null and ea.store_id = v_assignment.store_id)
          or (v_level = 4 and coalesce(ea.cluster_id, s.cluster_id) is not null and coalesce(ea.cluster_id, s.cluster_id) = v_assignment.cluster_id)
          or (v_level = 5 and coalesce(ea.area_id, s.area_id, cl.area_id) is not null and coalesce(ea.area_id, s.area_id, cl.area_id) = v_assignment.area_id)
          or v_level not in (2, 4, 5)
        )
        -- Verify candidate approver is ACTIVE and NOT BANNED
        and exists (
          select 1 from public.employees e
          left join public.user_profiles up2 on up2.employee_id = e.id
          left join auth.users au on au.id = up2.auth_user_id
          where e.id = ea.employee_id
            and lower(trim(coalesce(e.employment_status, 'active'))) not in ('banned', 'inactive', 'terminated', 'resigned')
            and coalesce(up2.is_active, true) = true
            and (au.banned_until is null or au.banned_until <= now())
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

-- Function: admin_refresh_assigned_approvers
create or replace function public.admin_refresh_assigned_approvers()
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_admin record;
  v_request record;
  v_assignment public.employee_assignments;
  v_step record;
  v_approver record;
  v_used_employee_ids uuid[];
  v_request_updated boolean;
  v_has_fallback_step boolean;
  v_first_pending_found boolean;
  v_updated_count int := 0;
  v_step_status text;
begin
  select *
  into v_admin
  from public.admin_desktop_login_check()
  limit 1;

  if v_admin.app_role not in ('admin', 'super_admin') then
    raise exception 'Admin access is required.';
  end if;

  for v_request in
    select id, submitted_by_employee_id as employee_id, 'request' as source_table
    from public.requests
    where status in ('pending', 'waiting', 'admin_fallback', 'needs_admin_review')
    union all
    select id, submitted_by_employee_id as employee_id, 'perk_request' as source_table
    from public.employee_perk_requests
    where status in ('pending', 'waiting', 'admin_fallback', 'needs_admin_review')
  loop
    v_request_updated := false;
    v_has_fallback_step := false;
    v_first_pending_found := false;
    v_used_employee_ids := '{}'::uuid[];

    select ea.*
    into v_assignment
    from public.employee_assignments ea
    where ea.employee_id = v_request.employee_id
      and ea.is_primary = true
      and ea.effective_from <= current_date
      and (ea.effective_to is null or ea.effective_to >= current_date)
    order by ea.created_at desc
    limit 1;

    if v_assignment.id is null then
      select ea.*
      into v_assignment
      from public.employee_assignments ea
      where ea.employee_id = v_request.employee_id
      order by ea.created_at desc
      limit 1;
    end if;

    if v_assignment.id is not null then
      if v_assignment.store_id is not null then
        select
          coalesce(s.area_id, cl.area_id, v_assignment.area_id),
          coalesce(s.cluster_id, v_assignment.cluster_id)
        into v_assignment.area_id, v_assignment.cluster_id
        from public.stores s
        left join public.clusters cl on cl.id = s.cluster_id
        where s.id = v_assignment.store_id;
      end if;

      for v_step in
        select *
        from public.request_approval_steps
        where request_id = v_request.id
        order by step_order asc
      loop
        if v_step.status in ('approved', 'rejected') then
          if v_step.assigned_approver_employee_id is not null then
            v_used_employee_ids := array_append(v_used_employee_ids, v_step.assigned_approver_employee_id);
          end if;
          continue;
        end if;

        select *
        into v_approver
        from public.find_request_approver(
          v_assignment.id,
          coalesce(v_step.required_function_id, v_assignment.function_id),
          v_step.required_level,
          v_request.employee_id,
          v_used_employee_ids
        )
        limit 1;

        if v_approver.approver_employee_id is not null then
          v_step_status := case when not v_first_pending_found then 'pending' else 'waiting' end;
          v_first_pending_found := true;

          if v_step.assigned_approver_employee_id is distinct from v_approver.approver_employee_id
             or v_step.assigned_approver_user_id is distinct from v_approver.approver_user_profile_id
             or v_step.status in ('admin_fallback', 'needs_admin_review')
             or v_step.status is distinct from v_step_status then
            update public.request_approval_steps
            set assigned_approver_employee_id = v_approver.approver_employee_id,
                assigned_approver_user_id = v_approver.approver_user_profile_id,
                required_level = v_approver.resolved_level,
                status = v_step_status,
                skipped_reason = null
            where id = v_step.id;

            v_request_updated := true;
          end if;

          v_used_employee_ids := array_append(v_used_employee_ids, v_approver.approver_employee_id);
        else
          v_step_status := case when not v_first_pending_found then 'admin_fallback' else 'waiting' end;
          v_first_pending_found := true;

          if v_step.assigned_approver_employee_id is not null
             or v_step.status is distinct from v_step_status then
            update public.request_approval_steps
            set assigned_approver_employee_id = null,
                assigned_approver_user_id = null,
                status = v_step_status,
                skipped_reason = 'No active non-banned matching approver found.'
            where id = v_step.id;

            v_request_updated := true;
          end if;

          if v_step_status = 'admin_fallback' then
            v_has_fallback_step := true;
          end if;
        end if;
      end loop;

      if v_has_fallback_step then
        if v_request.source_table = 'request' then
          update public.requests
          set status = 'needs_admin_review', updated_at = now()
          where id = v_request.id and status <> 'needs_admin_review';
        else
          update public.employee_perk_requests
          set status = 'needs_admin_review'
          where id = v_request.id and status <> 'needs_admin_review';
        end if;
      else
        if v_request.source_table = 'request' then
          update public.requests
          set status = 'pending', updated_at = now()
          where id = v_request.id and status in ('needs_admin_review', 'admin_fallback');
        else
          update public.employee_perk_requests
          set status = 'pending'
          where id = v_request.id and status in ('needs_admin_review', 'admin_fallback');
        end if;
      end if;

      if v_request_updated then
        v_updated_count := v_updated_count + 1;
      end if;
    end if;
  end loop;

  if v_updated_count > 0 then
    return 'Successfully refreshed assigned approvers. ' || v_updated_count || ' request(s) updated.';
  else
    return 'All approver assignments are already up to date.';
  end if;
end;
$$;

grant execute on function public.admin_refresh_assigned_approvers() to authenticated;
grant execute on function public.admin_refresh_assigned_approvers() to service_role;

notify pgrst, 'reload schema';
