-- Admin actions for registered login users.

create extension if not exists pgcrypto with schema extensions;

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
  employment_status text,
  registered_at timestamptz,
  email_confirmed_at timestamptz,
  last_sign_in_at timestamptz
)
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_admin record;
begin
  select *
  into v_admin
  from public.admin_desktop_login_check()
  limit 1;

  if v_admin.app_role not in ('admin', 'super_admin') then
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
    e.employment_status,
    up.created_at as registered_at,
    au.email_confirmed_at,
    au.last_sign_in_at
  from public.user_profiles up
  join auth.users au on au.id = up.auth_user_id
  left join public.employees e on e.id = up.employee_id
  order by up.created_at desc, up.username nulls last;
end;
$$;

create or replace function public.admin_set_user_ban(
  p_user_profile_id uuid,
  p_is_banned boolean
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_admin record;
  v_profile public.user_profiles;
begin
  select *
  into v_admin
  from public.admin_desktop_login_check()
  limit 1;

  if v_admin.app_role not in ('admin', 'super_admin') then
    raise exception 'Admin access is required.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null then
    raise exception 'User was not found.';
  end if;

  if v_profile.auth_user_id = auth.uid() then
    raise exception 'You cannot ban your own admin account.';
  end if;

  update auth.users
  set banned_until = case
        when p_is_banned then now() + interval '100 years'
        else null
      end,
      updated_at = now()
  where id = v_profile.auth_user_id;

  update public.user_profiles
  set is_active = not p_is_banned
  where id = p_user_profile_id;

  return p_user_profile_id;
end;
$$;

create or replace function public.admin_set_user_role(
  p_user_profile_id uuid,
  p_app_role text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_admin record;
  v_profile public.user_profiles;
  v_role text := lower(trim(coalesce(p_app_role, '')));
begin
  select *
  into v_admin
  from public.admin_desktop_login_check()
  limit 1;

  if v_admin.app_role not in ('admin', 'super_admin') then
    raise exception 'Admin access is required.';
  end if;

  if v_role not in ('employee', 'hr', 'admin', 'super_admin') then
    raise exception 'Role must be employee, hr, admin, or super_admin.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null then
    raise exception 'User was not found.';
  end if;

  if v_profile.auth_user_id = auth.uid() then
    raise exception 'You cannot change your own admin role.';
  end if;

  if v_role = 'super_admin' and v_admin.app_role <> 'super_admin' then
    raise exception 'Only a super admin can assign super admin.';
  end if;

  update public.user_profiles
  set app_role = v_role
  where id = p_user_profile_id;

  return p_user_profile_id;
end;
$$;

create or replace function public.admin_reset_user_password(
  p_user_profile_id uuid,
  p_new_password text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_admin record;
  v_profile public.user_profiles;
  v_password text := coalesce(p_new_password, '');
begin
  select *
  into v_admin
  from public.admin_desktop_login_check()
  limit 1;

  if v_admin.app_role not in ('admin', 'super_admin') then
    raise exception 'Admin access is required.';
  end if;

  if length(v_password) < 6 then
    raise exception 'Password must be at least 6 characters.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null then
    raise exception 'User was not found.';
  end if;

  update auth.users
  set encrypted_password = crypt(v_password, gen_salt('bf')),
      updated_at = now()
  where id = v_profile.auth_user_id;

  return p_user_profile_id;
end;
$$;

grant execute on function public.admin_registered_users() to authenticated;
grant execute on function public.admin_set_user_ban(uuid, boolean) to authenticated;
grant execute on function public.admin_set_user_role(uuid, text) to authenticated;
grant execute on function public.admin_reset_user_password(uuid, text) to authenticated;

notify pgrst, 'reload schema';
