-- One-time: create user accounts for all employees not yet linked to a user.
-- Username = first name (lowercase), email = employee email, password = 12345678

create extension if not exists pgcrypto with schema extensions;

do $$
declare
  v_emp record;
  v_username text;
  v_email text;
  v_password text := '12345678';
  v_auth_user_id uuid;
  v_profile_id uuid;
  v_first_name text;
  v_count int := 0;
begin
  for v_emp in
    select e.id, e.first_name, e.last_name, e.email, e.employee_no
    from public.employees e
    where not exists (
      select 1 from public.user_profiles up where up.employee_id = e.id
    )
    and lower(trim(coalesce(e.first_name, ''))) not in ('', 'n/a', 'na')
  loop
    v_first_name := lower(trim(regexp_replace(coalesce(v_emp.first_name, ''), '[^a-zA-Z]', '', 'g')));

    if v_first_name is null or length(v_first_name) < 2 then
      v_first_name := 'user' || coalesce(v_emp.employee_no, v_count::text);
    end if;

    v_username := v_first_name;
    v_email := coalesce(nullif(trim(lower(coalesce(v_emp.email, ''))), ''), v_first_name || '@hygportal.local');

    if exists (select 1 from auth.users where lower(email::text) = v_email) then
      v_email := v_first_name || '_' || replace(v_emp.id::text, '-', '') || '@hygportal.local';
    end if;

    if exists (select 1 from public.user_profiles where lower(username) = v_username) then
      v_username := v_username || '_' || left(replace(v_emp.id::text, '-', ''), 6);
    end if;

    v_auth_user_id := gen_random_uuid();

    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, confirmation_token, recovery_token,
      email_change, email_change_token_new,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) values (
      '00000000-0000-0000-0000-000000000000',
      v_auth_user_id, 'authenticated', 'authenticated',
      v_email, extensions.crypt(v_password, extensions.gen_salt('bf', 10)),
      now(), '', '', '', '',
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('email_verified', true),
      now(), now()
    );

    insert into auth.identities (
      provider_id, user_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      v_auth_user_id::text, v_auth_user_id,
      jsonb_build_object(
        'sub', v_auth_user_id::text,
        'email', v_email,
        'email_verified', true,
        'phone_verified', false
      ),
      'email', now(), now(), now()
    );

    insert into public.user_profiles (
      auth_user_id, employee_id, username, app_role, is_active
    ) values (
      v_auth_user_id, v_emp.id, v_username, 'employee', true
    ) returning id into v_profile_id;

    insert into public.leave_balances (employee_id, annual_credit_days, used_days)
    values (v_emp.id, 7, 0)
    on conflict (employee_id) do nothing;

    v_count := v_count + 1;
  end loop;

  raise notice 'Created % user accounts for unlinked employees.', v_count;
end $$;

notify pgrst, 'reload schema';
