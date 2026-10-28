-- Migration 0211: Ensure Pre-approved status is STRICTLY for scheduled OT or Offset only
-- 1. Updates submit_time_request so that:
--    - Regular ESARF requests (FIO, OB, UT, CS, or regular OT) ALWAYS get initial status 'pending'
--    - ONLY scheduled Overtime or Offset (applied strictly ahead of time for future date/time) get 'pre_approved'
-- 2. Updates approve_request so that when an intermediate approval step approves a pre_approved request,
--    its request status is updated to 'pending'.
-- 3. Backfills existing requests in public.requests:
--    - Any request with status = 'pre_approved' that is NOT pure OT or Offset (e.g. FIO, OB, UT, CS) is updated to 'pending'
--    - Any request with status = 'pre_approved' where the scheduled date/time has already arrived or passed is updated to 'pending'
--    - Any request with status = 'pre_approved' where approval steps have already been approved is updated to 'pending'
--    - Any request with status = 'pre_approved' where photo proof is already attached is updated to 'pending'
-- 4. Activates the next/first approval step from 'waiting' to 'pending' for any backfilled requests.

-- 1. Update public.submit_time_request
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
  v_new_balance numeric;
  v_transaction_type text;
  v_is_use_offset boolean := false;
  v_effective_hours numeric := coalesce(p_total_hours, 0);
  v_is_scheduled_ot boolean := false;
  v_initial_status text := 'pending';
  v_current_date_ph date;
  v_current_time_ph time;
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

  v_is_use_offset := (
    p_request_type_code = 'use_offset'
    or lower(v_transaction_type) like '%use_offset%'
    or lower(v_transaction_type) like '%use offset%'
    or lower(trim(coalesce(p_reason, ''))) like '%(use offset)%'
  );

  -- Offset earn rules: Minimum 4 hours required; 4-7.99h normalized to 4h, 8h+ normalized to 8h
  if (p_request_type_code = 'offset_earn' or lower(v_transaction_type) like '%offset%') and not v_is_use_offset then
    if v_effective_hours < 4 then
      raise exception 'Minimum offsetable hours not met. A minimum of 4.00 hours is required for offset.';
    elsif v_effective_hours >= 8 then
      v_effective_hours := 8;
    else
      v_effective_hours := 4;
    end if;
  end if;

  -- Determine if OT/Offset is applied ahead of time (scheduled OT/Offset) using Philippine Standard Time (Asia/Manila)
  v_current_date_ph := (timezone('Asia/Manila', now()))::date;
  v_current_time_ph := (timezone('Asia/Manila', now()))::time;

  -- Pre-approved status is STRICTLY for scheduled OT or Offset applied ahead of time.
  -- Regular ESARF requests (FIO, OB, UT, CS, or regular OT) MUST ALWAYS start as 'pending'.
  v_is_scheduled_ot := (
    (
      p_date_from > v_current_date_ph
      or (p_date_from = v_current_date_ph and p_time_from > v_current_time_ph)
    )
    and not v_is_use_offset
    -- Exclude requests where photo proof is already attached (indicates work already performed)
    and coalesce(p_reason, '') not like '%[Proof:%'
    -- Exclude regular non-OT/Offset ESARF types:
    and lower(v_transaction_type) not like '%fio%'
    and lower(v_transaction_type) not like '%punch%'
    and lower(v_transaction_type) not like '%business%'
    and lower(v_transaction_type) not like '%ob%'
    and lower(v_transaction_type) not like '%undertime%'
    and lower(v_transaction_type) not like '%ut%'
    and lower(v_transaction_type) not like '%change of schedule%'
    and lower(v_transaction_type) not like '%cs%'
    -- Must be strictly Overtime or Offset:
    and (
      lower(v_transaction_type) = 'ot'
      or lower(v_transaction_type) = 'overtime'
      or lower(v_transaction_type) like '%(ot)%'
      or p_request_type_code = 'offset_earn'
      or lower(v_transaction_type) like '%offset%'
    )
  );

  if v_is_scheduled_ot then
    v_initial_status := 'pre_approved';
  else
    v_initial_status := 'pending';
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

  if v_is_use_offset then
    select *
    into v_request_type
    from public.request_types
    where code = 'use_offset'
      and is_active = true
    limit 1;
  end if;

  if v_request_type.id is null then
    select *
    into v_request_type
    from public.request_types
    where code = p_request_type_code
      and is_active = true
    limit 1;
  end if;

  if v_request_type.id is null then
    raise exception 'Request type is not configured: %', p_request_type_code;
  end if;

  -- Ensure employee has an offset_balances record
  insert into public.offset_balances (employee_id, balance_hours, updated_at)
  values (v_profile.employee_id, 0, now())
  on conflict (employee_id) do nothing;

  -- If Use Offset: Check balance sufficiency and AUTOMATICALLY DEDUCT upon submission
  if v_is_use_offset then
    select coalesce(balance_hours, 0)
    into v_balance
    from public.offset_balances
    where employee_id = v_profile.employee_id
    for update;

    if coalesce(v_balance, 0) < p_total_hours then
      raise exception 'Insufficient offset balance. Available %, requested %.', coalesce(v_balance, 0), p_total_hours;
    end if;

    v_new_balance := v_balance - p_total_hours;

    update public.offset_balances
    set balance_hours = v_new_balance,
        updated_at = now()
    where employee_id = v_profile.employee_id;
  elsif v_request_type.requires_offset_credit_check then
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
    v_initial_status
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
    v_effective_hours,
    p_reason,
    p_time_schedule,
    p_day_off,
    p_payroll_class,
    v_transaction_type
  );

  -- Record balance transaction if use_offset
  if v_is_use_offset then
    insert into public.offset_balance_transactions (
      employee_id,
      request_id,
      amount_hours,
      previous_balance,
      new_balance,
      transaction_type,
      notes,
      created_by
    )
    values (
      v_profile.employee_id,
      v_request_id,
      -p_total_hours,
      v_balance,
      v_new_balance,
      'use',
      'Offset balance deduction on request submission',
      v_profile.id
    );
  end if;

  -- Build approval routes using approval_level_routes and find_request_approver
  for v_route in
    select distinct on (step_order) *
    from public.approval_level_routes
    where requester_level = v_position.authority_level
      and (department_id = v_assignment.department_id or department_id is null)
    order by
      step_order asc,
      case when department_id = v_assignment.department_id then 0 else 1 end
    limit coalesce(v_request_type.approval_count, 1)
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

    if coalesce((to_jsonb(v_approver)->>'approver_employee_id'), '') <> '' then
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
        coalesce((to_jsonb(v_approver)->>'resolved_level')::integer, v_route.approver_level),
        (to_jsonb(v_approver)->>'approver_employee_id')::uuid,
        coalesce(
          (to_jsonb(v_approver)->>'approver_user_profile_id')::uuid,
          (to_jsonb(v_approver)->>'approver_user_id')::uuid,
          (select id from public.user_profiles where employee_id = (to_jsonb(v_approver)->>'approver_employee_id')::uuid limit 1)
        ),
        case when v_is_scheduled_ot then 'waiting' when v_step_order = 1 then 'pending' else 'waiting' end
      );

      v_used_employee_ids := array_append(v_used_employee_ids, (to_jsonb(v_approver)->>'approver_employee_id')::uuid);
    end if;
  end loop;

  if v_step_order = 0 then
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
      1,
      v_assignment.function_id,
      null,
      null,
      null,
      'admin_fallback'
    );

    insert into public.request_audit_logs (
      request_id,
      actor_user_id,
      action,
      details
    )
    values (
      v_request_id,
      v_profile.id,
      'routed_to_admin',
      'No matching approver found.'
    );

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
    case
      when v_is_scheduled_ot and (p_request_type_code = 'offset_earn' or lower(v_transaction_type) like '%offset%')
        then 'Scheduled Offset pre-approved'
      when v_is_scheduled_ot
        then 'Scheduled OT pre-approved'
      else 'Request submitted'
    end,
    case
      when v_is_scheduled_ot and (p_request_type_code = 'offset_earn' or lower(v_transaction_type) like '%offset%')
        then 'Your scheduled offset request is pre-approved.'
      when v_is_scheduled_ot
        then 'Your scheduled overtime request is pre-approved.'
      when v_is_use_offset
        then 'Your Use Offset request was submitted. ' || p_total_hours || ' hr(s) deducted from offset balance.'
      else 'Your ' || v_transaction_type || ' request was submitted.'
    end,
    'request',
    v_request_id
  );

  return v_request_id;
