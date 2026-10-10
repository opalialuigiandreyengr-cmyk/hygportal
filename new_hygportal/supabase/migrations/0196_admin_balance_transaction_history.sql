-- Migration 0196: Dedicated Transaction History for Leave Credits & Offset Balances
-- Provides a unified, auditable transaction ledger for super admins and admins
-- covering all leave credit and offset balance earned, allocated, reimbursed, used, and deducted.

-- 1. Relax leave_transactions type check constraint to accommodate all transaction types
alter table public.leave_transactions drop constraint if exists leave_transactions_type_check;
alter table public.leave_transactions add constraint leave_transactions_type_check check (
  transaction_type in ('use_paid', 'use', 'adjustment', 'deduct', 'deduction', 'reimburse', 'refund', 'grant', 'allocation', 'set', 'set_credits', 'annual_credit')
);

-- 2. Update admin_deduct_employee_leave_credits to also write to leave_transactions
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

  -- Insert ledger entry into leave_transactions
  insert into public.leave_transactions (
    employee_id,
    request_id,
    transaction_type,
    days,
    balance_after,
    created_at
  )
  values (
    v_profile.employee_id,
    null,
    'deduct',
    -round(p_deduct_days, 2),
    round(v_current_annual - v_new_used, 2),
    now()
  );

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

-- 3. Update admin_reimburse_employee_leave_credits to also write to leave_transactions
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

  if v_policy.role_tier <> 'excluded' then
    if not coalesce(v_policy.is_eligible, false) then
      raise exception 'Cannot reimburse: Employee has not reached 1-year tenure under the leave credit allocation policy.';
    end if;
  end if;

  if v_used_days >= p_reimburse_days then
    v_new_used := round(v_used_days - p_reimburse_days, 2);
    v_new_annual := v_current_annual;
  else
    v_new_used := 0;
    v_new_annual := round(v_current_annual + (p_reimburse_days - v_used_days), 2);
  end if;

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

  -- Insert ledger entry into leave_transactions
  insert into public.leave_transactions (
    employee_id,
    request_id,
    transaction_type,
    days,
    balance_after,
    created_at
  )
  values (
    v_profile.employee_id,
    null,
    'reimburse',
    round(p_reimburse_days, 2),
    round(v_new_annual - v_new_used, 2),
    now()
  );

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

