-- Migration 0173: Leave credit automatic allocation checking mechanism and default handling.
-- Automatic allocation rules:
--   - If employee has completed 1 year (or 365 days) of service:
--     * Manager positions automatically receive 7 days annual leave credit.
--     * Regular employees automatically receive 5 days annual leave credit.
--     * Other eligible positions receive 7 days annual leave credit.
--   - If employee has under 1 year of service: automatically receives 0 days annual leave credit.
--   - Super Admin can view, adjust, and allocate leave credits directly.
-- Existing records in public.leave_balances are strictly preserved and unaffected.

-- 1. Alter table column default to 0 (applies to future inserts)
alter table if exists public.leave_balances
  alter column annual_credit_days set default 0;

-- 2. Function to calculate initial leave credits based on service tenure and position
create or replace function public.calculate_initial_leave_credits(p_employee_id uuid)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_effective_from date;
  v_position_name text;
  v_employee_type text;
  v_is_one_year boolean;
  v_is_manager boolean;
begin
  if p_employee_id is null then
    return 0;
  end if;

  select
    ea.effective_from,
    p.name,
    epd.employee_type
  into
    v_effective_from,
    v_position_name,
    v_employee_type
  from public.employees e
  left join public.employee_profile_details epd on epd.employee_id = e.id
  left join lateral (
    select *
    from public.employee_assignments current_ea
    where current_ea.employee_id = e.id
      and current_ea.is_primary = true
    order by
      case
        when current_ea.effective_to is null or current_ea.effective_to >= current_date then 0
        else 1
      end,
      current_ea.effective_from desc,
      current_ea.created_at desc
    limit 1
  ) ea on true
  left join public.positions p on p.id = ea.position_id
  where e.id = p_employee_id;

  if v_effective_from is null then
    return 0;
  end if;

  -- 1 year or 365 days of service check
  v_is_one_year := (current_date >= (v_effective_from + interval '1 year') or (current_date - v_effective_from) >= 365);
  if not v_is_one_year then
    return 0;
  end if;

  -- Role / Position evaluation
  v_is_manager := coalesce(lower(trim(v_position_name)), '') like '%manager%';
  if v_is_manager then
    return 7;
  end if;

  if coalesce(lower(trim(v_employee_type)), '') = 'regular' then
    return 5;
  end if;

  return 7;
end;
$$;

grant execute on function public.calculate_initial_leave_credits(uuid) to anon, authenticated, service_role;

-- 3. Update get_available_leave_days to coalesce missing balances to 0 instead of 7
create or replace function public.get_available_leave_days(p_employee_id uuid)
returns numeric
language sql
security definer
set search_path = public
as $$
  select greatest(
    0,
    coalesce((
      select annual_credit_days - used_days
      from public.leave_balances
      where employee_id = p_employee_id
    ), 0)
  );
$$;

grant execute on function public.get_available_leave_days(uuid) to authenticated;

