-- Migration 0197: Two Approvers for Use Offset and Leave Requests
-- Adjusts Use Offset and Leave request types to require two approvers, matching Overtime and Offset Earn ESARF requests.
-- Applies this adjustment to all new upcoming requests submitted by users.

-- 1. Update public.request_types to require 2 approvers for use_offset and leave
update public.request_types
set approval_count = 2
where code in ('use_offset', 'leave');

-- 2. Drop the single leave approval step trigger and its enforcement function
drop trigger if exists trg_single_leave_approval_step on public.request_approval_steps;
drop function if exists public.enforce_single_leave_approval_step();

-- 3. Update public.decide_approval_step
-- Remove the early cancellation and immediate approval block for 'leave' so that leave requests
-- follow the standard sequential approval workflow (Step 1 promotes Step 2 to pending, and
-- final approval + side effects are applied once all steps are approved).
create or replace function public.decide_approval_step(
  p_step_id uuid,
  p_decision text,
  p_remarks text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_step public.request_approval_steps;
  v_next_step_id uuid;
  v_request_type_code text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  if p_decision not in ('approved', 'rejected') then
    raise exception 'Decision must be approved or rejected.';
  end if;

  if p_decision = 'rejected' and nullif(trim(coalesce(p_remarks, '')), '') is null then
    raise exception 'A rejection reason is required.';
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
  into v_step
  from public.request_approval_steps
  where id = p_step_id
  for update;

  if v_step.id is null then
    raise exception 'Approval step was not found.';
  end if;

  if v_step.assigned_approver_employee_id <> v_profile.employee_id then
    raise exception 'This approval is not assigned to your employee profile.';
  end if;

  if v_step.status <> 'pending' then
    raise exception 'This approval step is not pending.';
  end if;

  select rt.code
  into v_request_type_code
  from public.requests r
  join public.request_types rt on rt.id = r.request_type_id
  where r.id = v_step.request_id
  limit 1;

  update public.request_approval_steps
  set status = p_decision,
      remarks = nullif(trim(coalesce(p_remarks, '')), ''),
      acted_at = now()
  where id = p_step_id;

  if p_decision = 'rejected' then
    update public.requests
    set status = 'rejected',
        rejected_at = now(),
        rejected_reason = nullif(trim(coalesce(p_remarks, '')), ''),
        updated_at = now()
    where id = v_step.request_id;

    update public.request_approval_steps
    set status = 'cancelled'
    where request_id = v_step.request_id
      and status = 'waiting';

    return v_step.request_id;
  end if;

  -- Advance to the next waiting step if present
  select id
  into v_next_step_id
  from public.request_approval_steps
  where request_id = v_step.request_id
    and status = 'waiting'
  order by step_order asc
  limit 1;

  if v_next_step_id is not null then
    update public.request_approval_steps
    set status = 'pending'
    where id = v_next_step_id;
  else
    update public.requests
    set status = 'approved',
        final_approved_at = now(),
        updated_at = now()
    where id = v_step.request_id;

    perform public.apply_offset_side_effects(v_step.request_id);
    perform public.apply_leave_side_effects(v_step.request_id);
  end if;

  return v_step.request_id;
end;
$$;

grant execute on function public.decide_approval_step(uuid, text, text) to authenticated;

-- 4. Update public.submit_leave_request
-- Generates two approval steps (Step 1 'pending', Step 2 'waiting') based on approval_level_routes and approval_count.
create or replace function public.submit_leave_request(
  p_leave_type text,
  p_leave_category text,
  p_start_date date,
  p_end_date date,
  p_paid_days numeric,
  p_unpaid_days numeric,
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
  v_total_days numeric;
  v_leave_type text;
  v_paid_days numeric;
  v_unpaid_days numeric;
  v_available_days numeric;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  if p_end_date < p_start_date then
    raise exception 'End date cannot be earlier than start date.';
  end if;

  v_leave_type := trim(coalesce(p_leave_type, ''));
  if v_leave_type not in ('With Pay', 'Without Pay', 'Both') then
    raise exception 'Leave type must be With Pay, Without Pay, or Both.';
  end if;

  if nullif(trim(p_leave_category), '') is null then
    raise exception 'Leave category is required.';
  end if;

  if nullif(trim(p_reason), '') is null then
    raise exception 'Reason is required.';
  end if;

  v_total_days := (p_end_date - p_start_date) + 1;

  if v_leave_type = 'With Pay' then
    v_paid_days := v_total_days;
    v_unpaid_days := 0;
  elsif v_leave_type = 'Without Pay' then
    v_paid_days := 0;
    v_unpaid_days := v_total_days;
  else
    v_paid_days := coalesce(p_paid_days, 0);
    v_unpaid_days := coalesce(p_unpaid_days, 0);
  end if;

  if v_paid_days < 0 or v_unpaid_days < 0 then
    raise exception 'Leave days cannot be negative.';
  end if;

  if round((v_paid_days + v_unpaid_days)::numeric, 2) <> round(v_total_days::numeric, 2) then
    raise exception 'Paid and unpaid leave days must equal total leave days.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  if v_profile.id is null or v_profile.employee_id is null then
    raise exception 'Your login is not linked to an employee profile.';
  end if;

  -- Synchronize and validate against available usable leave days for requested start date
  v_available_days := public.get_available_leave_days(v_profile.employee_id, coalesce(p_start_date, current_date));
  if v_paid_days > v_available_days then
    raise exception 'Insufficient paid leave credits. Available usable paid leave: % day(s).', v_available_days;
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
  where code = 'leave'
    and is_active = true;

  if v_request_type.id is null then
    raise exception 'Leave request type is not configured.';
  end if;

  insert into public.requests (
    request_type_id,
    submitted_by_employee_id,
    submitted_by_user_id,
    company_id,
    department_id,
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
    v_assignment.department_id,
    v_assignment.area_id,
    v_assignment.cluster_id,
    v_assignment.store_id,
    v_assignment.position_id,
    v_position.authority_level,
    'pending'
  )
  returning id into v_request_id;

  insert into public.leave_request_details (
    request_id,
    leave_type,
    leave_category,
    start_date,
    end_date,
    total_days,
    paid_days,
    unpaid_days,
    reason
  )
  values (
    v_request_id,
    v_leave_type,
    trim(p_leave_category),
    p_start_date,
    p_end_date,
    v_total_days,
    v_paid_days,
    v_unpaid_days,
    trim(p_reason)
  );

  -- Route approval steps using approval_level_routes (up to v_request_type.approval_count = 2)
  for v_route in
    select distinct on (step_order) *
    from public.approval_level_routes
    where requester_level = v_position.authority_level
      and (department_id = v_assignment.department_id or department_id is null)
    order by
      step_order asc,
      case when department_id = v_assignment.department_id then 0 else 1 end
    limit v_request_type.approval_count
  loop
    select *
    into v_approver
    from public.find_request_approver(
      v_assignment.id,
      v_assignment.function_id,
      v_route.approver_level,
      v_profile.employee_id,
      v_used_employee_ids
    )
    limit 1;

    if v_approver.approver_employee_id is not null then
      v_step_order := v_step_order + 1;

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
        v_assignment.function_id,
        v_approver.resolved_level,
        v_approver.approver_employee_id,
        v_approver.approver_user_profile_id,
        case when v_step_order = 1 then 'pending' else 'waiting' end
      );

      v_used_employee_ids := array_append(v_used_employee_ids, v_approver.approver_employee_id);
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
    'Leave submitted',
    'Your leave request was submitted.',
    'request',
    v_request_id
  );

  return v_request_id;
