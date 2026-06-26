create or replace function public.update_own_employee_profile(
  p_first_name text,
  p_middle_name text,
  p_last_name text,
  p_suffix text,
  p_birth_date date,
  p_gender text,
  p_civil_status text,
  p_cellphone text,
  p_email text,
  p_username text,
  p_employee_type text,
  p_tin text,
  p_sss text,
  p_pagibig text,
  p_philhealth text,
  p_bank_type text,
  p_account_no text,
  p_education text,
  p_present_address text,
  p_emergency_contact text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_username text := nullif(lower(trim(p_username)), '');
  v_email text := nullif(lower(trim(p_email)), '');
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to update your profile.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  if v_profile.id is null or v_profile.employee_id is null then
    raise exception 'This login is not linked to an employee profile.';
  end if;

  if nullif(trim(p_first_name), '') is null
    or nullif(trim(p_last_name), '') is null
    or nullif(trim(p_cellphone), '') is null then
    raise exception 'First name, last name, and cellphone number are required.';
  end if;

  if v_username is not null and exists (
    select 1
    from public.user_profiles
    where lower(username) = v_username
      and id <> v_profile.id
  ) then
    raise exception 'This username is already taken.';
  end if;

  if v_email is not null and exists (
    select 1
    from public.employees
    where lower(email) = v_email
      and id <> v_profile.employee_id
  ) then
    raise exception 'This email address is already used by another employee profile.';
  end if;

  update public.employees
  set
    first_name = trim(p_first_name),
    middle_name = nullif(trim(p_middle_name), ''),
    last_name = trim(p_last_name),
    suffix = nullif(trim(p_suffix), ''),
    birth_date = p_birth_date,
    gender = nullif(trim(p_gender), ''),
    civil_status = nullif(trim(p_civil_status), ''),
    email = v_email,
    phone = trim(p_cellphone),
    updated_at = now()
  where id = v_profile.employee_id;

  update public.user_profiles
  set username = v_username
  where id = v_profile.id;

  insert into public.employee_profile_details (
    employee_id,
    employee_type,
    tin,
    sss,
    pagibig,
    philhealth,
    bank_type,
    account_no,
    education,
    present_address,
    emergency_contact
  )
  values (
    v_profile.employee_id,
    nullif(trim(p_employee_type), ''),
    nullif(trim(p_tin), ''),
    nullif(trim(p_sss), ''),
    nullif(trim(p_pagibig), ''),
    nullif(trim(p_philhealth), ''),
    nullif(trim(p_bank_type), ''),
    nullif(trim(p_account_no), ''),
    nullif(trim(p_education), ''),
    nullif(trim(p_present_address), ''),
    nullif(trim(p_emergency_contact), '')
  )
  on conflict (employee_id) do update
  set
    employee_type = excluded.employee_type,
    tin = excluded.tin,
    sss = excluded.sss,
    pagibig = excluded.pagibig,
    philhealth = excluded.philhealth,
    bank_type = excluded.bank_type,
    account_no = excluded.account_no,
    education = excluded.education,
    present_address = excluded.present_address,
    emergency_contact = excluded.emergency_contact,
    updated_at = now();

  return v_profile.employee_id;
end;
$$;

grant execute on function public.update_own_employee_profile(
  text,
  text,
  text,
  text,
  date,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text
) to authenticated;
