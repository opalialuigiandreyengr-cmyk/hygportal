-- Submit overtime / offset time requests and generate approval steps.

create or replace function public.scope_matches_assignment(
  p_level int,
  p_assignment public.employee_assignments,
  p_authority public.authority_assignments
)
returns boolean
language plpgsql
stable
as $$
begin
  if p_level = 2 then
    return p_authority.store_id is not null and p_authority.store_id = p_assignment.store_id;
  elsif p_level = 3 then
    return (
      p_authority.company_id = p_assignment.company_id
      and (
        p_authority.department_id is null
        or p_assignment.department_id is null
        or p_authority.department_id = p_assignment.department_id
      )
    );
  elsif p_level = 4 then
    return (
      (p_assignment.cluster_id is not null and p_authority.cluster_id = p_assignment.cluster_id)
      or (p_assignment.cluster_id is null and p_authority.company_id = p_assignment.company_id)
    );
  elsif p_level = 5 then
    return (
      (p_assignment.area_id is not null and p_authority.area_id = p_assignment.area_id)
      or (p_assignment.area_id is null and p_authority.company_id = p_assignment.company_id)
    );
  else
    return p_authority.company_id is not null and p_authority.company_id = p_assignment.company_id;
  end if;
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
  v_level int;
  v_authority public.authority_assignments;
begin
  select *
  into v_assignment
  from public.employee_assignments
  where id = p_assignment_id;

  if v_assignment.id is null then
    return;
  end if;

  for v_level in p_starting_level..8 loop
    for v_authority in
      select aa.*
      from public.authority_assignments aa
      where aa.function_id = p_required_function_id
        and aa.authority_level = v_level
        and aa.is_active = true
        and aa.effective_from <= current_date
        and (aa.effective_to is null or aa.effective_to >= current_date)
        and aa.employee_id <> p_requester_employee_id
        and not (aa.employee_id = any(p_used_employee_ids))
      order by aa.created_at asc
    loop
      if public.scope_matches_assignment(v_level, v_assignment, v_authority) then
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

  return;
end;
$$;

create or replace function public.submit_time_request(
  p_request_type_code text,
  p_date_from date,
  p_date_to date,
  p_time_from time,
  p_time_to time,
  p_total_hours numeric,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_assignment public.employee_assignments;
  v_position public.positions;
  v_request_type public.request_types;
  v_request_id uuid;
  v_route record;
  v_approver record;
  v_step_order int := 0;
  v_used_employee_ids uuid[] := '{}';
  v_first_pending_set boolean := false;
  v_balance numeric;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  if p_request_type_code not in ('overtime', 'offset_earn', 'use_offset') then
    raise exception 'Unsupported time request type: %', p_request_type_code;
  end if;

  if p_date_to < p_date_from then
    raise exception 'Date To cannot be earlier than Date From.';
  end if;

  if p_total_hours <= 0 then
    raise exception 'Total hours must be greater than zero.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  if v_profile.id is null or v_profile.employee_id is null then
    raise exception 'Your login is not linked to an employee profile.';
  end if;

  select *
  into v_assignment
  from public.employee_assignments
  where employee_id = v_profile.employee_id
    and is_primary = true
    and effective_from <= current_date
    and (effective_to is null or effective_to >= current_date)
  order by created_at desc
  limit 1;

  if v_assignment.id is null then
    raise exception 'No active employee assignment found.';
  end if;

  select *
  into v_position
  from public.positions
  where id = v_assignment.position_id;

  if v_position.id is null then
    raise exception 'No position found for active assignment.';
  end if;

  select *
  into v_request_type
  from public.request_types
  where code = p_request_type_code
    and is_active = true;

  if v_request_type.id is null then
    raise exception 'Request type is not configured: %', p_request_type_code;
  end if;

  if v_request_type.requires_offset_credit_check then
    select coalesce(balance_hours, 0)
    into v_balance
    from public.offset_balances
    where employee_id = v_profile.employee_id;

    if coalesce(v_balance, 0) < p_total_hours then
      raise exception 'Insufficient offset balance. Available %, requested %.', coalesce(v_balance, 0), p_total_hours;
    end if;
  end if;

  insert into public.requests (
    request_type_id,
    submitted_by_employee_id,
    submitted_by_user_id,
    company_id,
    area_id,
    cluster_id,
    store_id,
    requester_position_id,
    requester_level,
    status
  )
  values (
    v_request_type.id,
    v_profile.employee_id,
    v_profile.id,
    v_assignment.company_id,
    v_assignment.area_id,
    v_assignment.cluster_id,
    v_assignment.store_id,
    v_assignment.position_id,
    v_position.authority_level,
    'pending'
  )
  returning id into v_request_id;

  insert into public.time_request_details (
    request_id,
    date_from,
    date_to,
    time_from,
    time_to,
    total_hours,
    reason
  )
  values (
    v_request_id,
    p_date_from,
    p_date_to,
    p_time_from,
    p_time_to,
    p_total_hours,
    nullif(trim(p_reason), '')
  );

  for v_route in
    select *
    from public.approval_level_routes
    where requester_level = v_position.authority_level
    order by step_order asc
    limit v_request_type.approval_count
  loop
    v_step_order := v_step_order + 1;

    select *
    into v_approver
    from public.find_request_approver(
      v_assignment.id,
      v_request_type.required_function_id,
      v_route.approver_level,
      v_profile.employee_id,
      v_used_employee_ids
    )
    limit 1;

    if v_approver.approver_employee_id is null then
      insert into public.request_approval_steps (
        request_id,
        step_order,
        required_function_id,
        required_level,
        status,
        skipped_reason
      )
      values (
        v_request_id,
        v_step_order,
        v_request_type.required_function_id,
        v_route.approver_level,
        case when v_first_pending_set then 'waiting' else 'admin_fallback' end,
        'No matching approver found.'
      );

      if not v_first_pending_set then
        update public.requests
        set status = 'needs_admin_review'
        where id = v_request_id;
        v_first_pending_set := true;
      end if;
    else
      insert into public.request_approval_steps (
        request_id,
        step_order,
        required_function_id,
        required_level,
        assigned_approver_employee_id,
        assigned_approver_user_id,
        status
      )
      values (
        v_request_id,
        v_step_order,
        v_request_type.required_function_id,
        v_approver.resolved_level,
        v_approver.approver_employee_id,
        v_approver.approver_user_profile_id,
        case when v_first_pending_set then 'waiting' else 'pending' end
      );

      v_used_employee_ids := array_append(v_used_employee_ids, v_approver.approver_employee_id);
      v_first_pending_set := true;
    end if;
  end loop;

  if v_step_order = 0 then
    update public.requests
    set status = 'needs_admin_review'
    where id = v_request_id;
  end if;

  insert into public.notifications (
    employee_id,
    user_profile_id,
    title,
    message,
    link_type,
    link_id
  )
  values (
    v_profile.employee_id,
    v_profile.id,
    'Request submitted',
    'Your ' || replace(p_request_type_code, '_', ' ') || ' request was submitted.',
    'request',
    v_request_id
  );

  return v_request_id;
end;
$$;

grant execute on function public.submit_time_request(text, date, date, time, time, numeric, text) to authenticated;
