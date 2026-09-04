-- Let admins view, set, add, and deduct offset balance from the registered users screen.

drop function if exists public.admin_registered_users();

create or replace function public.admin_registered_users()
returns table (
  user_profile_id uuid,
  auth_user_id uuid,
  username text,
  email text,
  app_role text,
  is_active boolean,
  is_banned boolean,
  employee_id uuid,
  employee_no text,
  full_name text,
  photo_url text,
  employment_status text,
  leave_credit_days numeric,
  leave_used_days numeric,
  leave_remaining_days numeric,
  offset_balance_hours numeric,
  registered_at timestamptz,
  email_confirmed_at timestamptz,
  last_sign_in_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_profile public.user_profiles;
begin
  select *
  into v_profile
  from public.user_profiles up
  where up.auth_user_id = auth.uid()
    and up.app_role in ('admin', 'super_admin')
    and up.is_active = true;

  if v_profile.id is null then
    raise exception 'Admin access is required.';
  end if;

  return query
  select
    up.id as user_profile_id,
    au.id as auth_user_id,
    up.username,
    au.email::text as email,
    up.app_role,
    up.is_active,
    coalesce(au.banned_until > now(), false) as is_banned,
    e.id as employee_id,
    e.employee_no,
    nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), '') as full_name,
    e.photo_url,
    e.employment_status,
    coalesce(lb.annual_credit_days, case when e.id is null then null else 7 end) as leave_credit_days,
    coalesce(lb.used_days, case when e.id is null then null else 0 end) as leave_used_days,
    case
      when e.id is null then null
      else coalesce(lb.annual_credit_days, 7) - coalesce(lb.used_days, 0)
    end as leave_remaining_days,
    coalesce(ob.balance_hours, case when e.id is null then null else 0 end) as offset_balance_hours,
    up.created_at as registered_at,
    au.email_confirmed_at,
    au.last_sign_in_at
  from public.user_profiles up
  join auth.users au on au.id = up.auth_user_id
  left join public.employees e on e.id = up.employee_id
  left join public.leave_balances lb on lb.employee_id = e.id
  left join public.offset_balances ob on ob.employee_id = e.id
  order by up.created_at desc, up.username nulls last;
end;
$$;

