alter table public.user_profiles
add column if not exists username text;

create unique index if not exists idx_user_profiles_username_lower
on public.user_profiles (lower(username))
where username is not null;

create or replace function public.link_employee_login_account(
  p_employee_id uuid,
  p_auth_user_id uuid,
  p_username text,
  p_terms_accepted boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
  v_username text := nullif(lower(trim(p_username)), '');
begin
  if p_employee_id is null or p_auth_user_id is null then
    raise exception 'Employee and login account are required.';
  end if;

  if v_username is null then
    raise exception 'Username is required.';
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

  if exists (
    select 1
    from public.user_profiles
    where lower(username) = v_username
  ) then
    raise exception 'This username is already taken.';
  end if;

  insert into public.user_profiles (
    auth_user_id,
    employee_id,
    username,
    app_role,
    is_active
  )
  values (
    p_auth_user_id,
    p_employee_id,
    v_username,
    'employee',
    true
  )
  returning id into v_profile_id;

  return v_profile_id;
end;
$$;

grant execute on function public.link_employee_login_account(uuid, uuid, text, boolean) to anon, authenticated;

create or replace function public.resolve_login_email(p_username text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text;
begin
  if lower(trim(p_username)) = 'hygportal' then
    return 'hygportal@gmail.com';
  end if;

  select au.email
  into v_email
  from public.user_profiles up
  join auth.users au on au.id = up.auth_user_id
  where lower(up.username) = lower(trim(p_username))
    and up.is_active = true
  limit 1;

  if v_email is null then
    raise exception 'Username was not found.';
  end if;

  return v_email;
end;
$$;

grant execute on function public.resolve_login_email(text) to anon, authenticated;
