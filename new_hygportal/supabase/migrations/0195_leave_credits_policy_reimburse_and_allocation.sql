-- Migration 0195: Policy-aware Leave Credit Reimbursement, Deduction & Allocation
-- Enforces 1-year tenure & quota policy for regular employees and managers upon reimbursement.
-- Allows General Manager, Operations Director, and Finance Director to be allocated / reimbursed regardless of policy.
-- Fixes manual deduction of leave credits to properly update leave_balances with actor validation and audit logging.

-- 1. Drop existing overloaded functions to prevent PostgREST signature ambiguity
drop function if exists public.admin_reimburse_employee_leave_credits(uuid, numeric);
drop function if exists public.admin_reimburse_employee_leave_credits(uuid, numeric, text);
drop function if exists public.admin_deduct_employee_leave_credits(uuid, numeric);
drop function if exists public.admin_deduct_employee_leave_credits(uuid, numeric, text);

-- 2. Create unified policy-aware admin_reimburse_employee_leave_credits
create or replace function public.admin_reimburse_employee_leave_credits(
  p_user_profile_id uuid,
  p_reimburse_days numeric,
  p_reason text default 'Admin reimbursement'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_profile public.user_profiles;
  v_used_days numeric;
  v_current_annual numeric;
  v_new_used numeric;
  v_new_annual numeric;
  v_policy record;
  v_max_quota numeric;
begin
  select *
  into v_actor
  from public.user_profiles up
  where up.auth_user_id = auth.uid()
    and up.app_role in ('admin', 'super_admin', 'hr')
    and up.is_active = true;

  if v_actor.id is null and current_user not in ('postgres', 'service_role', 'supabase_admin') then
    raise exception 'Admin or HR access is required.';
  end if;

  if p_reimburse_days is null or p_reimburse_days <= 0 then
    raise exception 'Reimbursement days must be greater than zero.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null then
    raise exception 'User was not found.';
  end if;

  if v_profile.employee_id is null then
    raise exception 'Leave credits can only be reimbursed for linked employees.';
  end if;

  -- Check leave credit policy for this employee
  select * into v_policy
  from public.calculate_policy_leave_credits(v_profile.employee_id, current_date)
  limit 1;

  -- Ensure leave_balances row exists
  insert into public.leave_balances (employee_id, annual_credit_days, used_days)
  values (v_profile.employee_id, coalesce(v_policy.allocated_days, 0), 0)
  on conflict (employee_id) do nothing;

  select coalesce(lb.annual_credit_days, 0), coalesce(lb.used_days, 0)
  into v_current_annual, v_used_days
  from public.leave_balances lb
  where lb.employee_id = v_profile.employee_id
  for update;

  -- If NOT excluded (i.e. Regular Employee or Manager), enforce policy tenure!
  if v_policy.role_tier <> 'excluded' then
    if not coalesce(v_policy.is_eligible, false) then
      raise exception 'Cannot reimburse: Employee has not reached 1-year tenure under the leave credit allocation policy.';
    end if;
  end if;

  -- Calculate new used and annual credits
  if v_used_days >= p_reimburse_days then
    v_new_used := round(v_used_days - p_reimburse_days, 2);
    v_new_annual := v_current_annual;
  else
    v_new_used := 0;
    v_new_annual := round(v_current_annual + (p_reimburse_days - v_used_days), 2);
  end if;

  -- If NOT excluded, ensure new annual credits do not exceed role annual quota
  if v_policy.role_tier <> 'excluded' then
    v_max_quota := coalesce(v_policy.annual_quota, case when v_policy.role_tier = 'manager' then 7 else 5 end);
    if v_new_annual > v_max_quota then
      raise exception 'Reimbursement would increase annual credits to % day(s), exceeding the policy quota of % day(s) for %.',
        v_new_annual, v_max_quota, case when v_policy.role_tier = 'manager' then 'managers' else 'regular employees' end;
    end if;
  end if;

  update public.leave_balances
  set annual_credit_days = v_new_annual,
      used_days = v_new_used,
      updated_at = now()
  where employee_id = v_profile.employee_id;

  insert into public.audit_logs (
    actor_user_profile_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    coalesce(v_actor.id, v_profile.id),
    'admin_reimburse_employee_leave_credits',
    'leave_balance',
    v_profile.employee_id,
    jsonb_build_object(
      'user_profile_id', p_user_profile_id,
      'reimburse_days', p_reimburse_days,
      'reason', coalesce(nullif(trim(p_reason), ''), 'Admin reimbursement'),
      'previous_annual_credit_days', v_current_annual,
      'new_annual_credit_days', v_new_annual,
      'previous_used_days', v_used_days,
      'new_used_days', v_new_used,
      'role_tier', v_policy.role_tier
    )
  );

  return v_profile.id;
end;
$$;

grant execute on function public.admin_reimburse_employee_leave_credits(uuid, numeric, text) to authenticated, anon, service_role;

-- 3. Create unified admin_deduct_employee_leave_credits
create or replace function public.admin_deduct_employee_leave_credits(
  p_user_profile_id uuid,
  p_deduct_days numeric,
  p_reason text default 'Admin deduction'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_profile public.user_profiles;
  v_used_days numeric;
  v_current_annual numeric;
  v_new_used numeric;
  v_remaining numeric;
begin
  select *
  into v_actor
  from public.user_profiles up
  where up.auth_user_id = auth.uid()
    and up.app_role in ('admin', 'super_admin', 'hr')
    and up.is_active = true;

  if v_actor.id is null and current_user not in ('postgres', 'service_role', 'supabase_admin') then
    raise exception 'Admin or HR access is required.';
  end if;

  if p_deduct_days is null or p_deduct_days <= 0 then
    raise exception 'Deduction days must be greater than zero.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null then
    raise exception 'User was not found.';
  end if;

  if v_profile.employee_id is null then
    raise exception 'Leave credits can only be deducted from linked employees.';
  end if;

  -- Ensure leave_balances row exists
  insert into public.leave_balances (employee_id, annual_credit_days, used_days)
  values (v_profile.employee_id, public.calculate_initial_leave_credits(v_profile.employee_id), 0)
  on conflict (employee_id) do nothing;

  select coalesce(lb.annual_credit_days, 0), coalesce(lb.used_days, 0)
  into v_current_annual, v_used_days
  from public.leave_balances lb
  where lb.employee_id = v_profile.employee_id
  for update;

  v_remaining := v_current_annual - v_used_days;

  if p_deduct_days > v_remaining then
    raise exception 'Deduction exceeds available leave credits. Remaining: % day(s).', v_remaining;
  end if;

  v_new_used := round(v_used_days + p_deduct_days, 2);

  update public.leave_balances
  set used_days = v_new_used,
      updated_at = now()
  where employee_id = v_profile.employee_id;

  insert into public.audit_logs (
    actor_user_profile_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    coalesce(v_actor.id, v_profile.id),
    'admin_deduct_employee_leave_credits',
    'leave_balance',
    v_profile.employee_id,
    jsonb_build_object(
      'user_profile_id', p_user_profile_id,
      'deduct_days', p_deduct_days,
      'reason', coalesce(nullif(trim(p_reason), ''), 'Admin deduction'),
      'annual_credit_days', v_current_annual,
      'previous_used_days', v_used_days,
      'new_used_days', v_new_used
    )
  );

  return v_profile.id;
end;
$$;

grant execute on function public.admin_deduct_employee_leave_credits(uuid, numeric, text) to authenticated, anon, service_role;

notify pgrst, 'reload schema';
