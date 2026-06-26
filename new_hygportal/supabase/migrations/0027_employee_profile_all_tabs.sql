alter table public.employee_profile_details
  add column if not exists religion text,
  add column if not exists birth_place text,
  add column if not exists nationality text,
  add column if not exists height text,
  add column if not exists weight text,
  add column if not exists other_phone text,
  add column if not exists social_media_type text,
  add column if not exists social_media_detail text,
  add column if not exists zip_code text,
  add column if not exists permanent_address text,
  add column if not exists elementary_school text,
  add column if not exists elementary_year text,
  add column if not exists secondary_school text,
  add column if not exists secondary_year text,
  add column if not exists college_school text,
  add column if not exists college_year text,
  add column if not exists college_course text,
  add column if not exists year_graduated text,
  add column if not exists father_name text,
  add column if not exists father_occupation text,
  add column if not exists mother_maiden_name text,
  add column if not exists mother_occupation text,
  add column if not exists number_of_siblings text,
  add column if not exists birth_order text,
  add column if not exists spouse_name text,
  add column if not exists spouse_occupation text,
  add column if not exists spouse_contact text,
  add column if not exists children_names text,
  add column if not exists children_count text;

drop function if exists public.update_own_employee_profile(
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
);

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
  p_emergency_contact text,
  p_religion text default null,
  p_birth_place text default null,
  p_nationality text default null,
  p_height text default null,
  p_weight text default null,
  p_other_phone text default null,
  p_social_media_type text default null,
  p_social_media_detail text default null,
  p_zip_code text default null,
  p_permanent_address text default null,
  p_elementary_school text default null,
  p_elementary_year text default null,
  p_secondary_school text default null,
  p_secondary_year text default null,
  p_college_school text default null,
  p_college_year text default null,
  p_college_course text default null,
  p_year_graduated text default null,
  p_father_name text default null,
  p_father_occupation text default null,
  p_mother_maiden_name text default null,
  p_mother_occupation text default null,
  p_number_of_siblings text default null,
  p_birth_order text default null,
  p_spouse_name text default null,
  p_spouse_occupation text default null,
  p_spouse_contact text default null,
  p_children_names text default null,
  p_children_count text default null
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
    emergency_contact,
    religion,
    birth_place,
    nationality,
    height,
    weight,
    other_phone,
    social_media_type,
    social_media_detail,
    zip_code,
    permanent_address,
    elementary_school,
    elementary_year,
    secondary_school,
    secondary_year,
    college_school,
    college_year,
    college_course,
    year_graduated,
    father_name,
    father_occupation,
    mother_maiden_name,
    mother_occupation,
    number_of_siblings,
    birth_order,
    spouse_name,
    spouse_occupation,
    spouse_contact,
    children_names,
    children_count
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
    nullif(trim(p_emergency_contact), ''),
    nullif(trim(p_religion), ''),
    nullif(trim(p_birth_place), ''),
    nullif(trim(p_nationality), ''),
    nullif(trim(p_height), ''),
    nullif(trim(p_weight), ''),
    nullif(trim(p_other_phone), ''),
    nullif(trim(p_social_media_type), ''),
    nullif(trim(p_social_media_detail), ''),
    nullif(trim(p_zip_code), ''),
    nullif(trim(p_permanent_address), ''),
    nullif(trim(p_elementary_school), ''),
    nullif(trim(p_elementary_year), ''),
    nullif(trim(p_secondary_school), ''),
    nullif(trim(p_secondary_year), ''),
    nullif(trim(p_college_school), ''),
    nullif(trim(p_college_year), ''),
    nullif(trim(p_college_course), ''),
    nullif(trim(p_year_graduated), ''),
    nullif(trim(p_father_name), ''),
    nullif(trim(p_father_occupation), ''),
    nullif(trim(p_mother_maiden_name), ''),
    nullif(trim(p_mother_occupation), ''),
    nullif(trim(p_number_of_siblings), ''),
    nullif(trim(p_birth_order), ''),
    nullif(trim(p_spouse_name), ''),
    nullif(trim(p_spouse_occupation), ''),
    nullif(trim(p_spouse_contact), ''),
    nullif(trim(p_children_names), ''),
    nullif(trim(p_children_count), '')
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
    religion = excluded.religion,
    birth_place = excluded.birth_place,
    nationality = excluded.nationality,
    height = excluded.height,
    weight = excluded.weight,
    other_phone = excluded.other_phone,
    social_media_type = excluded.social_media_type,
    social_media_detail = excluded.social_media_detail,
    zip_code = excluded.zip_code,
    permanent_address = excluded.permanent_address,
    elementary_school = excluded.elementary_school,
    elementary_year = excluded.elementary_year,
    secondary_school = excluded.secondary_school,
    secondary_year = excluded.secondary_year,
    college_school = excluded.college_school,
    college_year = excluded.college_year,
    college_course = excluded.college_course,
    year_graduated = excluded.year_graduated,
    father_name = excluded.father_name,
    father_occupation = excluded.father_occupation,
    mother_maiden_name = excluded.mother_maiden_name,
    mother_occupation = excluded.mother_occupation,
    number_of_siblings = excluded.number_of_siblings,
    birth_order = excluded.birth_order,
    spouse_name = excluded.spouse_name,
    spouse_occupation = excluded.spouse_occupation,
    spouse_contact = excluded.spouse_contact,
    children_names = excluded.children_names,
    children_count = excluded.children_count,
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
  text,
  text
) to authenticated;
