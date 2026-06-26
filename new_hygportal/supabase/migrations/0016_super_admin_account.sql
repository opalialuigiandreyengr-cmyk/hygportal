do $$
declare
  v_auth_user_id uuid;
begin
  select id
  into v_auth_user_id
  from auth.users
  where lower(email) = 'hygportal@gmail.com'
  limit 1;

  if v_auth_user_id is not null then
    insert into public.user_profiles (
      auth_user_id,
      employee_id,
      username,
      app_role,
      is_active
    )
    values (
      v_auth_user_id,
      null,
      'hygportal',
      'super_admin',
      true
    )
    on conflict (auth_user_id) do update
    set
      username = excluded.username,
      app_role = 'super_admin',
      is_active = true;
  end if;
end $$;
