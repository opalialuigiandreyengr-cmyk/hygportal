-- Migration 0194: Fix Admin Offset Balance RPC Overloading Ambiguity
-- Resolves PGRST203 ambiguity between (uuid, numeric) and (uuid, numeric, text default ...)
-- Allows Super Admin and Admin to manually add or deduct offset hours in the Users screen
-- without affecting current leave allocations or any other quotas.

-- 1. Drop all ambiguous overloaded variants
drop function if exists public.admin_add_employee_offset_balance(uuid, numeric);
drop function if exists public.admin_add_employee_offset_balance(uuid, numeric, text);
drop function if exists public.admin_deduct_employee_offset_balance(uuid, numeric);
drop function if exists public.admin_deduct_employee_offset_balance(uuid, numeric, text);
drop function if exists public.admin_set_employee_offset_balance(uuid, numeric);
drop function if exists public.admin_set_employee_offset_balance(uuid, numeric, text);

-- 2. Ensure offset_transactions check constraint allows all adjustment types
alter table public.offset_transactions drop constraint if exists offset_transactions_type_check;
alter table public.offset_transactions add constraint offset_transactions_type_check
  check (transaction_type in ('earn', 'credit', 'use', 'deduct', 'deduction', 'adjustment', 'refund', 'add'));

-- 3. Unified admin_add_employee_offset_balance
create or replace function public.admin_add_employee_offset_balance(
  p_user_profile_id uuid,
  p_add_hours numeric,
  p_reason text default 'Admin addition'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_profile public.user_profiles;
  v_current_bal numeric;
  v_new_bal numeric;
begin
  select * into v_actor
  from public.user_profiles
  where auth_user_id = auth.uid()
    and app_role in ('admin', 'super_admin')
    and is_active = true;

  if v_actor.id is null and current_user not in ('postgres', 'service_role', 'supabase_admin') then
    raise exception 'Admin access is required.';
  end if;

  if p_add_hours is null or p_add_hours <= 0 then
    raise exception 'Hours to add must be greater than zero.';
  end if;

  select * into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null or v_profile.employee_id is null then
    raise exception 'Target employee not found for this user.';
  end if;

  insert into public.offset_balances (employee_id, balance_hours, updated_at)
  values (v_profile.employee_id, 0, now())
  on conflict (employee_id) do nothing;

  select coalesce(balance_hours, 0)
  into v_current_bal
  from public.offset_balances
  where employee_id = v_profile.employee_id
  for update;

  v_new_bal := round(v_current_bal + p_add_hours, 2);

  update public.offset_balances
  set balance_hours = v_new_bal,
      updated_at = now()
  where employee_id = v_profile.employee_id;

  insert into public.offset_transactions (
    employee_id,
    request_id,
    transaction_type,
    hours,
    balance_after,
    created_at
  )
  values (
    v_profile.employee_id,
    null,
    'earn',
    round(p_add_hours, 2),
    v_new_bal,
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
    'admin_add_employee_offset_balance',
    'offset_balance',
    v_profile.employee_id,
    jsonb_build_object(
      'user_profile_id', p_user_profile_id,
      'employee_id', v_profile.employee_id,
      'add_hours', round(p_add_hours, 2),
      'previous_balance_hours', v_current_bal,
      'new_balance_hours', v_new_bal,
      'reason', coalesce(nullif(trim(p_reason), ''), 'Admin addition')
    )
  );

  return v_profile.id;
end;
$$;

-- 4. Unified admin_deduct_employee_offset_balance
create or replace function public.admin_deduct_employee_offset_balance(
  p_user_profile_id uuid,
  p_deduct_hours numeric,
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
  v_current_bal numeric;
  v_new_bal numeric;
begin
  select * into v_actor
  from public.user_profiles
  where auth_user_id = auth.uid()
    and app_role in ('admin', 'super_admin')
    and is_active = true;

  if v_actor.id is null and current_user not in ('postgres', 'service_role', 'supabase_admin') then
    raise exception 'Admin access is required.';
  end if;

  if p_deduct_hours is null or p_deduct_hours <= 0 then
    raise exception 'Hours to deduct must be greater than zero.';
  end if;

  select * into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null or v_profile.employee_id is null then
    raise exception 'Target employee not found for this user.';
  end if;

  insert into public.offset_balances (employee_id, balance_hours, updated_at)
  values (v_profile.employee_id, 0, now())
  on conflict (employee_id) do nothing;

  select coalesce(balance_hours, 0)
  into v_current_bal
  from public.offset_balances
  where employee_id = v_profile.employee_id
  for update;

  if v_current_bal < p_deduct_hours then
    raise exception 'Cannot deduct more than available offset balance (% hrs).', v_current_bal;
  end if;

  v_new_bal := greatest(0, round(v_current_bal - p_deduct_hours, 2));

  update public.offset_balances
  set balance_hours = v_new_bal,
      updated_at = now()
  where employee_id = v_profile.employee_id;

  insert into public.offset_transactions (
    employee_id,
    request_id,
    transaction_type,
    hours,
    balance_after,
    created_at
  )
  values (
    v_profile.employee_id,
    null,
    'deduct',
    -round(p_deduct_hours, 2),
    v_new_bal,
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
    'admin_deduct_employee_offset_balance',
    'offset_balance',
    v_profile.employee_id,
    jsonb_build_object(
      'user_profile_id', p_user_profile_id,
      'employee_id', v_profile.employee_id,
      'deduct_hours', round(p_deduct_hours, 2),
      'previous_balance_hours', v_current_bal,
      'new_balance_hours', v_new_bal,
      'reason', coalesce(nullif(trim(p_reason), ''), 'Admin deduction')
    )
  );

  return v_profile.id;
end;
$$;

-- 5. Unified admin_set_employee_offset_balance
create or replace function public.admin_set_employee_offset_balance(
  p_user_profile_id uuid,
  p_balance_hours numeric,
  p_reason text default 'Admin set balance'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_profile public.user_profiles;
  v_current_bal numeric;
  v_diff numeric;
begin
  select * into v_actor
  from public.user_profiles
  where auth_user_id = auth.uid()
    and app_role in ('admin', 'super_admin')
    and is_active = true;

  if v_actor.id is null and current_user not in ('postgres', 'service_role', 'supabase_admin') then
    raise exception 'Admin access is required.';
  end if;

  if p_balance_hours is null or p_balance_hours < 0 then
    raise exception 'Offset balance cannot be negative.';
  end if;

  select * into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null or v_profile.employee_id is null then
    raise exception 'Target employee not found for this user.';
  end if;

  insert into public.offset_balances (employee_id, balance_hours, updated_at)
  values (v_profile.employee_id, 0, now())
  on conflict (employee_id) do nothing;

  select coalesce(balance_hours, 0)
  into v_current_bal
  from public.offset_balances
  where employee_id = v_profile.employee_id
  for update;

  v_diff := round(p_balance_hours - v_current_bal, 2);

  update public.offset_balances
  set balance_hours = round(p_balance_hours, 2),
      updated_at = now()
  where employee_id = v_profile.employee_id;

  if v_diff <> 0 then
    insert into public.offset_transactions (
      employee_id,
      request_id,
      transaction_type,
      hours,
      balance_after,
      created_at
    )
    values (
      v_profile.employee_id,
      null,
      case when v_diff < 0 then 'deduct' else 'earn' end,
      v_diff,
      round(p_balance_hours, 2),
      now()
    );
  end if;

  insert into public.audit_logs (
    actor_user_profile_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    coalesce(v_actor.id, v_profile.id),
    'admin_set_employee_offset_balance',
    'offset_balance',
    v_profile.employee_id,
    jsonb_build_object(
      'user_profile_id', p_user_profile_id,
      'employee_id', v_profile.employee_id,
      'new_balance_hours', round(p_balance_hours, 2),
      'previous_balance_hours', v_current_bal,
      'diff_hours', v_diff,
      'reason', coalesce(nullif(trim(p_reason), ''), 'Admin set balance')
    )
  );

  return v_profile.id;
end;
$$;

-- 6. Permissions and PostgREST schema cache reload
grant execute on function public.admin_add_employee_offset_balance(uuid, numeric, text) to authenticated, anon, service_role;
grant execute on function public.admin_deduct_employee_offset_balance(uuid, numeric, text) to authenticated, anon, service_role;
grant execute on function public.admin_set_employee_offset_balance(uuid, numeric, text) to authenticated, anon, service_role;

notify pgrst, 'reload schema';