-- 4. Update admin_create_unlinked_user to initialize new employee balance using tenure and position checking
create or replace function public.admin_create_unlinked_user(
  p_username text,
  p_email text,
  p_password text,
  p_app_role text default 'employee',
  p_employee_id uuid default null,
  p_company_ids uuid[] default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_admin record;
  v_username text := nullif(lower(trim(coalesce(p_username, ''))), '');
  v_email text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_password text := coalesce(p_password, '');
  v_role text := lower(trim(coalesce(p_app_role, 'employee')));
  v_auth_user_id uuid := gen_random_uuid();
  v_profile_id uuid;
  v_initial_credits numeric := 0;
begin
  select *
  into v_admin
  from public.admin_desktop_login_check()
  limit 1;

  if v_admin.app_role not in ('admin', 'super_admin') then
    raise exception 'Admin access is required.';
  end if;

  if v_username is null then
    raise exception 'Username is required.';
  end if;

  if v_email is null or v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid email address.';
  end if;

  if length(v_password) < 6 then
    raise exception 'Password must be at least 6 characters.';
  end if;

  if v_role not in ('employee', 'hr', 'admin', 'super_admin') then
    raise exception 'Role must be employee, hr, admin, or super_admin.';
  end if;

  if v_role = 'super_admin' and v_admin.app_role <> 'super_admin' then
    raise exception 'Only a super admin can create a super admin.';
  end if;

  if exists (select 1 from public.user_profiles where lower(username) = v_username) then
    raise exception 'This username is already taken.';
  end if;

  if exists (select 1 from auth.users where lower(email::text) = v_email) then
    raise exception 'This email is already registered.';
  end if;

  if p_employee_id is not null then
    if not exists (select 1 from public.employees where id = p_employee_id) then
      raise exception 'Selected employee was not found.';
    end if;
    if exists (select 1 from public.user_profiles where employee_id = p_employee_id) then
      raise exception 'This employee is already linked to another user.';
    end if;
  end if;

  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    confirmation_token,
    recovery_token,
    email_change,
    email_change_token_new,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    v_auth_user_id,
    'authenticated',
    'authenticated',
    v_email,
    crypt(v_password, gen_salt('bf', 10)),
    now(),
    '',
    '',
    '',
    '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('email_verified', true),
    now(),
    now()
  );

  insert into auth.identities (
    provider_id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  )
  values (
    v_auth_user_id::text,
    v_auth_user_id,
    jsonb_build_object(
      'sub', v_auth_user_id::text,
      'email', v_email,
      'email_verified', true,
      'phone_verified', false
    ),
    'email',
    now(),
    now(),
    now()
  );

  insert into public.user_profiles (
    auth_user_id,
    employee_id,
    username,
    app_role,
    is_active
  )
  values (
    v_auth_user_id,
    p_employee_id,
    v_username,
    v_role,
    true
  )
  returning id into v_profile_id;

  if p_employee_id is not null then
    v_initial_credits := public.calculate_initial_leave_credits(p_employee_id);
    insert into public.leave_balances (employee_id, annual_credit_days, used_days)
    values (p_employee_id, v_initial_credits, 0)
    on conflict (employee_id) do nothing;
  end if;

  -- Insert company assignments if company ids are provided
  if p_company_ids is not null then
    declare
      c_id uuid;
    begin
      foreach c_id in array p_company_ids loop
        insert into public.hr_company_assignments (user_profile_id, company_id)
        values (v_profile_id, c_id)
        on conflict (user_profile_id, company_id) do nothing;
      end loop;
    end;
  end if;

  return v_profile_id;
end;
$$;

grant execute on function public.admin_create_unlinked_user(text, text, text, text, uuid, uuid[]) to authenticated;

-- 5. Update admin_registered_users and admin_get_registered_users to directly return database leave balances
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
set search_path = public
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
    coalesce(lb.annual_credit_days, case when e.id is null then null else 0 end) as leave_credit_days,
    coalesce(lb.used_days, case when e.id is null then null else 0 end) as leave_used_days,
    case
      when e.id is null then null
      else coalesce(lb.annual_credit_days, 0) - coalesce(lb.used_days, 0)
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

grant execute on function public.admin_registered_users() to authenticated;

create or replace function public.admin_get_registered_users()
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
set search_path = public
as $$
begin
  return query select * from public.admin_registered_users();
end;
$$;

grant execute on function public.admin_get_registered_users() to authenticated;

-- 6. Update admin_set_employee_leave_credits to default new record using tenure checking
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
  v_used_days numeric;
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

  if p_annual_credit_days is null or p_annual_credit_days < 0 then
    raise exception 'Leave credits must be zero or higher.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null then
    raise exception 'User was not found.';
  end if;

  if v_profile.employee_id is null then
    raise exception 'Leave credits can only be allocated to linked employees.';
  end if;

  insert into public.leave_balances (employee_id, annual_credit_days, used_days)
  values (v_profile.employee_id, public.calculate_initial_leave_credits(v_profile.employee_id), 0)
  on conflict (employee_id) do nothing;

  select used_days
  into v_used_days
  from public.leave_balances
  where employee_id = v_profile.employee_id;

  if p_annual_credit_days < coalesce(v_used_days, 0) then
    raise exception 'Annual leave credits cannot be lower than used leave days (%).', v_used_days;
  end if;

  update public.leave_balances
  set annual_credit_days = round(p_annual_credit_days, 2),
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
    v_actor.id,
    'set_leave_credits',
    'user_profile',
    v_profile.id,
    jsonb_build_object(
      'employee_id', v_profile.employee_id,
      'annual_credit_days', round(p_annual_credit_days, 2)
    )
  );

  return v_profile.id;
