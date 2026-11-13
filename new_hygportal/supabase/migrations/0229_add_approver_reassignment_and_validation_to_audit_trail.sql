-- Migration 0229: Add Approver Reassignment, Leave/ESARF Request Validation & Authority Changes to Audit Trail
-- Ensures that:
-- 1. Manual approver reassignment (admin_reassign_request_approver) logs to public.audit_logs
-- 2. Leave request validation (admin_validate_leave_request) logs to public.audit_logs
-- 3. ESARF request validation & re-validation (admin_validate_esarf_request) consistently logs to public.audit_logs
-- 4. HR authority assignments (hr_admin_set_authority_assignment) and position authority updates log rich metadata
-- 5. admin_get_audit_logs resolves employee/position/department targets and formats user-friendly action labels
-- NOTE: Does NOT modify any request submission functions (submit_leave_request, etc.), keeping request submission 100% stable.

-- ============================================================================
-- Section 1: Update public.admin_reassign_request_approver with Audit Trail
-- ============================================================================
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
  v_old_approver_employee_id uuid;
  v_actor_profile_id uuid;
  v_requester_emp_id uuid;
  v_requester_name text;
  v_requester_no text;
  v_old_approver_name text;
  v_new_approver_name text;
begin
  -- Resolve actor user profile id if authenticated
  if auth.uid() is not null then
    select id into v_actor_profile_id
    from public.user_profiles
    where auth_user_id = auth.uid()
    limit 1;
  end if;

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

  -- Get step_order and old assigned approver of target step
  select step_order, assigned_approver_employee_id
  into v_target_step_order, v_old_approver_employee_id
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

  -- Lookup requester employee info
  select r.submitted_by_employee_id,
         concat_ws(' ', e.first_name, e.last_name),
         e.employee_no
  into v_requester_emp_id, v_requester_name, v_requester_no
  from public.requests r
  left join public.employees e on e.id = r.submitted_by_employee_id
  where r.id = p_request_id;

  if v_requester_emp_id is null then
    select pr.employee_id,
           concat_ws(' ', e.first_name, e.last_name),
           e.employee_no
    into v_requester_emp_id, v_requester_name, v_requester_no
    from public.employee_perk_requests pr
    left join public.employees e on e.id = pr.employee_id
    where pr.id = p_request_id;
  end if;

  -- Lookup old and new approver names
  if v_old_approver_employee_id is not null then
    select concat_ws(' ', first_name, last_name)
    into v_old_approver_name
    from public.employees
    where id = v_old_approver_employee_id;
  end if;

  if p_new_approver_employee_id is not null then
    select concat_ws(' ', first_name, last_name)
    into v_new_approver_name
    from public.employees
    where id = p_new_approver_employee_id;
  end if;

  -- Record in audit_logs
  insert into public.audit_logs (
    actor_user_profile_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    v_actor_profile_id,
    'admin_reassign_request_approver',
    'request',
    p_request_id,
    jsonb_build_object(
      'employee_id', v_requester_emp_id,
      'target_employee_id', v_requester_emp_id,
      'target_name', coalesce(nullif(trim(v_requester_name), ''), 'Employee'),
      'target_employee_no', coalesce(v_requester_no, ''),
      'step_id', v_target_step_id,
      'step_order', v_target_step_order,
      'old_approver_id', v_old_approver_employee_id,
      'old_approver_name', coalesce(nullif(trim(v_old_approver_name), ''), 'Unassigned'),
      'new_approver_id', p_new_approver_employee_id,
      'new_approver_name', coalesce(nullif(trim(v_new_approver_name), ''), 'Unknown Approver'),
      'description', concat(
        'Reassigned step ', coalesce(v_target_step_order::text, '1'), ' approver from ',
        coalesce(nullif(trim(v_old_approver_name), ''), 'Unassigned'), ' to ',
        coalesce(nullif(trim(v_new_approver_name), ''), 'New Approver')
      )
    )
  );

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

