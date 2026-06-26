create or replace function public.ensure_own_employee_profile_link()
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_auth_email text;
  v_employee_id uuid;
  v_profile_id uuid;
begin
  if v_auth_user_id is null then
    raise exception 'You must be signed in to load your employee profile.';
  end if;

  select id
  into v_profile_id
  from public.user_profiles
  where auth_user_id = v_auth_user_id
  limit 1;

  if v_profile_id is not null then
    return v_profile_id;
  end if;

  select lower(email)
  into v_auth_email
  from auth.users
  where id = v_auth_user_id
  limit 1;

  if v_auth_email is null then
    return null;
  end if;

  select id
  into v_employee_id
  from public.employees
  where lower(email) = v_auth_email
  order by created_at desc
  limit 1;

  if v_employee_id is null then
    return null;
  end if;

  if exists (
    select 1
    from public.user_profiles
    where employee_id = v_employee_id
  ) then
    return null;
  end if;

  insert into public.user_profiles (
    auth_user_id,
    employee_id,
    username,
    app_role,
    is_active
  )
  values (
    v_auth_user_id,
    v_employee_id,
    split_part(v_auth_email, '@', 1),
    'employee',
    true
  )
  returning id into v_profile_id;

  return v_profile_id;
end;
$$;

grant execute on function public.ensure_own_employee_profile_link() to authenticated;