end;
$$;

grant execute on function public.admin_set_employee_leave_credits(uuid, numeric) to authenticated;

-- 7. Update admin_deduct_employee_leave_credits to default using tenure checking
create or replace function public.admin_deduct_employee_leave_credits(
  p_user_profile_id uuid,
  p_deduct_days numeric,
  p_reason text
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

  if p_deduct_days is null or p_deduct_days <= 0 then
    raise exception 'Deduction days must be greater than zero.';
  end if;

  if p_reason is null or trim(p_reason) = '' then
    raise exception 'Reason is required for leave credit deduction.';
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

  insert into public.leave_balances (employee_id, annual_credit_days, used_days)
  values (v_profile.employee_id, public.calculate_initial_leave_credits(v_profile.employee_id), 0)
  on conflict (employee_id) do nothing;

  select coalesce(lb.annual_credit_days, 0), coalesce(lb.used_days, 0)
  into v_current_annual, v_used_days
  from public.leave_balances lb
  where lb.employee_id = v_profile.employee_id;

  v_new_used := round(v_used_days + p_deduct_days, 2);

  if v_new_used > v_current_annual then
    raise exception 'Deduction exceeds available credits. Remaining: % day(s).', v_current_annual - v_used_days;
  end if;

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
    v_actor.id,
    'deduct_leave_credits',
    'user_profile',
    v_profile.id,
    jsonb_build_object(
      'employee_id', v_profile.employee_id,
      'deduct_days', p_deduct_days,
      'reason', trim(p_reason),
      'previous_used_days', v_used_days,
      'new_used_days', v_new_used
    )
  );

  return v_profile.id;
end;
$$;

grant execute on function public.admin_deduct_employee_leave_credits(uuid, numeric, text) to authenticated;

-- 8. Update admin_reimburse_employee_leave_credits to default using tenure checking
create or replace function public.admin_reimburse_employee_leave_credits(
  p_user_profile_id uuid,
  p_reimburse_days numeric,
  p_reason text
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

  if p_reimburse_days is null or p_reimburse_days <= 0 then
    raise exception 'Reimbursement days must be greater than zero.';
  end if;

  if p_reason is null or trim(p_reason) = '' then
    raise exception 'Reason is required for leave credit reimbursement.';
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

  insert into public.leave_balances (employee_id, annual_credit_days, used_days)
  values (v_profile.employee_id, public.calculate_initial_leave_credits(v_profile.employee_id), 0)
  on conflict (employee_id) do nothing;

  select coalesce(lb.annual_credit_days, 0), coalesce(lb.used_days, 0)
  into v_current_annual, v_used_days
  from public.leave_balances lb
  where lb.employee_id = v_profile.employee_id;

  if v_used_days >= p_reimburse_days then
    v_new_used := round(v_used_days - p_reimburse_days, 2);
    v_new_annual := v_current_annual;
  else
    v_new_used := 0;
    v_new_annual := round(v_current_annual + (p_reimburse_days - v_used_days), 2);
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
    v_actor.id,
    'reimburse_leave_credits',
    'user_profile',
    v_profile.id,
    jsonb_build_object(
      'employee_id', v_profile.employee_id,
      'reimburse_days', p_reimburse_days,
      'reason', trim(p_reason),
      'old_annual_credit_days', v_current_annual,
      'new_annual_credit_days', v_new_annual,
      'old_used_days', v_used_days,
      'new_used_days', v_new_used
    )
  );

  return v_profile.id;
end;
$$;

grant execute on function public.admin_reimburse_employee_leave_credits(uuid, numeric, text) to authenticated;

-- 9. Update admin_validate_leave_request to default using tenure checking
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
  v_old_paid numeric;
  v_diff numeric;
  v_new_type text;