grant execute on function public.admin_reassign_request_approver(uuid, uuid, uuid) to authenticated, anon, service_role;
grant execute on function public.admin_reassign_request_approver(uuid, uuid) to authenticated, anon, service_role;

-- ============================================================================
-- Section 2: Update public.admin_validate_leave_request with Audit Trail
-- ============================================================================
drop function if exists public.admin_validate_leave_request(uuid, numeric, numeric);

create or replace function public.admin_validate_leave_request(
  p_request_id uuid,
  p_paid_days numeric,
  p_unpaid_days numeric
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emp_id uuid;
  v_old_paid numeric := 0;
  v_old_unpaid numeric := 0;
  v_diff numeric := 0;
  v_new_type text;
  v_actor_profile_id uuid;
  v_emp_name text;
  v_emp_no text;
begin
  -- Resolve actor profile if authenticated
  if auth.uid() is not null then
    select id into v_actor_profile_id
    from public.user_profiles
    where auth_user_id = auth.uid()
    limit 1;
  end if;

  select r.submitted_by_employee_id,
         coalesce(lrd.paid_days, 0),
         coalesce(lrd.unpaid_days, 0),
         concat_ws(' ', e.first_name, e.last_name),
         e.employee_no
  into v_emp_id, v_old_paid, v_old_unpaid, v_emp_name, v_emp_no
  from public.requests r
  join public.leave_request_details lrd on lrd.request_id = r.id
  left join public.employees e on e.id = r.submitted_by_employee_id
  where r.id = p_request_id;

  if v_emp_id is null then
    raise exception 'Leave request not found.';
  end if;

  if p_paid_days > 0 and p_unpaid_days > 0 then
    v_new_type := 'With and Without Pay';
  elsif p_paid_days > 0 then
    v_new_type := 'With Pay';
  else
    v_new_type := 'Without Pay';
  end if;

  update public.leave_request_details
  set paid_days = p_paid_days,
      unpaid_days = p_unpaid_days,
      leave_type = v_new_type,
      total_days = (p_paid_days + p_unpaid_days)
  where request_id = p_request_id;

  update public.requests
  set status = 'validated',
      updated_at = now()
  where id = p_request_id;

  v_diff := p_paid_days - v_old_paid;
  if v_diff <> 0 then
    insert into public.leave_balances (employee_id, annual_credit_days, used_days)
    values (v_emp_id, public.calculate_initial_leave_credits(v_emp_id), 0)
    on conflict (employee_id) do nothing;

    update public.leave_balances
    set used_days = greatest(0, used_days + v_diff),
        updated_at = now()
    where employee_id = v_emp_id;
  end if;

  -- Record in audit_logs
  insert into public.audit_logs (
    actor_user_profile_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    v_actor_profile_id,
    'admin_validate_leave_request',
    'request',
    p_request_id,
    jsonb_build_object(
      'employee_id', v_emp_id,
      'target_employee_id', v_emp_id,
      'target_name', coalesce(nullif(trim(v_emp_name), ''), 'Employee'),
      'target_employee_no', coalesce(v_emp_no, ''),
      'old_paid_days', v_old_paid,
      'old_unpaid_days', v_old_unpaid,
      'new_paid_days', p_paid_days,
      'new_unpaid_days', p_unpaid_days,
      'new_leave_type', v_new_type,
      'diff_paid_days', v_diff,
      'description', concat(
        'Validated leave request: ', p_paid_days, ' paid day(s), ', p_unpaid_days, ' unpaid day(s)',
        case when v_diff <> 0 then concat(' (adjusted by ', v_diff, ' paid day(s))') else '' end
      )
    )
  );

  return 'Leave request validated successfully.';
end;
$$;

grant execute on function public.admin_validate_leave_request(uuid, numeric, numeric) to authenticated, anon, service_role;

-- ============================================================================
-- Section 3: Update public.admin_validate_esarf_request with Consistent Audit Trail
-- ============================================================================
drop function if exists public.admin_validate_esarf_request(uuid, numeric, text);

create or replace function public.admin_validate_esarf_request(
  p_request_id uuid,
  p_total_hours numeric default null,
  p_reason text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.requests;
  v_request_type public.request_types;
  v_time public.time_request_details;
  v_emp_id uuid;
  v_emp_name text;
  v_emp_no text;
  v_actor_profile_id uuid;
  v_current_bal numeric;
  v_new_bal numeric;
  v_old_hours numeric := 0;
  v_new_hours numeric;
  v_diff numeric := 0;
  v_action text := 'none';
  v_txn_type text := '';
  v_reason_text text := '';
  v_is_revalidation boolean := false;
begin
  -- 1. Check caller permissions if authenticated
  if auth.uid() is not null then
    select id into v_actor_profile_id
    from public.user_profiles
    where auth_user_id = auth.uid()
      and app_role in ('admin', 'super_admin')
      and is_active = true
    limit 1;

    if v_actor_profile_id is null and current_user not in ('postgres', 'service_role', 'supabase_admin') then
      raise exception 'Admin access is required.';
    end if;
  end if;

  -- 2. Fetch the request
  select * into v_request
  from public.requests
  where id = p_request_id;

  if v_request.id is null then
    raise exception 'Request not found.';
  end if;

  if v_request.status in ('rejected', 'cancelled') then
    raise exception 'Cannot validate a % request.', v_request.status;
  end if;

  v_is_revalidation := (v_request.status = 'validated');

  v_emp_id := v_request.submitted_by_employee_id;
  if v_emp_id is null then
    raise exception 'Target employee not found for this request.';
  end if;

  select concat_ws(' ', first_name, last_name), employee_no
  into v_emp_name, v_emp_no
  from public.employees
  where id = v_emp_id;

  -- 3. Fetch request type and time details
  select * into v_request_type
  from public.request_types
  where id = v_request.request_type_id;

  select * into v_time
  from public.time_request_details
  where request_id = p_request_id;

  if v_time.id is null then
    update public.requests
    set status = 'validated',
        updated_at = now()
    where id = p_request_id;

    insert into public.audit_logs (
      actor_user_profile_id,
      action,
      entity_type,
      entity_id,
      metadata
    )
    values (
      v_actor_profile_id,
      case when v_is_revalidation then 'admin_revalidate_esarf_request' else 'admin_validate_esarf_request' end,
      'request',
      p_request_id,
      jsonb_build_object(
        'employee_id', v_emp_id,
        'target_employee_id', v_emp_id,
        'target_name', coalesce(nullif(trim(v_emp_name), ''), 'Employee'),
        'target_employee_no', coalesce(v_emp_no, ''),
        'is_revalidation', v_is_revalidation,
        'description', case when v_is_revalidation then 'Re-validated ESARF request' else 'Validated ESARF request' end
      )
    );

    if v_is_revalidation then
      return 'ESARF request re-validated successfully.';
    else
      return 'ESARF request validated successfully.';
    end if;
  end if;

  v_old_hours := coalesce(v_time.total_hours, 0);
  v_new_hours := coalesce(p_total_hours, v_old_hours);

  if v_new_hours <= 0 then
    raise exception 'Total hours must be greater than zero.';
  end if;

  v_txn_type := lower(trim(coalesce(v_time.transaction_type, '')));
  v_reason_text := lower(trim(coalesce(v_time.reason, '')));

  if coalesce(v_request_type.code, '') = 'use_offset'
     or coalesce(v_request_type.affects_offset_balance, '') = 'use'
     or v_txn_type like '%use_offset%'
     or v_txn_type like '%use offset%'
     or v_reason_text like '%(use offset)%' then
    v_action := 'use';
  elsif coalesce(v_request_type.code, '') = 'offset_earn'
     or coalesce(v_request_type.affects_offset_balance, '') = 'earn'
     or v_txn_type like '%offset%'
     or v_reason_text like '%(offset)%' then
    v_action := 'earn';
  end if;

  -- 4. Update time_request_details
  update public.time_request_details
  set total_hours = v_new_hours,
      reason = coalesce(nullif(trim(p_reason), ''), reason)
  where request_id = p_request_id;

  -- 5. Update requests status to validated
  update public.requests
  set status = 'validated',
      updated_at = now()
  where id = p_request_id;

  -- 6. Process balance adjustment if it is an offset request
  if v_action <> 'none' then
    insert into public.offset_balances (employee_id, balance_hours, updated_at)
    values (v_emp_id, 0, now())
    on conflict (employee_id) do nothing;

    select coalesce(balance_hours, 0)
    into v_current_bal
    from public.offset_balances
    where employee_id = v_emp_id
    for update;

    if v_action = 'earn' then
      v_diff := round(v_new_hours - v_old_hours, 2);

      if not exists (
        select 1 from public.offset_transactions
        where request_id = p_request_id and transaction_type in ('earn', 'credit')
      ) and (v_old_hours > 0 or v_new_hours > 0) then
        insert into public.offset_transactions (
          employee_id,
          request_id,
          transaction_type,
          hours,
          balance_after,
          created_at
        )
        values (
          v_emp_id,
          p_request_id,
          'earn',
          greatest(v_old_hours, v_new_hours),
          v_current_bal,
          coalesce(v_request.final_approved_at, v_request.submitted_at, now() - interval '1 second')
        );
      end if;

      if v_diff < 0 then
        v_new_bal := greatest(0, round(v_current_bal + v_diff, 2));

        update public.offset_balances
        set balance_hours = v_new_bal,
            updated_at = now()
        where employee_id = v_emp_id;

        insert into public.offset_transactions (
          employee_id,
          request_id,
          transaction_type,
          hours,
          balance_after,
          created_at
        )
        values (
          v_emp_id,
          p_request_id,
          'deduct',
          v_diff,
          v_new_bal,
          now()
        );
      elsif v_diff > 0 then
        v_new_bal := round(v_current_bal + v_diff, 2);

        update public.offset_balances
        set balance_hours = v_new_bal,
            updated_at = now()
        where employee_id = v_emp_id;

        insert into public.offset_transactions (
          employee_id,
          request_id,
          transaction_type,
          hours,
          balance_after,
          created_at
        )
        values (
          v_emp_id,
          p_request_id,
          'adjustment',
          v_diff,
          v_new_bal,
          now()
        );
      end if;

    elsif v_action = 'use' then
      v_diff := round(v_old_hours - v_new_hours, 2);

      if v_diff > 0 then
        v_new_bal := round(v_current_bal + v_diff, 2);

        update public.offset_balances
        set balance_hours = v_new_bal,
            updated_at = now()
        where employee_id = v_emp_id;

        insert into public.offset_transactions (
          employee_id,
          request_id,
          transaction_type,
          hours,
          balance_after,
          created_at
        )
        values (
          v_emp_id,
          p_request_id,
          'adjustment',
          v_diff,
          v_new_bal,
          now()
        );
      elsif v_diff < 0 then
        v_new_bal := greatest(0, round(v_current_bal - abs(v_diff), 2));

        update public.offset_balances
        set balance_hours = v_new_bal,
            updated_at = now()
        where employee_id = v_emp_id;

        insert into public.offset_transactions (
          employee_id,
          request_id,
          transaction_type,
          hours,
          balance_after,
          created_at
        )
        values (
          v_emp_id,
          p_request_id,
          'deduct',
          -abs(v_diff),
          v_new_bal,
          now()
        );
      end if;
    end if;
  end if;

  -- 7. Record in audit_logs (always recorded on both initial validation and re-validation)
  insert into public.audit_logs (
    actor_user_profile_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    v_actor_profile_id,
    case when v_is_revalidation then 'admin_revalidate_esarf_request' else 'admin_validate_esarf_request' end,
    'request',
    p_request_id,
    jsonb_build_object(
      'employee_id', v_emp_id,
      'target_employee_id', v_emp_id,
      'target_name', coalesce(nullif(trim(v_emp_name), ''), 'Employee'),
      'target_employee_no', coalesce(v_emp_no, ''),
      'old_total_hours', v_old_hours,
      'new_total_hours', v_new_hours,
      'diff_hours', v_diff,
      'action', v_action,
      'is_revalidation', v_is_revalidation,
      'reason', coalesce(nullif(trim(p_reason), ''), v_time.reason, ''),
      'description', concat(
        case when v_is_revalidation then 'Re-validated' else 'Validated' end,
        ' ESARF request: ', v_new_hours, ' total hrs',
        case when v_old_hours <> v_new_hours then concat(' (adjusted from ', v_old_hours, ' hrs)') else '' end
      )
    )
  );

  if v_is_revalidation then
    return 'ESARF request re-validated successfully.';
  else
    return 'ESARF request validated successfully.';
  end if;
end;
$$;

grant execute on function public.admin_validate_esarf_request(uuid, numeric, text) to authenticated, anon, service_role;

-- ============================================================================
-- Section 4: Update hr_admin_set_authority_assignment with Rich Audit Metadata
-- ============================================================================
drop function if exists public.hr_admin_set_authority_assignment(text, text, uuid, uuid, int, uuid, uuid, uuid);

create or replace function public.hr_admin_set_authority_assignment(
  p_username text default null,
  p_password text default null,
  p_employee_id uuid default null,
  p_function_id uuid default null,
  p_authority_level int default null,
  p_store_id uuid default null,
  p_cluster_id uuid default null,
  p_area_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.employee_assignments;
  v_authority_id uuid;
  v_company_id uuid;
  v_area_id uuid;
  v_cluster_id uuid;
  v_store_id uuid;
  v_actor_profile_id uuid;
  v_target_emp_name text;
  v_target_emp_no text;
begin
  if not public.hr_admin_has_access(p_username, p_password) then
    raise exception 'Admin access is required.';
  end if;

  if p_employee_id is null or p_function_id is null or p_authority_level not between 1 and 8 then
    raise exception 'Employee, function, and level 1-8 are required.';
  end if;

  -- Resolve actor user profile id
  if auth.uid() is not null then
    select id into v_actor_profile_id
    from public.user_profiles
    where auth_user_id = auth.uid()
    limit 1;
  end if;

  if v_actor_profile_id is null and p_username is not null then
    select id into v_actor_profile_id
    from public.user_profiles
    where username = p_username
    limit 1;
  end if;

  select *
  into v_assignment
  from public.employee_assignments
  where employee_id = p_employee_id
    and is_primary = true
    and effective_to is null
  order by created_at desc
  limit 1;

  if v_assignment.id is null then
    raise exception 'No active employee assignment found.';
  end if;

  v_company_id := v_assignment.company_id;
  v_area_id := v_assignment.area_id;
  v_cluster_id := v_assignment.cluster_id;
  v_store_id := v_assignment.store_id;

  if p_store_id is not null then
    select s.company_id, coalesce(s.area_id, cl.area_id), s.cluster_id, s.id
    into v_company_id, v_area_id, v_cluster_id, v_store_id
    from public.stores s
    left join public.clusters cl on cl.id = s.cluster_id
    where s.id = p_store_id
      and s.is_active = true;

    if v_store_id is null then
      raise exception 'Selected store was not found.';
    end if;
  elsif p_cluster_id is not null then
    select cl.company_id, cl.area_id, cl.id
    into v_company_id, v_area_id, v_cluster_id
    from public.clusters cl
    where cl.id = p_cluster_id
      and cl.is_active = true;

    if v_cluster_id is null then
      raise exception 'Selected cluster was not found.';
    end if;

    v_store_id := null;
  elsif p_area_id is not null then
    select a.company_id, a.id
    into v_company_id, v_area_id
    from public.areas a
    where a.id = p_area_id
      and a.is_active = true;

    if v_area_id is null then
      raise exception 'Selected area was not found.';
    end if;

    v_cluster_id := null;
    v_store_id := null;
  end if;

  update public.authority_assignments
  set is_active = false,
      effective_to = current_date
  where employee_id = p_employee_id
    and function_id = p_function_id
    and is_active = true
    and effective_to is null;

  insert into public.authority_assignments (
    employee_id,
    function_id,
    authority_level,
    company_id,
    area_id,
    cluster_id,
    store_id,
    department_id,
    effective_from,
    is_active
  )
  values (
    p_employee_id,
    p_function_id,
    p_authority_level,
    v_company_id,
    v_area_id,
    v_cluster_id,
    v_store_id,
    v_assignment.department_id,
    current_date,
    true
  )
  returning id into v_authority_id;

  -- Lookup target employee info
  select concat_ws(' ', first_name, last_name), employee_no
  into v_target_emp_name, v_target_emp_no
  from public.employees
  where id = p_employee_id;

  insert into public.audit_logs (
    actor_user_profile_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    v_actor_profile_id,
    'hr_admin_set_authority_assignment',
    'authority_assignment',
    v_authority_id,
    jsonb_build_object(
      'employee_id', p_employee_id,
      'target_employee_id', p_employee_id,
      'target_name', coalesce(nullif(trim(v_target_emp_name), ''), 'Employee'),
      'target_employee_no', coalesce(v_target_emp_no, ''),
      'function_id', p_function_id,
      'authority_level', p_authority_level,
      'store_id', v_store_id,
      'cluster_id', v_cluster_id,
      'area_id', v_area_id,
      'description', concat('Assigned Authority Level ', p_authority_level)
    )
  );

  return v_authority_id;
end;
$$;

grant execute on function public.hr_admin_set_authority_assignment(text, text, uuid, uuid, int, uuid, uuid, uuid) to anon, authenticated, service_role;

-- ============================================================================
-- Section 5: Update public.admin_get_audit_logs to format and display all events
-- ============================================================================
drop function if exists public.admin_get_audit_logs(text, text, text, timestamptz, timestamptz, int, int);

create or replace function public.admin_get_audit_logs(
  p_search text default null,
  p_action text default null,
  p_entity_type text default null,
  p_start_date timestamptz default null,
  p_end_date timestamptz default null,
  p_limit int default 50,
  p_offset int default 0
)
returns table (
  id uuid,
  created_at timestamptz,
  action text,
  action_label text,
  entity_type text,
  entity_id uuid,
  actor_user_profile_id uuid,
  actor_username text,
  actor_full_name text,
  actor_role text,
  target_name text,
  target_identifier text,
  description text,
  metadata jsonb,
  total_count bigint
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_admin record;
  v_search text;
begin
  select *
  into v_admin
  from public.admin_desktop_login_check()
  limit 1;

  if v_admin.app_role not in ('super_admin', 'admin') then
    raise exception 'Admin or Super Admin access is required to view the Audit Trail.';
  end if;

  v_search := nullif(trim(lower(p_search)), '');

  return query
  with filtered as (
    select
      al.id,
      al.created_at,
      al.action,
      case
        when al.action = 'password_reset' then 'Password Reset'
        when al.action in ('update_employee_profile', 'update_employee_information') then 'Employee Info Updated'
        when al.action = 'update_employee_assignment' then 'Job Assignment Updated'
        when al.action = 'update_employee_details' then 'Employee Details Updated'
        when al.action in ('update_user_information', 'user_role_change') then 'User Role / Info Changed'
        when al.action = 'user_banned' then 'User Banned'
        when al.action = 'user_unbanned' then 'User Unbanned'
        when al.action in ('create_user', 'admin_create_user') then 'User Created'
        when al.action = 'admin_delete_user' then 'User Deleted'
        when al.action = 'hr_delete_employee' then 'Employee Deleted'
        when al.action = 'admin_set_employee_leave_credits' then 'Leave Credits Set'
        when al.action = 'admin_deduct_employee_leave_credits' then 'Leave Credits Deducted'
        when al.action = 'admin_reimburse_employee_leave_credits' then 'Leave Credits Reimbursed'
        when al.action = 'admin_set_employee_offset_balance' then 'Offset Balance Set'
        when al.action = 'admin_add_employee_offset_balance' then 'Offset Balance Added'
        when al.action = 'admin_deduct_employee_offset_balance' then 'Offset Balance Deducted'
        when al.action in ('admin_set_authority_assignment', 'hr_admin_set_authority_assignment') then 'Authority Assignment'
        when al.action in ('admin_set_position_authority_level', 'hr_admin_set_position_authority_level') then 'Position Authority Level'
        when al.action in ('admin_clear_position_authority_level', 'hr_admin_clear_position_authority_level') then 'Position Authority Cleared'
        when al.action in ('department_approval_ladders', 'hr_admin_set_department_approval_ladder') then 'Approval Ladder Changed'
        when al.action = 'admin_approval_routes' then 'Approval Route Changed'
        when al.action = 'department_position_catalog' then 'Position Catalog Changed'
        when al.action in ('admin_reassign_request_approver', 'reassign_request_approver') then 'Approver Reassigned'
        when al.action in ('admin_validate_leave_request', 'validate_leave_request') then 'Leave Request Validated'
        when al.action in ('admin_validate_esarf_request', 'validate_esarf_request') then 'ESARF Request Validated'
        when al.action in ('admin_revalidate_esarf_request', 'revalidate_esarf_request') then 'ESARF Request Re-validated'
        when al.action in ('admin_update_request_status', 'update_request_status') then 'Request Status Updated'
        else initcap(replace(al.action, '_', ' '))
      end as action_label,
      al.entity_type,
      al.entity_id,
      al.actor_user_profile_id,
      coalesce(al.metadata->>'actor_username', actor_up.username, 'System') as actor_username,
      coalesce(
        nullif(trim(concat_ws(' ', actor_e.first_name, actor_e.last_name)), ''),
        al.metadata->>'actor_full_name',
        actor_up.username,
        'System'
      ) as actor_full_name,
      coalesce(al.metadata->>'actor_role', actor_up.app_role, 'system') as actor_role,
      coalesce(
        al.metadata->>'target_name',
        al.metadata->>'target_full_name',
        al.metadata->>'full_name',
        nullif(trim(concat_ws(' ', target_e.first_name, target_e.last_name)), ''),
        target_pos.name,
        target_dept.name,
        target_up.username,
        al.metadata->>'target_username',
        'N/A'
      ) as target_name,
      coalesce(
        al.metadata->>'target_employee_no',
        al.metadata->>'employee_no',
        target_e.employee_no,
        al.metadata->>'target_identifier',
        al.metadata->>'target_username',
        target_up.username,
        al.metadata->>'username',
        ''
      ) as target_identifier,
      coalesce(
        al.metadata->>'description',
        case
          when al.action = 'admin_set_employee_leave_credits' then
            concat('Set annual leave credits to ', al.metadata->>'annual_credit_days', ' days')
          when al.action = 'admin_deduct_employee_leave_credits' then
            concat('Deducted ', al.metadata->>'deduct_days', ' leave days')
          when al.action = 'admin_reimburse_employee_leave_credits' then
            concat('Reimbursed ', al.metadata->>'reimburse_days', ' leave days')
          when al.action = 'admin_set_employee_offset_balance' then
            concat('Set offset balance to ', al.metadata->>'new_balance_hours', ' hrs')
          when al.action = 'admin_add_employee_offset_balance' then
            concat('Added ', al.metadata->>'add_hours', ' hrs to offset balance')
          when al.action = 'admin_deduct_employee_offset_balance' then
            concat('Deducted ', al.metadata->>'deduct_hours', ' hrs from offset balance')
          when al.action in ('admin_set_authority_assignment', 'hr_admin_set_authority_assignment') then
            concat('Assigned Authority Level ', al.metadata->>'authority_level')
          when al.action in ('admin_set_position_authority_level', 'hr_admin_set_position_authority_level') then
            concat('Set position authority level to ', al.metadata->>'authority_level')
          when al.action in ('admin_clear_position_authority_level', 'hr_admin_clear_position_authority_level') then
            'Cleared position authority level'
          when al.action in ('department_approval_ladders', 'hr_admin_set_department_approval_ladder') then
            concat('Updated approval ladder levels: ', al.metadata->>'levels')
          when al.action in ('admin_reassign_request_approver', 'reassign_request_approver') then
            concat('Reassigned step approver to ', coalesce(al.metadata->>'new_approver_name', 'new approver'))
          when al.action in ('admin_validate_leave_request', 'validate_leave_request') then
            concat('Validated leave request: ', coalesce(al.metadata->>'new_paid_days', '0'), ' paid, ', coalesce(al.metadata->>'new_unpaid_days', '0'), ' unpaid')
          when al.action in ('admin_validate_esarf_request', 'validate_esarf_request') then
            concat('Validated ESARF request: ', coalesce(al.metadata->>'new_total_hours', '0'), ' hrs')
          when al.action in ('admin_revalidate_esarf_request', 'revalidate_esarf_request') then
            concat('Re-validated ESARF request: ', coalesce(al.metadata->>'new_total_hours', '0'), ' hrs')
          else null
        end,
        al.metadata->>'reason',
        al.metadata->>'note',
        ''
      ) as description,
      al.metadata
    from public.audit_logs al
    left join public.user_profiles actor_up on actor_up.id = al.actor_user_profile_id
    left join public.employees actor_e on actor_e.id = actor_up.employee_id
    left join public.positions target_pos on (
      al.entity_type = 'position' and target_pos.id = al.entity_id
    )
    left join public.departments target_dept on (
      al.entity_type = 'department' and target_dept.id = al.entity_id
    )
    left join public.user_profiles target_up on (
      (al.entity_type in ('user', 'user_profile') and target_up.id = al.entity_id)
      or (
        al.metadata->>'user_profile_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and target_up.id = (al.metadata->>'user_profile_id')::uuid
      )
    )
    left join public.employees target_e on (
      (al.entity_type in ('employee', 'leave_balance', 'offset_balance') and target_e.id = al.entity_id)
      or (al.entity_type in ('user', 'user_profile') and target_e.id = target_up.employee_id)
      or (
        al.metadata->>'target_employee_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and target_e.id = (al.metadata->>'target_employee_id')::uuid
      )
      or (
        al.metadata->>'employee_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        and target_e.id = (al.metadata->>'employee_id')::uuid
      )
    )
    where
      (p_action is null or p_action = 'all' or al.action = p_action)
      and (
        p_entity_type is null or p_entity_type = 'all'
        or al.entity_type = p_entity_type
        or (p_entity_type = 'balance' and al.entity_type in ('leave_balance', 'offset_balance'))
        or (p_entity_type = 'workflow' and al.entity_type in ('authority_assignment', 'position', 'department'))
        or (p_entity_type = 'requests' and al.entity_type in ('request', 'request_approval_step'))
      )
      and (p_start_date is null or al.created_at >= p_start_date)
      and (p_end_date is null or al.created_at <= p_end_date)
      and (
        v_search is null
        or lower(al.action) like '%' || v_search || '%'
        or lower(al.entity_type) like '%' || v_search || '%'
        or lower(coalesce(actor_up.username, '')) like '%' || v_search || '%'
        or lower(coalesce(actor_e.first_name || ' ' || actor_e.last_name, '')) like '%' || v_search || '%'
        or lower(coalesce(target_e.first_name || ' ' || target_e.last_name, '')) like '%' || v_search || '%'
        or lower(coalesce(al.metadata::text, '')) like '%' || v_search || '%'
      )
  )
  select
    f.id,
    f.created_at,
    f.action,
    f.action_label,
    f.entity_type,
    f.entity_id,
    f.actor_user_profile_id,
    f.actor_username,
    f.actor_full_name,
    f.actor_role,
    f.target_name,
    f.target_identifier,
    f.description,
    f.metadata,
    count(*) over() as total_count
  from filtered f
  order by f.created_at desc
  limit coalesce(p_limit, 50)
  offset coalesce(p_offset, 0);
end;
$$;

grant execute on function public.admin_get_audit_logs(text, text, text, timestamptz, timestamptz, int, int) to authenticated, anon, service_role;

notify pgrst, 'reload schema';

