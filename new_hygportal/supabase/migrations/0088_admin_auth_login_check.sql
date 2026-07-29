-- Validate Flutter admin login using the signed-in Supabase user.

create or replace function public.admin_desktop_login_check()
returns table (
  username text,
  app_role text
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_auth_user auth.users;
  v_profile public.user_profiles;
begin
  select *
  into v_auth_user
  from auth.users
  where id = auth.uid();

  if v_auth_user.id is null then
    raise exception 'Admin login is required.';
  end if;

  if lower(v_auth_user.email) = 'hygportal@gmail.com' then
    insert into public.user_profiles (
      auth_user_id,
      employee_id,
      username,
      app_role,
      is_active
    )
    values (
      v_auth_user.id,
      null,
      'hygportal',
      'super_admin',
      true
    )
    on conflict (auth_user_id) do update
    set username = excluded.username,
        app_role = 'super_admin',
        is_active = true;
  end if;

  select *
  into v_profile
  from public.user_profiles up
  where up.auth_user_id = v_auth_user.id
    and up.is_active = true
  limit 1;

  if v_profile.id is null or v_profile.app_role not in ('admin', 'super_admin') then
    raise exception 'Admin access is required.';
  end if;

  return query
  select coalesce(v_profile.username, v_auth_user.email), v_profile.app_role;
end;
$$;

grant execute on function public.admin_desktop_login_check() to authenticated;

notify pgrst, 'reload schema';
