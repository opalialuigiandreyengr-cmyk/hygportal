-- Let admins view and allocate annual leave credits from the registered users screen.

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
    up.created_at as registered_at,
    au.email_confirmed_at,
    au.last_sign_in_at
  from public.user_profiles up
  join auth.users au on au.id = up.auth_user_id
  left join public.employees e on e.id = up.employee_id
  left join public.leave_balances lb on lb.employee_id = e.id
  order by up.created_at desc, up.username nulls last;
end;
$$;

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
  values (v_profile.employee_id, 7, 0)
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
    'admin_set_employee_leave_credits',
    'leave_balance',
    v_profile.employee_id,
    jsonb_build_object(
      'user_profile_id', p_user_profile_id,
      'annual_credit_days', round(p_annual_credit_days, 2),
      'used_days', v_used_days
    )
  );

  return p_user_profile_id;
end;
$$;

grant execute on function public.admin_registered_users() to authenticated;
grant execute on function public.admin_set_employee_leave_credits(uuid, numeric) to authenticated;

notify pgrst, 'reload schema';