end;
$$;

grant execute on function public.submit_time_request(text, date, date, time, time, numeric, text, text, text, text, text) to authenticated;
grant execute on function public.submit_time_request(text, date, date, time, time, numeric, text, text, text, text, text) to anon;
grant execute on function public.submit_time_request(text, date, date, time, time, numeric, text, text, text, text, text) to service_role;


-- 2. Update public.decide_approval_step: update requests.status to 'pending' when intermediate approval occurs on pre_approved request
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

    -- Ensure request status transitions from 'pre_approved' to 'pending'
    update public.requests
    set status = 'pending',
        updated_at = now()
    where id = v_step.request_id
      and status in ('pre_approved', 'pre-approved');
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
grant execute on function public.decide_approval_step(uuid, text, text) to anon;
grant execute on function public.decide_approval_step(uuid, text, text) to service_role;

-- Backward compatibility alias for approve_request if invoked directly
create or replace function public.approve_request(
  p_step_id uuid,
  p_decision text,
  p_remarks text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.decide_approval_step(p_step_id, p_decision, p_remarks);
end;
$$;

grant execute on function public.approve_request(uuid, text, text) to authenticated;
grant execute on function public.approve_request(uuid, text, text) to anon;
grant execute on function public.approve_request(uuid, text, text) to service_role;


-- 3. Backfill all regular ESARF requests (FIO, OB, UT, CS, or combined) that were mistakenly marked 'pre_approved'
update public.requests r
set status = 'pending',
    updated_at = now()
from public.time_request_details trd
where trd.request_id = r.id
  and r.status in ('pre_approved', 'pre-approved')
  and (
    lower(coalesce(trd.transaction_type, '')) like '%fio%'
    or lower(coalesce(trd.transaction_type, '')) like '%punch%'
    or lower(coalesce(trd.transaction_type, '')) like '%business%'
    or lower(coalesce(trd.transaction_type, '')) like '%ob%'
    or lower(coalesce(trd.transaction_type, '')) like '%undertime%'
    or lower(coalesce(trd.transaction_type, '')) like '%ut%'
    or lower(coalesce(trd.transaction_type, '')) like '%change of schedule%'
    or lower(coalesce(trd.transaction_type, '')) like '%cs%'
    or (
      lower(coalesce(trd.transaction_type, '')) not like '%ot%'
      and lower(coalesce(trd.transaction_type, '')) not like '%overtime%'
      and lower(coalesce(trd.transaction_type, '')) not like '%offset%'
    )
  );

-- 4. Backfill any OT/Offset requests where the scheduled shift date or time has already arrived or passed
update public.requests r
set status = 'pending',
    updated_at = now()
from public.time_request_details trd
where trd.request_id = r.id
  and r.status in ('pre_approved', 'pre-approved')
  and (
    trd.date_from < (timezone('Asia/Manila', now()))::date
    or (
      trd.date_from = (timezone('Asia/Manila', now()))::date
      and trd.time_to is not null
      and (timezone('Asia/Manila', now()))::time >= trd.time_to
    )
    or (
      trd.date_from = (timezone('Asia/Manila', now()))::date
      and trd.time_to is null
      and trd.time_from is not null
      and (timezone('Asia/Manila', now()))::time >= trd.time_from
    )
  );

-- 5. Backfill any request where at least one approval step has already been approved
update public.requests r
set status = 'pending',
    updated_at = now()
where r.status in ('pre_approved', 'pre-approved')
  and exists (
    select 1 from public.request_approval_steps ras
    where ras.request_id = r.id
      and ras.status = 'approved'
  );

-- 6. Backfill any request that already has photo proof attached
update public.requests r
set status = 'pending',
    updated_at = now()
where r.status in ('pre_approved', 'pre-approved')
  and exists (
    select 1 from public.time_request_details trd
    where trd.request_id = r.id
      and (
        trd.reason like '%[Proof:%'
        or trd.reason like '%[ProofId:%'
      )
  );

-- 7. Activate next/first pending approval step for any backfilled request currently stuck in 'waiting'
update public.request_approval_steps ras
set status = 'pending'
from public.requests r
where ras.request_id = r.id
  and r.status = 'pending'
  and ras.status = 'waiting'
  and not exists (
    select 1 from public.request_approval_steps prev
    where prev.request_id = r.id
      and prev.status = 'pending'
  )
  and not exists (
    select 1 from public.request_approval_steps prev2
    where prev2.request_id = r.id
      and prev2.step_order < ras.step_order
      and prev2.status in ('waiting', 'pending_hr')
  );

notify pgrst, 'reload schema';