begin
  select r.submitted_by_employee_id, coalesce(lrd.paid_days, 0)
  into v_emp_id, v_old_paid
  from public.requests r
  join public.leave_request_details lrd on lrd.request_id = r.id
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

  return 'Leave request validated successfully.';
end;
$$;

grant execute on function public.admin_validate_leave_request(uuid, numeric, numeric) to authenticated;
grant execute on function public.admin_validate_leave_request(uuid, numeric, numeric) to anon;
grant execute on function public.admin_validate_leave_request(uuid, numeric, numeric) to service_role;

-- 10. Update apply_leave_side_effects to default using tenure checking
create or replace function public.apply_leave_side_effects(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.requests;
  v_request_type public.request_types;
  v_leave public.leave_request_details;
  v_current_available numeric;
  v_new_used numeric;
  v_balance_after numeric;
begin
  select * into v_request
  from public.requests
  where id = p_request_id;

  select * into v_request_type
  from public.request_types
  where id = v_request.request_type_id;

  if v_request_type.code <> 'leave' then
    return;
  end if;

  select * into v_leave
  from public.leave_request_details
  where request_id = p_request_id;

  if coalesce(v_leave.paid_days, 0) <= 0 then
    return;
  end if;

  if exists (
    select 1
    from public.leave_transactions
    where request_id = p_request_id
      and transaction_type = 'use_paid'
  ) then
    return;
  end if;

  insert into public.leave_balances (employee_id, annual_credit_days, used_days)
  values (v_request.submitted_by_employee_id, public.calculate_initial_leave_credits(v_request.submitted_by_employee_id), 0)
  on conflict (employee_id) do nothing;

  select coalesce(annual_credit_days - used_days, 0)
  into v_current_available
  from public.leave_balances
  where employee_id = v_request.submitted_by_employee_id
  for update;

  if v_current_available < v_leave.paid_days then
    raise exception 'Insufficient paid leave credits at approval time.';
  end if;

  update public.leave_balances
  set used_days = used_days + v_leave.paid_days,
      updated_at = now()
  where employee_id = v_request.submitted_by_employee_id
  returning used_days, annual_credit_days - used_days
  into v_new_used, v_balance_after;

  insert into public.leave_transactions (
    employee_id,
    request_id,
    transaction_type,
    days,
    balance_after
  )
  values (
    v_request.submitted_by_employee_id,
    p_request_id,
    'use_paid',
    v_leave.paid_days,
    v_balance_after
  );
end;
$$;

grant execute on function public.apply_leave_side_effects(uuid) to authenticated;

-- 11. Update submit_leave_request to default using tenure checking
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

  insert into public.leave_balances (employee_id, annual_credit_days, used_days)
  values (v_profile.employee_id, public.calculate_initial_leave_credits(v_profile.employee_id), 0)
  on conflict (employee_id) do nothing;

  v_available_days := public.get_available_leave_days(v_profile.employee_id);
  if v_paid_days > v_available_days then
    raise exception 'Insufficient paid leave credits. Available paid leave: % day(s).', v_available_days;
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

  select *
  into v_route
  from public.approval_level_routes
  where requester_level = v_position.authority_level
    and (department_id = v_assignment.department_id or department_id is null)
  order by
    case when department_id = v_assignment.department_id then 0 else 1 end,
    step_order asc
  limit 1;

  if v_route.approver_level is null then
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
      1,
      v_assignment.function_id,
      v_position.authority_level,
      'admin_fallback',
      'No approval route configured.'
    );

    update public.requests
    set status = 'needs_admin_review'
    where id = v_request_id;
  else
    select *
    into v_approver
    from public.find_request_approver(
      v_assignment.id,
      v_assignment.function_id,
      v_route.approver_level,
      v_profile.employee_id,
      '{}'
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
        1,
        v_assignment.function_id,
        v_route.approver_level,
        'admin_fallback',
        'No matching approver found.'
      );

      update public.requests
      set status = 'needs_admin_review'
      where id = v_request_id;
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
        1,
        v_assignment.function_id,
        v_approver.resolved_level,
        v_approver.approver_employee_id,
        v_approver.approver_user_profile_id,
        'pending'
      );
    end if;
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