create or replace function public.admin_set_employee_offset_balance(
  p_user_profile_id uuid,
  p_balance_hours numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_profile public.user_profiles;
  v_current_balance numeric;
begin
  select *
  into v_actor
  from public.user_profiles up
  where up.auth_user_id = auth.uid()
    and up.app_role in ('admin', 'super_admin')
    and up.is_active = true;

  if v_actor.id is null then
    raise exception 'Admin access is required.';
  end if;

  if p_balance_hours is null or p_balance_hours < 0 then
    raise exception 'Offset balance must be zero or higher.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null then
    raise exception 'User was not found.';
  end if;

  if v_profile.employee_id is null then
    raise exception 'Offset balance can only be allocated to linked employees.';
  end if;

  select coalesce(ob.balance_hours, 0)
  into v_current_balance
  from public.offset_balances ob
  where ob.employee_id = v_profile.employee_id;

  insert into public.offset_balances (employee_id, balance_hours, updated_at)
  values (v_profile.employee_id, round(p_balance_hours, 2), now())
  on conflict (employee_id) do update
  set balance_hours = round(p_balance_hours, 2),
      updated_at = now();

  insert into public.offset_transactions (
    employee_id,
    transaction_type,
    hours,
    balance_after,
    created_at
  )
  values (
    v_profile.employee_id,
    'adjustment',
    round(p_balance_hours - coalesce(v_current_balance, 0), 2),
    round(p_balance_hours, 2),
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
    v_actor.id,
    'admin_set_employee_offset_balance',
    'offset_balance',
    v_profile.employee_id,
    jsonb_build_object(
      'user_profile_id', p_user_profile_id,
      'previous_balance_hours', v_current_balance,
      'new_balance_hours', round(p_balance_hours, 2)
    )
  );

  return p_user_profile_id;
end;
$$;

create or replace function public.admin_add_employee_offset_balance(
  p_user_profile_id uuid,
  p_add_hours numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_profile public.user_profiles;
  v_current_balance numeric;
  v_new_balance numeric;
begin
  select *
  into v_actor
  from public.user_profiles up
  where up.auth_user_id = auth.uid()
    and up.app_role in ('admin', 'super_admin')
    and up.is_active = true;

  if v_actor.id is null then
    raise exception 'Admin access is required.';
  end if;

  if p_add_hours is null or p_add_hours <= 0 then
    raise exception 'Hours to add must be greater than zero.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null then
    raise exception 'User was not found.';
  end if;

  if v_profile.employee_id is null then
    raise exception 'Offset balance can only be added to linked employees.';
  end if;

  select coalesce(ob.balance_hours, 0)
  into v_current_balance
  from public.offset_balances ob
  where ob.employee_id = v_profile.employee_id;

  v_new_balance := round(coalesce(v_current_balance, 0) + p_add_hours, 2);

  insert into public.offset_balances (employee_id, balance_hours, updated_at)
  values (v_profile.employee_id, v_new_balance, now())
  on conflict (employee_id) do update
  set balance_hours = v_new_balance,
      updated_at = now();

  insert into public.offset_transactions (
    employee_id,
    transaction_type,
    hours,
    balance_after,
    created_at
  )
  values (
    v_profile.employee_id,
    'adjustment',
    round(p_add_hours, 2),
    v_new_balance,
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
    v_actor.id,
    'admin_add_employee_offset_balance',
    'offset_balance',
    v_profile.employee_id,
    jsonb_build_object(
      'user_profile_id', p_user_profile_id,
      'add_hours', round(p_add_hours, 2),
      'previous_balance_hours', v_current_balance,
      'new_balance_hours', v_new_balance
    )
  );

  return p_user_profile_id;
end;
$$;

create or replace function public.admin_deduct_employee_offset_balance(
  p_user_profile_id uuid,
  p_deduct_hours numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_profile public.user_profiles;
  v_current_balance numeric;
  v_new_balance numeric;
begin
  select *
  into v_actor
  from public.user_profiles up
  where up.auth_user_id = auth.uid()
    and up.app_role in ('admin', 'super_admin')
    and up.is_active = true;

  if v_actor.id is null then
    raise exception 'Admin access is required.';
  end if;

  if p_deduct_hours is null or p_deduct_hours <= 0 then
    raise exception 'Hours to deduct must be greater than zero.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null then
    raise exception 'User was not found.';
  end if;

  if v_profile.employee_id is null then
    raise exception 'Offset balance can only be deducted from linked employees.';
  end if;

  select coalesce(ob.balance_hours, 0)
  into v_current_balance
  from public.offset_balances ob
  where ob.employee_id = v_profile.employee_id;

  if coalesce(v_current_balance, 0) < p_deduct_hours then
    raise exception 'Cannot deduct more than available offset balance (% hrs).', coalesce(v_current_balance, 0);
  end if;

  v_new_balance := round(v_current_balance - p_deduct_hours, 2);

  update public.offset_balances
  set balance_hours = v_new_balance,
      updated_at = now()
  where employee_id = v_profile.employee_id;

  insert into public.offset_transactions (
    employee_id,
    transaction_type,
    hours,
    balance_after,
    created_at
  )
  values (
    v_profile.employee_id,
    'adjustment',
    -round(p_deduct_hours, 2),
    v_new_balance,
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
    v_actor.id,
    'admin_deduct_employee_offset_balance',
    'offset_balance',
    v_profile.employee_id,
    jsonb_build_object(
      'user_profile_id', p_user_profile_id,
      'deduct_hours', round(p_deduct_hours, 2),
      'previous_balance_hours', v_current_balance,
      'new_balance_hours', v_new_balance
    )
  );

  return p_user_profile_id;
end;
$$;

grant execute on function public.admin_registered_users() to authenticated;
grant execute on function public.admin_set_employee_offset_balance(uuid, numeric) to authenticated;
grant execute on function public.admin_add_employee_offset_balance(uuid, numeric) to authenticated;
grant execute on function public.admin_deduct_employee_offset_balance(uuid, numeric) to authenticated;

notify pgrst, 'reload schema';
