-- Migration 0182: Preserve Manually Reassigned Approvers on Refresh
-- When an admin manually reassigns an approver for a request step, mark that step as manually reassigned (is_reassigned = true).
-- During admin_refresh_assigned_approvers(), do NOT revert manually reassigned steps back to default approval route approvers.

-- 1. Add is_reassigned column to public.request_approval_steps
alter table public.request_approval_steps
  add column if not exists is_reassigned boolean not null default false;

-- 2. Update public.admin_reassign_request_approver to flag is_reassigned = true
drop function if exists public.admin_reassign_request_approver(uuid, uuid, uuid);
drop function if exists public.admin_reassign_request_approver(uuid, uuid);

create or replace function public.admin_reassign_request_approver(
  p_request_id uuid,
  p_new_approver_employee_id uuid,
  p_step_id uuid default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_step_id uuid;
  v_user_profile_id uuid;
  v_target_step_order int;
  v_prev_unapproved_count int;
begin
  -- Get user_profile_id of the new approver from user_profiles table
  select id
  into v_user_profile_id
  from public.user_profiles
  where employee_id = p_new_approver_employee_id
  limit 1;

  if p_step_id is not null then
    v_target_step_id := p_step_id;
  else
    -- Find step that needs approver assignment
    select id
    into v_target_step_id
    from public.request_approval_steps
    where request_id = p_request_id
      and (assigned_approver_employee_id is null or status in ('admin_fallback', 'needs_admin_review', 'pending', 'waiting'))
    order by
      case when status = 'admin_fallback' then 1
           when assigned_approver_employee_id is null then 2
           when status = 'needs_admin_review' then 3
           when status = 'pending' then 4
           else 5 end,
      step_order asc
    limit 1;
  end if;

  if v_target_step_id is null then
    raise exception 'No editable approval step found for this request';
  end if;

  -- Get step_order of target step
  select step_order
  into v_target_step_order
  from public.request_approval_steps
  where id = v_target_step_id;

  -- Count unapproved previous steps for this request
  select count(*)
  into v_prev_unapproved_count
  from public.request_approval_steps
  where request_id = p_request_id
    and step_order < v_target_step_order
    and status not in ('approved', 'skipped');

  -- Update approval step: set status to 'pending' if all previous steps are approved, otherwise keep 'waiting'
  -- Set is_reassigned = true to lock in the manual approver assignment
  update public.request_approval_steps
  set assigned_approver_employee_id = p_new_approver_employee_id,
      assigned_approver_user_id = v_user_profile_id,
      status = case when v_prev_unapproved_count = 0 then 'pending' else 'waiting' end,
      skipped_reason = null,
      is_reassigned = true
  where id = v_target_step_id;

  -- Update requests status from admin_fallback / needs_admin_review to pending
  update public.requests
  set status = 'pending',
      updated_at = now()
  where id = p_request_id
    and status in ('admin_fallback', 'needs_admin_review');

  -- Update employee_perk_requests status from admin_fallback / needs_admin_review to pending
  update public.employee_perk_requests
  set status = 'pending'
  where id = p_request_id
    and status in ('admin_fallback', 'needs_admin_review');

  return 'Approver reassigned successfully.';
end;
$$;

-- Overload with 2 parameters (p_request_id, p_new_approver_employee_id)
create or replace function public.admin_reassign_request_approver(
  p_request_id uuid,
  p_new_approver_employee_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.admin_reassign_request_approver(
    p_request_id => p_request_id,
    p_new_approver_employee_id => p_new_approver_employee_id,
    p_step_id => null
  );
end;
$$;

grant execute on function public.admin_reassign_request_approver(uuid, uuid, uuid) to authenticated;
grant execute on function public.admin_reassign_request_approver(uuid, uuid, uuid) to service_role;
grant execute on function public.admin_reassign_request_approver(uuid, uuid) to authenticated;
grant execute on function public.admin_reassign_request_approver(uuid, uuid) to service_role;

-- 3. Update public.admin_refresh_assigned_approvers to preserve manually reassigned steps
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
  v_requester_level int;
  v_target_route_level int;
  v_last_resolved_level int;
  v_existing_step_count int;
  v_approval_count int;
  v_route record;
  v_max_step_order int;
begin
  select *
  into v_admin
  from public.admin_desktop_login_check()
  limit 1;

  if v_admin.app_role not in ('admin', 'super_admin') then
    raise exception 'Admin access is required.';
  end if;

  for v_request in
    select id, submitted_by_employee_id as employee_id, 'request' as source_table, request_type_id
    from public.requests
    where status in ('pending', 'waiting', 'admin_fallback', 'needs_admin_review')
    union all
    select id, submitted_by_employee_id as employee_id, 'perk_request' as source_table, null::uuid as request_type_id
    from public.employee_perk_requests
    where status in ('pending', 'waiting', 'admin_fallback', 'needs_admin_review')
  loop
    v_request_updated := false;
    v_has_fallback_step := false;
    v_first_pending_found := false;
    v_used_employee_ids := '{}'::uuid[];
    v_last_resolved_level := 0;

    -- Get employee assignment for requester
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

      -- Get requester authority level
      select p.authority_level
      into v_requester_level
      from public.positions p
      where p.id = v_assignment.position_id
      limit 1;

      -- Get expected approval count for this request type
      if v_request.source_table = 'request' and v_request.request_type_id is not null then
        select approval_count
        into v_approval_count
        from public.request_types
        where id = v_request.request_type_id;
      else
        v_approval_count := 1;
      end if;
      v_approval_count := coalesce(v_approval_count, 2);

      -- Check existing steps count
      select count(*), coalesce(max(step_order), 0)
      into v_existing_step_count, v_max_step_order
      from public.request_approval_steps
      where request_id = v_request.id;

      -- If request has NO steps at all, create them based on approval_level_routes
      if v_existing_step_count = 0 and v_request.source_table = 'request' then
        for v_route in
          select distinct on (step_order) *
          from public.approval_level_routes
          where requester_level = coalesce(v_requester_level, 1)
            and (department_id = v_assignment.department_id or department_id is null)
          order by
            step_order asc,
            case when department_id = v_assignment.department_id then 0 else 1 end
          limit v_approval_count
        loop
          select *
          into v_approver
          from public.find_request_approver(
            v_assignment.id,
            v_assignment.function_id,
            v_route.approver_level,
            v_request.employee_id,
            v_used_employee_ids
          )
          limit 1;

          if v_approver.approver_employee_id is not null then
            v_max_step_order := v_max_step_order + 1;
            v_step_status := case when not v_first_pending_found then 'pending' else 'waiting' end;
            v_first_pending_found := true;

            insert into public.request_approval_steps (
              request_id,
              step_order,
              required_function_id,
              required_level,
              assigned_approver_employee_id,
              assigned_approver_user_id,
              status,
              is_reassigned
            )
            values (
              v_request.id,
              v_max_step_order,
              v_assignment.function_id,
              v_approver.resolved_level,
              v_approver.approver_employee_id,
              v_approver.approver_user_profile_id,
              v_step_status,
              false
            );

            v_used_employee_ids := array_append(v_used_employee_ids, v_approver.approver_employee_id);
            v_request_updated := true;
          else
            v_max_step_order := v_max_step_order + 1;
            v_step_status := case when not v_first_pending_found then 'admin_fallback' else 'waiting' end;
            v_first_pending_found := true;

            insert into public.request_approval_steps (
              request_id,
              step_order,
              required_function_id,
              required_level,
              assigned_approver_employee_id,
              assigned_approver_user_id,
              status,
              skipped_reason,
              is_reassigned
            )
            values (
              v_request.id,
              v_max_step_order,
              v_assignment.function_id,
              v_route.approver_level,
              null,
              null,
              v_step_status,
              'No active non-banned matching approver found.',
              false
            );

            v_request_updated := true;
            if v_step_status = 'admin_fallback' then
              v_has_fallback_step := true;
            end if;
          end if;
        end loop;
      else
        -- Request ALREADY has steps: refresh existing steps
        for v_step in
          select *
          from public.request_approval_steps
          where request_id = v_request.id
          order by step_order asc
        loop
          -- Already acted steps (approved/rejected) are never altered
          if v_step.status in ('approved', 'rejected') then
            if v_step.assigned_approver_employee_id is not null then
              v_used_employee_ids := array_append(v_used_employee_ids, v_step.assigned_approver_employee_id);
            end if;
            v_last_resolved_level := greatest(v_last_resolved_level, coalesce(v_step.required_level, 1));
            continue;
          end if;

          -- Manually reassigned steps: preserve the reassigned approver, do NOT recalculate from default routes!
          if coalesce(v_step.is_reassigned, false) = true and v_step.assigned_approver_employee_id is not null then
            v_step_status := case when not v_first_pending_found then 'pending' else 'waiting' end;
            v_first_pending_found := true;

            if v_step.status in ('admin_fallback', 'needs_admin_review')
               or v_step.status is distinct from v_step_status then
              update public.request_approval_steps
              set status = v_step_status,
                  skipped_reason = null
              where id = v_step.id;

              v_request_updated := true;
            end if;

            v_used_employee_ids := array_append(v_used_employee_ids, v_step.assigned_approver_employee_id);
            v_last_resolved_level := greatest(v_last_resolved_level, coalesce(v_step.required_level, 1));
            continue;
          end if;

          -- Normal steps: look up target level from approval_level_routes for this step_order
          select r.approver_level
          into v_target_route_level
          from public.approval_level_routes r
          where r.requester_level = coalesce(v_requester_level, 1)
            and (r.department_id = v_assignment.department_id or r.department_id is null)
            and r.step_order = v_step.step_order
          order by case when r.department_id = v_assignment.department_id then 0 else 1 end
          limit 1;

          select *
          into v_approver
          from public.find_request_approver(
            v_assignment.id,
            coalesce(v_step.required_function_id, v_assignment.function_id),
            greatest(coalesce(v_target_route_level, v_step.required_level, 1), coalesce(v_last_resolved_level + 1, 1)),
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
                  skipped_reason = null,
                  is_reassigned = false
              where id = v_step.id;

              v_request_updated := true;
            end if;

            v_last_resolved_level := v_approver.resolved_level;
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
                  skipped_reason = 'No active non-banned matching approver found.',
                  is_reassigned = false
              where id = v_step.id;

              v_request_updated := true;
            end if;

            if v_step_status = 'admin_fallback' then
              v_has_fallback_step := true;
            end if;
          end if;
        end loop;
      end if;

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
