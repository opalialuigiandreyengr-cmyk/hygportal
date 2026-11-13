-- ============================================================================
-- Migration 0228: Fix submit_leave_request Function Overload Ambiguity
--
-- Objective:
-- Resolve PostgreSQL ambiguity error (42725):
-- "Could not choose the best candidate function between:
--  public.submit_leave_request(p_leave_type => text, p_leave_category => text, p_start_date => date, p_end_date => date, p_paid_days => numeric, p_unpaid_days => numeric, p_reason => text),
--  public.submit_leave_request(p_leave_type => text, p_start_date => date, p_end_date => date, p_reason => text, p_leave_category => text, p_total_days => numeric, p_paid_days => numeric, p_unpaid_days => numeric, p_custom_approvers => jsonb)"
--
-- Fix:
-- 1. Drop all previous overloaded variants of public.submit_leave_request.
-- 2. Create a single, canonical, backwards-compatible public.submit_leave_request
--    that matches the exact parameter names sent by the mobile app and admin desktop.
-- 3. Include Assistant Store Manager (ASM) fallback and approver detail logging.
-- ============================================================================

-- 1. Drop old overloaded signatures
drop function if exists public.submit_leave_request(text, text, date, date, text);
drop function if exists public.submit_leave_request(text, text, date, date, numeric, numeric, text);
drop function if exists public.submit_leave_request(text, date, date, text, text, numeric, numeric, numeric, jsonb);
drop function if exists public.submit_leave_request(text, text, date, date, numeric, numeric, text, numeric, jsonb);

