-- Admin registered users directory for Flutter desktop.

create or replace function public.admin_registered_users()
returns table (
  user_profile_id uuid,
  auth_user_id uuid,
  username text,
  email text,
  app_role text,
  is_active boolean,
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
set search_path = public, auth
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

grant execute on function public.admin_registered_users() to authenticated;

notify pgrst, 'reload schema';