end;
$$;

grant execute on function public.submit_leave_request(text, text, date, date, numeric, numeric, text) to authenticated;

-- 5. Update public.submit_time_request
-- Ensures department_id is populated on public.requests and routes steps up to approval_count (now 2 for use_offset).
create or replace function public.submit_time_request(
  p_request_type_code text,
  p_date_from date,
  p_date_to date,
  p_time_from time,
  p_time_to time,
  p_total_hours numeric,
  p_reason text,
  p_time_schedule text,
  p_day_off text,
  p_payroll_class text,
  p_transaction_type text default null
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
  v_balance numeric;
  v_transaction_type text;
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

  if nullif(trim(p_time_schedule), '') is null then
    raise exception 'Time schedule is required.';
  end if;

  if nullif(trim(p_day_off), '') is null then
    raise exception 'Day off is required.';
  end if;

  if nullif(trim(p_payroll_class), '') is null then
    raise exception 'Payroll class is required.';
  end if;

  v_transaction_type := coalesce(
    nullif(trim(p_transaction_type), ''),
    case p_request_type_code
      when 'overtime' then 'OT'
      when 'offset_earn' then 'Offset'
      when 'use_offset' then 'Use Offset'
      else p_request_type_code
    end
  );

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
    department_id,
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
    v_assignment.department_id,
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
    reason,
    time_schedule,
    day_off,
    payroll_class,
    transaction_type
  )
  values (
    v_request_id,
    p_date_from,
    p_date_to,
    p_time_from,
    p_time_to,
    p_total_hours,
    nullif(trim(p_reason), ''),
    trim(p_time_schedule),
    trim(p_day_off),
    trim(p_payroll_class),
    v_transaction_type
  );

  for v_route in
    select distinct on (step_order) *
    from public.approval_level_routes
    where requester_level = v_position.authority_level
      and (department_id = v_assignment.department_id or department_id is null)
    order by
      step_order asc,
      case when department_id = v_assignment.department_id then 0 else 1 end
    limit v_request_type.approval_count
  loop
    select *
    into v_approver
    from public.find_request_approver(
      v_assignment.id,
      v_assignment.function_id,
      v_route.approver_level,
      v_profile.employee_id,
      v_used_employee_ids
    )
    limit 1;

    if v_approver.approver_employee_id is not null then
      v_step_order := v_step_order + 1;

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
        v_assignment.function_id,
        v_approver.resolved_level,
        v_approver.approver_employee_id,
        v_approver.approver_user_profile_id,
        case when v_step_order = 1 then 'pending' else 'waiting' end
      );

      v_used_employee_ids := array_append(v_used_employee_ids, v_approver.approver_employee_id);
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
    'Your ' || v_transaction_type || ' request was submitted.',
    'request',
    v_request_id
  );

  return v_request_id;
end;
$$;

grant execute on function public.submit_time_request(text, date, date, time, time, numeric, text, text, text, text, text) to authenticated;

notify pgrst, 'reload schema';