-- 2. Create canonical public.submit_leave_request
create or replace function public.submit_leave_request(
  p_leave_type text,
  p_leave_category text,
  p_start_date date,
  p_end_date date,
  p_paid_days numeric,
  p_unpaid_days numeric,
  p_reason text,
  p_total_days numeric default null,
  p_custom_approvers jsonb default null
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
  v_is_birthday_leave boolean;
  v_credits_to_check numeric;
  v_hire_date date;
  v_has_one_year_service boolean;
  v_day_off text;
  v_custom_app_elem jsonb;
  v_custom_matched boolean;
  v_step_approver_emp_id uuid;
  v_step_approver_user_id uuid;
  v_step_resolved_level int;
  v_step_approver_name text;
  v_step_approver_pos_name text;
  v_step_approver_emp_no text;
  v_step1_emp_id uuid;
  v_step1_user_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  if p_end_date < p_start_date then
    raise exception 'End date cannot be earlier than start date.';
  end if;

  v_leave_type := trim(coalesce(p_leave_type, ''));
  if v_leave_type not in ('With Pay', 'Without Pay', 'Both') then
    if lower(v_leave_type) = 'with pay' then v_leave_type := 'With Pay';
    elsif lower(v_leave_type) = 'without pay' then v_leave_type := 'Without Pay';
    elsif lower(v_leave_type) = 'both' then v_leave_type := 'Both';
    else
      raise exception 'Leave type must be With Pay, Without Pay, or Both.';
    end if;
  end if;

  if nullif(trim(p_leave_category), '') is null then
    raise exception 'Leave category is required.';
  end if;

  if nullif(trim(p_reason), '') is null then
    raise exception 'Reason is required.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  if v_profile.id is null or v_profile.employee_id is null then
    raise exception 'Your login is not linked to an employee profile.';
  end if;

  -- 1. Compute total days considering employee day-off if not explicitly passed
  if p_total_days is not null and p_total_days > 0 then
    v_total_days := p_total_days;
  else
    select coalesce(epd.day_off, '')
    into v_day_off
    from public.employee_profile_details epd
    where epd.employee_id = v_profile.employee_id
    limit 1;

    if nullif(trim(v_day_off), '') is not null and upper(trim(v_day_off)) not in ('NO DAY OFF', 'NO_DAY_OFF', 'NONE') then
      select count(*)
      into v_total_days
      from generate_series(p_start_date::timestamp, p_end_date::timestamp, '1 day'::interval) as s(d)
      where not (
        (upper(v_day_off) ~* '\y(SUN|SUNDAY)\y' and extract(dow from s.d) = 0)
        or (upper(v_day_off) ~* '\y(MON|MONDAY)\y' and extract(dow from s.d) = 1)
        or (upper(v_day_off) ~* '\y(TUE|TUES|TUESDAY)\y' and extract(dow from s.d) = 2)
        or (upper(v_day_off) ~* '\y(WED|WEDNESDAY)\y' and extract(dow from s.d) = 3)
        or (upper(v_day_off) ~* '\y(THU|THUR|THURS|THURSDAY)\y' and extract(dow from s.d) = 4)
        or (upper(v_day_off) ~* '\y(FRI|FRIDAY)\y' and extract(dow from s.d) = 5)
        or (upper(v_day_off) ~* '\y(SAT|SATURDAY)\y' and extract(dow from s.d) = 6)
      );
    else
      v_total_days := (p_end_date - p_start_date) + 1;
    end if;
  end if;

  -- 2. Compute paid and unpaid days
  if coalesce(p_paid_days, 0) + coalesce(p_unpaid_days, 0) = v_total_days then
    v_paid_days := coalesce(p_paid_days, 0);
    v_unpaid_days := coalesce(p_unpaid_days, 0);
  else
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
  end if;

  -- 3. Birthday leave checks
  v_is_birthday_leave := lower(trim(p_leave_category)) = 'birthday leave';

  if v_is_birthday_leave then
    select e.hire_date into v_hire_date
    from public.employees e
    where e.id = v_profile.employee_id;

    if v_hire_date is null then
      v_has_one_year_service := false;
    else
      v_has_one_year_service := (v_hire_date + interval '1 year') <= p_start_date;
    end if;

    if not v_has_one_year_service then
      raise exception 'Birthday Leave requires at least one (1) year of continuous service.';
    end if;

    if exists (
      select 1
      from public.leave_request_details lrd
      join public.requests r on r.id = lrd.request_id
      where r.submitted_by_employee_id = v_profile.employee_id
        and lower(trim(lrd.leave_category)) = 'birthday leave'
        and extract(year from lrd.start_date) = extract(year from p_start_date)
        and r.status not in ('rejected', 'cancelled', 'deleted')
    ) then
      raise exception 'You have already applied for or used Birthday Leave for this calendar year.';
    end if;
  end if;

  -- 4. Check available leave credits if paid leave requested
  if v_paid_days > 0 and not v_is_birthday_leave then
    v_available_days := public.get_available_leave_days(v_profile.employee_id, p_start_date);
    if v_available_days is null or v_available_days = 0 then
      select coalesce(lc.available_days, 0)
      into v_available_days
      from public.leave_credits lc
      where lc.employee_id = v_profile.employee_id
      limit 1;
    end if;

    v_credits_to_check := coalesce(v_available_days, 0);

    if v_credits_to_check < v_paid_days then
      raise exception 'Insufficient leave credits. Available: %, Requested Paid Days: %',
        v_credits_to_check, v_paid_days;
    end if;
  end if;

  -- 5. Resolve active employee assignment
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
    select *
    into v_assignment
    from public.employee_assignments
    where employee_id = v_profile.employee_id
    order by is_primary desc, effective_from desc
    limit 1;
  end if;

  if v_assignment.id is null then
    raise exception 'No active employee assignment found.';
  end if;

  -- Resolve cluster and area for employee assignment
  if v_assignment.store_id is not null then
    select coalesce(s.area_id, cl.area_id, v_assignment.area_id), coalesce(s.cluster_id, v_assignment.cluster_id)
    into v_assignment.area_id, v_assignment.cluster_id
    from public.stores s
    left join public.clusters cl on cl.id = s.cluster_id
    where s.id = v_assignment.store_id;
  elsif v_assignment.cluster_id is not null then
    select coalesce(cl.area_id, v_assignment.area_id)
    into v_assignment.area_id
    from public.clusters cl
    where cl.id = v_assignment.cluster_id;
  end if;

  if v_assignment.area_id is null then
    select aa.area_id
    into v_assignment.area_id
    from public.authority_assignments aa
    where aa.employee_id = v_assignment.employee_id
      and aa.area_id is not null
      and aa.is_active = true
      and aa.effective_from <= current_date
      and (aa.effective_to is null or aa.effective_to >= current_date)
    order by aa.created_at desc
    limit 1;
  end if;

  if v_assignment.cluster_id is null then
    select aa.cluster_id
    into v_assignment.cluster_id
    from public.authority_assignments aa
    where aa.employee_id = v_assignment.employee_id
      and aa.cluster_id is not null
      and aa.is_active = true
      and aa.effective_from <= current_date
      and (aa.effective_to is null or aa.effective_to >= current_date)
    order by aa.created_at desc
    limit 1;
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
  where code in ('leave', 'leave_request')
    and is_active = true
  order by case when code = 'leave' then 0 else 1 end
  limit 1;

  if v_request_type.id is null then
    raise exception 'Leave request type is not configured.';
  end if;

  -- 6. Birthday leave auto-approval
  if v_is_birthday_leave and v_total_days = 1 and v_has_one_year_service then
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
      status,
      final_approved_at
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
      'approved',
      now()
    )
    returning id into v_request_id;

    insert into public.leave_request_details (
      request_id,
      leave_type,
      leave_category,
      start_date,
      end_date,
      paid_days,
      unpaid_days,
      reason,
      total_days
    )
    values (
      v_request_id,
      v_leave_type,
      trim(p_leave_category),
      p_start_date,
      p_end_date,
      v_paid_days,
      v_unpaid_days,
      trim(p_reason),
      v_total_days
    );

    insert into public.request_approval_steps (
      request_id,
      step_order,
      required_function_id,
      required_level,
      assigned_approver_employee_id,
      assigned_approver_user_id,
      status,
      approved_at,
      approval_comment
    )
    values (
      v_request_id,
      1,
      v_assignment.function_id,
      1,
      null,
      null,
      'approved',
      now(),
      'Auto-approved by HYG Portal System for Birthday Leave'
    );

    return v_request_id;
  end if;

  -- 7. Regular leave request
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
    paid_days,
    unpaid_days,
    reason,
    total_days
  )
  values (
    v_request_id,
    v_leave_type,
    trim(p_leave_category),
    p_start_date,
    p_end_date,
    v_paid_days,
    v_unpaid_days,
    trim(p_reason),
    v_total_days
  );

  -- 8. Build approval routes (with custom approvers and ASM fallback support)
  for v_route in
    select distinct on (step_order) *
    from public.approval_level_routes
    where requester_level = v_position.authority_level
      and (department_id = v_assignment.department_id or department_id is null)
    order by
      step_order asc,
      case when department_id = v_assignment.department_id then 0 else 1 end
    limit coalesce(v_request_type.approval_count, 2)
  loop
    v_step_order := v_step_order + 1;
    v_custom_matched := false;
    v_step_approver_emp_id := null;
    v_step_approver_user_id := null;
    v_step_resolved_level := null;
    v_step_approver_name := null;
    v_step_approver_pos_name := null;
    v_step_approver_emp_no := null;

    -- Check custom approvers array if provided
    if p_custom_approvers is not null and jsonb_typeof(p_custom_approvers) = 'array' then
      for v_custom_app_elem in select * from jsonb_array_elements(p_custom_approvers) loop
        if (v_custom_app_elem->>'step_order')::int = v_step_order
           and nullif(trim(v_custom_app_elem->>'approver_employee_id'), '') is not null then
          v_step_approver_emp_id := (v_custom_app_elem->>'approver_employee_id')::uuid;
          select up.id into v_step_approver_user_id
          from public.user_profiles up
          where up.employee_id = v_step_approver_emp_id
          limit 1;
          v_step_resolved_level := coalesce((v_custom_app_elem->>'approver_level')::int, v_route.approver_level);
          v_custom_matched := true;
          exit;
        end if;
      end loop;
    end if;

    if v_custom_matched and v_step_approver_emp_id is not null then
      select
        nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), ''),
        e.employee_no,
        p.name
      into
        v_step_approver_name,
        v_step_approver_emp_no,
        v_step_approver_pos_name
      from public.employees e
      left join public.employee_assignments ea on ea.employee_id = e.id and ea.is_primary = true
      left join public.positions p on p.id = ea.position_id
      where e.id = v_step_approver_emp_id
      limit 1;

      insert into public.request_approval_steps (
        request_id,
        step_order,
        required_function_id,
        required_level,
        assigned_approver_employee_id,
        assigned_approver_user_id,
        status,
        approver_name,
        approver_position_name,
        approver_employee_no,
        is_reassigned
      )
      values (
        v_request_id,
        v_step_order,
        v_assignment.function_id,
        coalesce(v_step_resolved_level, v_route.approver_level),
        v_step_approver_emp_id,
        v_step_approver_user_id,
        case when v_step_order = 1 then 'pending' else 'waiting' end,
        v_step_approver_name,
        v_step_approver_pos_name,
        v_step_approver_emp_no,
        true
      );
      v_used_employee_ids := array_append(v_used_employee_ids, v_step_approver_emp_id);
    else
      -- Standard approver resolution using find_request_approver (with ASM fallback)
      select
        (to_jsonb(fa)->>'approver_employee_id')::uuid,
        coalesce(
          (to_jsonb(fa)->>'approver_user_profile_id')::uuid,
          (to_jsonb(fa)->>'approver_user_id')::uuid,
          (select id from public.user_profiles where employee_id = (to_jsonb(fa)->>'approver_employee_id')::uuid limit 1)
        ),
        coalesce((to_jsonb(fa)->>'resolved_level')::integer, v_route.approver_level),
        to_jsonb(fa)->>'approver_full_name',
        to_jsonb(fa)->>'approver_position_name',
        to_jsonb(fa)->>'approver_employee_no'
      into
        v_step_approver_emp_id,
        v_step_approver_user_id,
        v_step_resolved_level,
        v_step_approver_name,
        v_step_approver_pos_name,
        v_step_approver_emp_no
      from public.find_request_approver(
        v_assignment.id,
        v_assignment.function_id,
        v_route.approver_level,
        v_profile.employee_id,
        v_used_employee_ids
      ) fa
      limit 1;

      if v_step_approver_emp_id is not null then
        insert into public.request_approval_steps (
          request_id,
          step_order,
          required_function_id,
          required_level,
          assigned_approver_employee_id,
          assigned_approver_user_id,
          status,
          approver_name,
          approver_position_name,
          approver_employee_no
        )
        values (
          v_request_id,
          v_step_order,
          v_assignment.function_id,
          coalesce(v_step_resolved_level, v_route.approver_level),
          v_step_approver_emp_id,
          v_step_approver_user_id,
          case when v_step_order = 1 then 'pending' else 'waiting' end,
          v_step_approver_name,
          v_step_approver_pos_name,
          v_step_approver_emp_no
        );

        v_used_employee_ids := array_append(v_used_employee_ids, v_step_approver_emp_id);
      end if;
    end if;
  end loop;

  if v_step_order = 0 then
    insert into public.request_approval_steps (
      request_id,
      step_order,
      required_function_id,
      required_level,
      assigned_approver_employee_id,
      status
    )
    values (
      v_request_id,
      1,
      v_assignment.function_id,
      greatest(2, coalesce(v_position.authority_level, 1) + 1),
      null,
      'admin_fallback'
    );
  end if;

  -- Send notification to Step 1 Approver if user account exists
  select assigned_approver_employee_id, assigned_approver_user_id
  into v_step1_emp_id, v_step1_user_id
  from public.request_approval_steps
  where request_id = v_request_id and step_order = 1;

  if v_step1_emp_id is not null then
    insert into public.notifications (
      employee_id,
      user_profile_id,
      title,
      message,
      link_type,
      link_id
    )
    values (
      v_step1_emp_id,
      v_step1_user_id,
      'Leave Request Pending Approval',
      coalesce(
        (select trim(concat_ws(' ', first_name, last_name)) from public.employees where id = v_profile.employee_id),
        'An employee'
      ) || ' submitted a leave request.',
      'approval',
      v_request_id
    );
  end if;

  return v_request_id;
end;
$$;

-- 3. Also ensure submit_time_request has no overload ambiguity between 14-arg and 16-arg variants
drop function if exists public.submit_time_request(
  text, date, date, time, time, numeric, text, text, text, text, text, uuid, jsonb, boolean
);

-- 4. Grant execute permissions to roles
grant execute on function public.submit_leave_request(
  text, text, date, date, numeric, numeric, text, numeric, jsonb
) to authenticated, anon, service_role;

-- 5. Force schema cache reload in PostgREST
notify pgrst, 'reload schema';