-- 12. Update create_employee_profile_with_store to initialize leave_balances on employee creation
create or replace function public.create_employee_profile_with_store(
  p_last_name text,
  p_first_name text,
  p_middle_name text,
  p_suffix text,
  p_birth_date date,
  p_gender text,
  p_civil_status text,
  p_cellphone text,
  p_email text,
  p_company text,
  p_work_unit text,
  p_store text,
  p_position text,
  p_date_hired date,
  p_employee_type text,
  p_tin text,
  p_sss text,
  p_pagibig text,
  p_philhealth text,
  p_bank_type text,
  p_account_no text,
  p_education text,
  p_present_address text,
  p_emergency_contact text,
  p_document_refs jsonb default null,
  p_emergency_contact_no text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee_id uuid;
  v_store_id uuid;
  v_store_name text := nullif(trim(coalesce(p_store, '')), '');
begin
  if v_store_name is null then
    raise exception 'Please select a store or N/A.';
  end if;

  if lower(v_store_name) <> 'n/a' then
    select s.id into v_store_id
    from public.stores s
    join public.companies c on c.id = s.company_id
    where lower(s.name) = lower(v_store_name)
      and lower(c.name) = lower(trim(p_company))
      and s.is_active = true
      and c.is_active = true
    limit 1;

    if v_store_id is null then
      raise exception 'Selected store was not found for this company.';
    end if;
  end if;

  v_employee_id := public.create_employee_profile(
    p_last_name,
    p_first_name,
    p_middle_name,
    p_suffix,
    p_birth_date,
    p_gender,
    p_civil_status,
    p_cellphone,
    p_email,
    p_company,
    p_work_unit,
    p_position,
    p_date_hired,
    p_employee_type,
    p_tin,
    p_sss,
    p_pagibig,
    p_philhealth,
    p_bank_type,
    p_account_no,
    p_education,
    p_present_address,
    p_emergency_contact,
    p_document_refs
  );

  update public.employee_assignments
  set store_id = v_store_id
  where employee_id = v_employee_id
    and is_primary = true;

  update public.employee_profile_details
  set emergency_contact_no = nullif(trim(coalesce(p_emergency_contact_no, '')), ''),
      updated_at = now()
  where employee_id = v_employee_id;

  insert into public.leave_balances (employee_id, annual_credit_days, used_days)
  values (v_employee_id, public.calculate_initial_leave_credits(v_employee_id), 0)
  on conflict (employee_id) do nothing;

  return v_employee_id;
end;
$$;

grant execute on function public.create_employee_profile_with_store(
  text, text, text, text, date, text, text, text, text, text, text, text,
  text, date, text, text, text, text, text, text, text, text, text, text, jsonb, text
) to anon, authenticated;

-- 13. Update link_employee_login_account to initialize leave_balances on employee registration
create or replace function public.link_employee_login_account(
  p_employee_id uuid,
  p_auth_user_id uuid,
  p_terms_accepted boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
begin
  if p_employee_id is null or p_auth_user_id is null then
    raise exception 'Employee and login account are required.';
  end if;

  if p_terms_accepted is not true then
    raise exception 'Terms and conditions must be accepted.';
  end if;

  if exists (
    select 1
    from public.user_profiles
    where employee_id = p_employee_id
  ) then
    raise exception 'This employee profile already has a registered login account.';
  end if;

  insert into public.user_profiles (
    auth_user_id,
    employee_id,
    app_role,
    is_active
  )
  values (
    p_auth_user_id,
    p_employee_id,
    'employee',
    true
  )
  returning id into v_profile_id;

  insert into public.leave_balances (employee_id, annual_credit_days, used_days)
  values (p_employee_id, public.calculate_initial_leave_credits(p_employee_id), 0)
  on conflict (employee_id) do nothing;

  return v_profile_id;
end;
$$;

grant execute on function public.link_employee_login_account(uuid, uuid, boolean) to anon, authenticated;

notify pgrst, 'reload schema';