-- 4. Update admin_set_employee_leave_credits to also write to leave_transactions
create or replace function public.admin_set_employee_leave_credits(
  p_user_profile_id uuid,
  p_annual_credit_days numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_profile public.user_profiles;
  v_current_annual numeric;
  v_used_days numeric;
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

  if p_annual_credit_days is null or p_annual_credit_days < 0 then
    raise exception 'Annual leave credits must be 0 or greater.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null then
    raise exception 'User was not found.';
  end if;

  if v_profile.employee_id is null then
    raise exception 'Leave credits can only be assigned to linked employees.';
  end if;

  insert into public.leave_balances (employee_id, annual_credit_days, used_days)
  values (v_profile.employee_id, p_annual_credit_days, 0)
  on conflict (employee_id) do nothing;

  select coalesce(annual_credit_days, 0), coalesce(used_days, 0)
  into v_current_annual, v_used_days
  from public.leave_balances
  where employee_id = v_profile.employee_id
  for update;

  update public.leave_balances
  set annual_credit_days = round(p_annual_credit_days, 2),
      updated_at = now()
  where employee_id = v_profile.employee_id;

  -- Insert ledger entry into leave_transactions
  insert into public.leave_transactions (
    employee_id,
    request_id,
    transaction_type,
    days,
    balance_after,
    created_at
  )
  values (
    v_profile.employee_id,
    null,
    'allocation',
    round(p_annual_credit_days - coalesce(v_current_annual, 0), 2),
    round(p_annual_credit_days - coalesce(v_used_days, 0), 2),
    now()
  );

  insert into public.audit_logs (
    actor_user_profile_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    coalesce(v_actor.id, v_profile.id),
    'admin_set_employee_leave_credits',
    'leave_balance',
    v_profile.employee_id,
    jsonb_build_object(
      'user_profile_id', p_user_profile_id,
      'annual_credit_days', round(p_annual_credit_days, 2),
      'previous_annual_credit_days', v_current_annual,
      'used_days', v_used_days
    )
  );

  return v_profile.id;
end;
$$;

grant execute on function public.admin_set_employee_leave_credits(uuid, numeric) to authenticated, anon, service_role;

-- 5. Create unified public.admin_get_balance_transactions
create or replace function public.admin_get_balance_transactions(
  p_employee_id uuid default null,
  p_user_profile_id uuid default null,
  p_balance_type text default null,
  p_limit int default 500
)
returns table (
  id text,
  user_profile_id uuid,
  employee_id uuid,
  employee_no text,
  full_name text,
  username text,
  photo_url text,
  balance_type text,
  category text,
  title text,
  subtitle text,
  amount numeric,
  unit text,
  balance_after numeric,
  reason text,
  actor_name text,
  request_id uuid,
  request_status text,
  created_at timestamptz,
  date_from text,
  date_to text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_emp_id uuid := p_employee_id;
begin
  if p_user_profile_id is not null and v_target_emp_id is null then
    select up.employee_id into v_target_emp_id
    from public.user_profiles up
    where up.id = p_user_profile_id;
  end if;

  return query
  with raw_records as (
    -- ==========================================
    -- 1. OFFSET TRANSACTIONS
    -- ==========================================
    select
      ('offset_' || ot.id::text) as id,
      up.id as user_profile_id,
      ot.employee_id,
      coalesce(e.employee_no, '-') as employee_no,
      coalesce(trim(concat_ws(' ', e.first_name, e.last_name)), up.username, 'Unknown Employee') as full_name,
      coalesce(up.username, 'unlinked') as username,
      e.photo_url,
      'offset'::text as balance_type,
      case
        when ot.request_id is not null and (ot.transaction_type in ('use', 'deduct', 'deduction') or coalesce(ot.hours, 0) < 0) then 'use'
        when ot.request_id is not null and ot.transaction_type in ('refund') then 'refund'
        when ot.request_id is not null and (ot.transaction_type = 'adjustment' and r.status in ('rejected', 'cancelled')) then 'refund'
        when ot.request_id is not null and ot.transaction_type in ('earn', 'credit') then 'earn'
        when ot.request_id is null and (ot.transaction_type in ('deduct', 'deduction') or coalesce(ot.hours, 0) < 0) then 'deduction'
        when ot.request_id is null and (ot.transaction_type in ('earn', 'add', 'credit') or coalesce(ot.hours, 0) > 0) then 'allocation'
        else 'allocation'
      end as category,
      case
        when ot.request_id is not null and (ot.transaction_type in ('use', 'deduct', 'deduction') or coalesce(ot.hours, 0) < 0) then 'Offset Deducted'
        when ot.request_id is not null and ot.transaction_type in ('refund') then 'Offset Refunded'
        when ot.request_id is not null and (ot.transaction_type = 'adjustment' and r.status in ('rejected', 'cancelled')) then 'Offset Refunded'
        when ot.request_id is not null and ot.transaction_type in ('earn', 'credit') then 'Offset Earned'
        when ot.request_id is null and (ot.transaction_type in ('deduct', 'deduction') or coalesce(ot.hours, 0) < 0) then 'Offset Deducted (Admin)'
        when ot.request_id is null and (ot.transaction_type in ('earn', 'add', 'credit') or coalesce(ot.hours, 0) > 0) then 'Offset Added (Admin)'
        else 'Offset Adjustment'
      end as title,
      case
        when ot.request_id is not null and trd.transaction_type is not null and trd.transaction_type <> '' then trd.transaction_type
        when ot.request_id is not null and (ot.transaction_type in ('use', 'deduct') or coalesce(ot.hours, 0) < 0) then 'Use Offset Request'
        when ot.request_id is not null and ot.transaction_type in ('refund', 'adjustment') then 'Credited back upon rejection'
        when ot.request_id is not null and ot.transaction_type in ('earn', 'credit') then 'ESARF Offset Credit'
        when ot.request_id is null and (ot.transaction_type in ('deduct', 'deduction') or coalesce(ot.hours, 0) < 0) then 'Admin deduction'
        when ot.request_id is null and (ot.transaction_type in ('earn', 'add', 'credit') or coalesce(ot.hours, 0) > 0) then 'Admin credit addition'
        else 'Admin balance adjustment'
      end as subtitle,
      case
        when ot.transaction_type in ('use', 'deduct', 'deduction') or coalesce(ot.hours, 0) < 0 then -abs(coalesce(ot.hours, 0))
        else abs(coalesce(ot.hours, 0))
      end as amount,
      'hours'::text as unit,
      ot.balance_after,
      coalesce(al.metadata->>'reason', trd.reason, r.rejected_reason, 'Offset adjustment') as reason,
      case
        when ot.request_id is not null then coalesce(trim(concat_ws(' ', e.first_name, e.last_name)), up.username, 'Employee')
        when actor_e.first_name is not null then trim(concat_ws(' ', actor_e.first_name, actor_e.last_name))
        when actor_up.username is not null then actor_up.username
        else 'Super Admin'
      end as actor_name,
      ot.request_id,
      r.status as request_status,
      ot.created_at,
      trd.date_from::text as date_from,
      trd.date_to::text as date_to
    from public.offset_transactions ot
    left join public.employees e on e.id = ot.employee_id
    left join public.user_profiles up on up.employee_id = ot.employee_id
    left join public.requests r on r.id = ot.request_id
    left join public.time_request_details trd on trd.request_id = ot.request_id
    left join lateral (
      select * from public.audit_logs al2
      where al2.entity_type = 'offset_balance'
        and al2.entity_id = ot.employee_id
        and abs(extract(epoch from (al2.created_at - ot.created_at))) < 10
      order by al2.created_at desc limit 1
    ) al on true
    left join public.user_profiles actor_up on actor_up.id = al.actor_user_profile_id
    left join public.employees actor_e on actor_e.id = actor_up.employee_id

    union all

    -- ==========================================
    -- 2. LEAVE TRANSACTIONS
    -- ==========================================
    select
      ('leave_' || lt.id::text) as id,
      up.id as user_profile_id,
      lt.employee_id,
      coalesce(e.employee_no, '-') as employee_no,
      coalesce(trim(concat_ws(' ', e.first_name, e.last_name)), up.username, 'Unknown Employee') as full_name,
      coalesce(up.username, 'unlinked') as username,
      e.photo_url,
      'leave'::text as balance_type,
      case
        when lt.transaction_type in ('use_paid', 'use') or (lt.request_id is not null and coalesce(lt.days, 0) < 0) then 'use'
        when lt.transaction_type in ('deduct', 'deduction') or (lt.request_id is null and coalesce(lt.days, 0) < 0) then 'deduction'
        when lt.transaction_type in ('reimburse', 'refund') then 'refund'
        when lt.transaction_type in ('grant', 'credit', 'annual_credit', 'allocation', 'set', 'set_credits') then 'allocation'
        else 'allocation'
      end as category,
      case
        when lt.transaction_type in ('use_paid', 'use') or (lt.request_id is not null and coalesce(lt.days, 0) < 0) then coalesce(lrd.leave_category || ' (Paid)', 'Paid Leave Deducted')
        when lt.transaction_type in ('deduct', 'deduction') or (lt.request_id is null and coalesce(lt.days, 0) < 0) then 'Leave Deducted (Admin)'
        when lt.transaction_type in ('reimburse', 'refund') then 'Credit Reimbursed (Admin)'
        when lt.transaction_type in ('grant', 'credit', 'annual_credit', 'allocation', 'set', 'set_credits') then 'Leave Credits Allocated'
        else 'Leave Adjustment'
      end as title,
      case
        when lt.request_id is not null then 'Approved paid leave'
        when lt.transaction_type in ('deduct', 'deduction') or coalesce(lt.days, 0) < 0 then 'Admin deduction'
        when lt.transaction_type in ('reimburse', 'refund') then 'Admin reimbursement'
        when lt.transaction_type in ('grant', 'credit', 'annual_credit', 'allocation') then 'Admin allocation'
        else 'Leave credit adjustment'
      end as subtitle,
      case
        when lt.transaction_type in ('use_paid', 'use', 'deduct', 'deduction') or coalesce(lt.days, 0) < 0 then -abs(coalesce(lt.days, 0))
        else abs(coalesce(lt.days, 0))
      end as amount,
      'days'::text as unit,
      lt.balance_after,
      coalesce(al.metadata->>'reason', lrd.reason, r.rejected_reason, 'Leave credit transaction') as reason,
      case
        when lt.request_id is not null then coalesce(trim(concat_ws(' ', e.first_name, e.last_name)), up.username, 'Employee')
        when actor_e.first_name is not null then trim(concat_ws(' ', actor_e.first_name, actor_e.last_name))
        when actor_up.username is not null then actor_up.username
        else 'Super Admin'
      end as actor_name,
      lt.request_id,
      r.status as request_status,
      lt.created_at,
      lrd.start_date::text as date_from,
      lrd.end_date::text as date_to
    from public.leave_transactions lt
    left join public.employees e on e.id = lt.employee_id
    left join public.user_profiles up on up.employee_id = lt.employee_id
    left join public.requests r on r.id = lt.request_id
    left join public.leave_request_details lrd on lrd.request_id = lt.request_id
    left join lateral (
      select * from public.audit_logs al2
      where al2.entity_type = 'leave_balance'
        and al2.entity_id = lt.employee_id
        and abs(extract(epoch from (al2.created_at - lt.created_at))) < 10
      order by al2.created_at desc limit 1
    ) al on true
    left join public.user_profiles actor_up on actor_up.id = al.actor_user_profile_id
    left join public.employees actor_e on actor_e.id = actor_up.employee_id

    union all

    -- ==========================================
    -- 3. HISTORICAL AUDIT LOGS FOR LEAVE CREDITS (legacy rows not in leave_transactions)
    -- ==========================================
    select
      ('audit_' || al.id::text) as id,
      up.id as user_profile_id,
      coalesce(e.id, up.employee_id) as employee_id,
      coalesce(e.employee_no, '-') as employee_no,
      coalesce(trim(concat_ws(' ', e.first_name, e.last_name)), up.username, 'Unknown Employee') as full_name,
      coalesce(up.username, 'unlinked') as username,
      e.photo_url,
      'leave'::text as balance_type,
      case
        when al.action in ('admin_deduct_employee_leave_credits', 'deduct_leave_credits') then 'deduction'
        when al.action in ('admin_reimburse_employee_leave_credits', 'reimburse_leave_credits') then 'refund'
        else 'allocation'
      end as category,
      case
        when al.action in ('admin_deduct_employee_leave_credits', 'deduct_leave_credits') then 'Leave Deducted (Admin)'
        when al.action in ('admin_reimburse_employee_leave_credits', 'reimburse_leave_credits') then 'Credit Reimbursed (Admin)'
        else 'Leave Credits Allocated'
      end as title,
      case
        when al.action in ('admin_deduct_employee_leave_credits', 'deduct_leave_credits') then coalesce(al.metadata->>'reason', 'Admin deduction')
        when al.action in ('admin_reimburse_employee_leave_credits', 'reimburse_leave_credits') then coalesce(al.metadata->>'reason', 'Admin reimbursement')
        else coalesce(al.metadata->>'reason', 'Admin credit allocation')
      end as subtitle,
      case
        when al.action in ('admin_deduct_employee_leave_credits', 'deduct_leave_credits') then -abs(coalesce((al.metadata->>'deduct_days')::numeric, 0))
        when al.action in ('admin_reimburse_employee_leave_credits', 'reimburse_leave_credits') then abs(coalesce((al.metadata->>'reimburse_days')::numeric, 0))
        when al.action in ('admin_set_employee_leave_credits', 'set_leave_credits') then abs(coalesce((al.metadata->>'annual_credit_days')::numeric, 0))
        else 0
      end as amount,
      'days'::text as unit,
      coalesce(
        (al.metadata->>'new_annual_credit_days')::numeric,
        (al.metadata->>'annual_credit_days')::numeric
      ) as balance_after,
      coalesce(al.metadata->>'reason', 'Admin action logged') as reason,
      case
        when actor_e.first_name is not null then trim(concat_ws(' ', actor_e.first_name, actor_e.last_name))
        when actor_up.username is not null then actor_up.username
        else 'Super Admin'
      end as actor_name,
      null::uuid as request_id,
      'approved'::text as request_status,
      al.created_at,
      null::text as date_from,
      null::text as date_to
    from public.audit_logs al
    left join public.user_profiles up on (
      (al.entity_type = 'user_profile' and up.id = al.entity_id)
      or (al.entity_type = 'leave_balance' and up.employee_id = al.entity_id)
      or (al.metadata->>'user_profile_id' is not null and up.id = (al.metadata->>'user_profile_id')::uuid)
    )
    left join public.employees e on e.id = coalesce(up.employee_id, case when al.entity_type = 'leave_balance' then al.entity_id else null end)
    left join public.user_profiles actor_up on actor_up.id = al.actor_user_profile_id
    left join public.employees actor_e on actor_e.id = actor_up.employee_id
    where al.action in (
      'admin_set_employee_leave_credits',
      'set_leave_credits',
      'admin_deduct_employee_leave_credits',
      'deduct_leave_credits',
      'admin_reimburse_employee_leave_credits',
      'reimburse_leave_credits'
    )
    and not exists (
      select 1 from public.leave_transactions lt2
      where lt2.employee_id = coalesce(e.id, up.employee_id)
        and abs(extract(epoch from (lt2.created_at - al.created_at))) < 10
    )

    union all

    -- ==========================================
    -- 4. INITIAL ANNUAL POLICY GRANT FROM leave_balances
    -- ==========================================
    select
      ('policy_grant_' || lb.employee_id::text) as id,
      up.id as user_profile_id,
      lb.employee_id,
      coalesce(e.employee_no, '-') as employee_no,
      coalesce(trim(concat_ws(' ', e.first_name, e.last_name)), up.username, 'Unknown Employee') as full_name,
      coalesce(up.username, 'unlinked') as username,
      e.photo_url,
      'leave'::text as balance_type,
      'allocation'::text as category,
      'Annual Leave Credits Granted'::text as title,
      'Policy leave entitlement'::text as subtitle,
      coalesce(lb.annual_credit_days, 0) as amount,
      'days'::text as unit,
      round(coalesce(lb.annual_credit_days, 0) - coalesce(lb.used_days, 0), 2) as balance_after,
      'Annual leave policy credit entitlement'::text as reason,
      'System Policy'::text as actor_name,
      null::uuid as request_id,
      'approved'::text as request_status,
      coalesce(lb.updated_at, e.created_at, now()) as created_at,
      null::text as date_from,
      null::text as date_to
    from public.leave_balances lb
    left join public.employees e on e.id = lb.employee_id
    left join public.user_profiles up on up.employee_id = lb.employee_id
    where coalesce(lb.annual_credit_days, 0) > 0
      and not exists (
        select 1 from public.leave_transactions lt3
        where lt3.employee_id = lb.employee_id
          and lt3.transaction_type in ('grant', 'credit', 'annual_credit', 'allocation', 'set', 'set_credits')
      )
      and not exists (
        select 1 from public.audit_logs al3
        where (al3.entity_id = lb.employee_id or al3.metadata->>'employee_id' = lb.employee_id::text)
          and al3.action in ('admin_set_employee_leave_credits', 'set_leave_credits')
      )
  )
  select *
  from raw_records
  where (v_target_emp_id is null or employee_id = v_target_emp_id)
    and (p_balance_type is null or balance_type = p_balance_type)
  order by created_at desc
  limit coalesce(p_limit, 500);
end;
$$;

grant execute on function public.admin_get_balance_transactions(uuid, uuid, text, int) to authenticated, anon, service_role;

notify pgrst, 'reload schema';
