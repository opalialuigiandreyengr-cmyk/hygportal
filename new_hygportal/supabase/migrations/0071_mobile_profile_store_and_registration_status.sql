-- Mobile profile creation captures stores, and login registration requires HR activation.

create or replace function public.employee_store_options()
returns table (
  store_name text,
  company_name text
)
language sql
security definer
set search_path = public
as $$
  select s.name, c.name
  from public.stores s
  join public.companies c on c.id = s.company_id
  where s.is_active = true
    and c.is_active = true
  order by c.name, s.name;
$$;

grant execute on function public.employee_store_options() to anon, authenticated;

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
  p_document_refs jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee_id uuid;
  v_store_id uuid;
begin
  if nullif(trim(coalesce(p_store, '')), '') is null then
    raise exception 'Please select a store.';
  end if;

  select s.id into v_store_id
  from public.stores s
  join public.companies c on c.id = s.company_id
  where lower(s.name) = lower(trim(p_store))
    and lower(c.name) = lower(trim(p_company))
    and s.is_active = true
    and c.is_active = true
  limit 1;

  if v_store_id is null then
    raise exception 'Selected store was not found for this company.';
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

  return v_employee_id;
end;
$$;

grant execute on function public.create_employee_profile_with_store(
  text, text, text, text, date, text, text, text, text, text, text, text,
  text, date, text, text, text, text, text, text, text, text, text, text, jsonb
) to anon, authenticated;

create or replace function public.verify_employee_for_registration(
  p_first_name text,
  p_last_name text,
  p_middle_name text,
  p_birth_date date,
  p_email text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee public.employees;
  v_already_registered boolean;
begin
  if nullif(trim(p_first_name), '') is null
    or nullif(trim(p_last_name), '') is null
    or p_birth_date is null then
    raise exception 'First name, last name, and birthday are required.';
  end if;

  select *
  into v_employee
  from public.employees e
  where lower(trim(e.first_name)) = lower(trim(p_first_name))
    and lower(trim(e.last_name)) = lower(trim(p_last_name))
    and e.birth_date = p_birth_date
  order by e.created_at desc
  limit 1;

  if v_employee.id is null then
    return jsonb_build_object('verified', false, 'message', 'No employee profile matched the details entered.');
  end if;

  if lower(trim(coalesce(v_employee.employment_status, ''))) <> 'active' then
    return jsonb_build_object(
      'verified', false,
      'message', case
        when lower(trim(coalesce(v_employee.employment_status, ''))) = 'pending'
          then 'Your employee profile is still pending HR approval. You can register after HR activates your profile.'
        else 'Your employee profile is inactive. Please contact HR before registering an account.'
      end
    );
  end if;

  select exists (select 1 from public.user_profiles up where up.employee_id = v_employee.id)
  into v_already_registered;

  if v_already_registered then
    return jsonb_build_object(
      'verified', false,
      'already_registered', true,
      'message', 'This employee profile already has a registered login account.'
    );
  end if;

  return jsonb_build_object(
    'verified', true,
    'employee_id', v_employee.id,
    'employee_no', v_employee.employee_no,
    'full_name', trim(concat_ws(' ', v_employee.first_name, v_employee.middle_name, v_employee.last_name, v_employee.suffix))
  );
end;
$$;

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
  v_employment_status text;
begin
  if p_employee_id is null or p_auth_user_id is null then
    raise exception 'Employee and login account are required.';
  end if;

  select lower(trim(coalesce(e.employment_status, '')))
  into v_employment_status
  from public.employees e
  where e.id = p_employee_id;

  if v_employment_status is distinct from 'active' then
    raise exception 'Your employee profile must be activated by HR before registering an account.';
  end if;

  if v_username is null then
    raise exception 'Username is required.';
  end if;

  if p_terms_accepted is not true then
    raise exception 'Terms and conditions must be accepted.';
  end if;

  if exists (select 1 from public.user_profiles where employee_id = p_employee_id) then
    raise exception 'This employee profile already has a registered login account.';
  end if;

  if exists (select 1 from public.user_profiles where lower(username) = v_username) then
    raise exception 'This username is already taken.';
  end if;

  insert into public.user_profiles (auth_user_id, employee_id, username, app_role, is_active)
  values (p_auth_user_id, p_employee_id, v_username, 'employee', true)
  returning id into v_profile_id;

  return v_profile_id;
end;
$$;

grant execute on function public.verify_employee_for_registration(text, text, text, date, text) to anon, authenticated;
grant execute on function public.link_employee_login_account(uuid, uuid, text, boolean) to anon, authenticated;

notify pgrst, 'reload schema';
