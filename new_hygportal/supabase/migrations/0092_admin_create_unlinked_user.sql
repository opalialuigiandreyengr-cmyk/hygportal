-- Admin creation of login users that are not linked to employee profiles.

create extension if not exists pgcrypto with schema extensions;

create or replace function public.admin_create_unlinked_user(
  p_username text,
  p_email text,
  p_password text,
  p_app_role text default 'employee'
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
    now(),
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
    null,
    v_username,
    v_role,
    true
  )
  returning id into v_profile_id;

  return v_profile_id;
end;
$$;

grant execute on function public.admin_create_unlinked_user(text, text, text, text) to authenticated;

notify pgrst, 'reload schema';
