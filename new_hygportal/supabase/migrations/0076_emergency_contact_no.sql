-- Store emergency contact name and phone number separately.

alter table if exists public.employee_profile_details
add column if not exists emergency_contact_no text;

create or replace function public.hr_update_employee_supplemental_details(
  p_username text default null,
  p_password text default null,
  p_employee_id uuid default null,
  p_profile jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (
    public.is_hr_staff()
    or (
      lower(trim(coalesce(p_username, ''))) = 'hyg_hr'
      and coalesce(p_password, '') = 'hyg_hr2026'
    )
  ) then
    raise exception 'HR access is required.';
  end if;

  if p_employee_id is null then
    raise exception 'Employee id is required.';
  end if;

  if not exists (select 1 from public.employees where id = p_employee_id) then
    raise exception 'Employee profile was not found.';
  end if;

  insert into public.employee_profile_details (
    employee_id,
    emergency_contact_no,
    zip_code,
    social_media_type,
    social_media_detail,
    permanent_address,
    religion,
    height,
    weight,
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
    children_count,
    updated_at
  )
  values (
    p_employee_id,
    nullif(trim(p_profile->>'emergencyContactNo'), ''),
    nullif(trim(p_profile->>'zipCode'), ''),
    nullif(trim(p_profile->>'socialMediaType'), ''),
    nullif(trim(p_profile->>'socialMediaDetail'), ''),
    nullif(trim(p_profile->>'permanentAddress'), ''),
    nullif(trim(p_profile->>'religion'), ''),
    nullif(trim(p_profile->>'height'), ''),
    nullif(trim(p_profile->>'weight'), ''),
    nullif(trim(p_profile->>'elementarySchool'), ''),
    nullif(trim(p_profile->>'elementaryYear'), ''),
    nullif(trim(p_profile->>'secondarySchool'), ''),
    nullif(trim(p_profile->>'secondaryYear'), ''),
    nullif(trim(p_profile->>'collegeSchool'), ''),
    nullif(trim(p_profile->>'collegeYear'), ''),
    nullif(trim(p_profile->>'collegeCourse'), ''),
    nullif(trim(p_profile->>'yearGraduated'), ''),
    nullif(trim(p_profile->>'fatherName'), ''),
    nullif(trim(p_profile->>'fatherOccupation'), ''),
    nullif(trim(p_profile->>'motherMaidenName'), ''),
    nullif(trim(p_profile->>'motherOccupation'), ''),
    nullif(trim(p_profile->>'numberOfSiblings'), ''),
    nullif(trim(p_profile->>'birthOrder'), ''),
    nullif(trim(p_profile->>'spouseName'), ''),
    nullif(trim(p_profile->>'spouseOccupation'), ''),
    nullif(trim(p_profile->>'spouseContact'), ''),
    nullif(trim(p_profile->>'childrenNames'), ''),
    nullif(trim(p_profile->>'childrenCount'), ''),
    now()
  )
  on conflict (employee_id) do update
  set
    emergency_contact_no = excluded.emergency_contact_no,
    zip_code = excluded.zip_code,
    social_media_type = excluded.social_media_type,
    social_media_detail = excluded.social_media_detail,
    permanent_address = excluded.permanent_address,
    religion = excluded.religion,
    height = excluded.height,
    weight = excluded.weight,
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

  return p_employee_id;
end;
$$;

grant execute on function public.hr_update_employee_supplemental_details(text, text, uuid, jsonb) to anon, authenticated;

drop function if exists public.hr_employee_profile_detail(text, text, uuid);

create or replace function public.hr_employee_profile_detail(
  p_username text default null,
  p_password text default null,
  p_employee_id uuid default null
)
returns table (
  employee_id uuid,
  employee_no text,
  first_name text,
  middle_name text,
  last_name text,
  suffix text,
  birth_date date,
  gender text,
  civil_status text,
  email text,
  phone text,
  company_name text,
  department_name text,
  position_name text,
  hired_date date,
  employee_type text,
  time_schedule text,
  day_off_day text,
  payroll_class text,
  religion text,
  height text,
  weight text,
  social_media_type text,
  social_media_detail text,
  zip_code text,
  present_address text,
  permanent_address text,
  tin text,
  sss text,
  pagibig text,
  philhealth text,
  bank_type text,
  account_no text,
  emergency_contact text,
  emergency_contact_no text,
  elementary_school text,
  elementary_year text,
  secondary_school text,
  secondary_year text,
  college_school text,
  college_year text,
  college_course text,
  year_graduated text,
  father_name text,
  father_occupation text,
  mother_maiden_name text,
  mother_occupation text,
  number_of_siblings text,
  birth_order text,
  spouse_name text,
  spouse_occupation text,
  spouse_contact text,
  children_names text,
  children_count text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (
    public.is_hr_staff()
    or (
      lower(trim(coalesce(p_username, ''))) = 'hyg_hr'
      and coalesce(p_password, '') = 'hyg_hr2026'
    )
  ) then
    raise exception 'HR access is required.';
  end if;

  if p_employee_id is null then
    raise exception 'Employee id is required.';
  end if;

  return query
  select
    e.id,
    e.employee_no,
    e.first_name,
    e.middle_name,
    e.last_name,
    e.suffix,
    e.birth_date,
    e.gender,
    e.civil_status,
    e.email,
    e.phone,
    c.name,
    d.name,
    p.name,
    ea.effective_from,
    epd.employee_type,
    epd.time_schedule,
    epd.day_off,
    epd.payroll_class,
    epd.religion,
    epd.height,
    epd.weight,
    epd.social_media_type,
    epd.social_media_detail,
    epd.zip_code,
    epd.present_address,
    epd.permanent_address,
    epd.tin,
    epd.sss,
    epd.pagibig,
    epd.philhealth,
    epd.bank_type,
    epd.account_no,
    epd.emergency_contact,
    epd.emergency_contact_no,
    epd.elementary_school,
    epd.elementary_year,
    epd.secondary_school,
    epd.secondary_year,
    epd.college_school,
    epd.college_year,
    epd.college_course,
    epd.year_graduated,
    epd.father_name,
    epd.father_occupation,
    epd.mother_maiden_name,
    epd.mother_occupation,
    epd.number_of_siblings,
    epd.birth_order,
    epd.spouse_name,
    epd.spouse_occupation,
    epd.spouse_contact,
    epd.children_names,
    epd.children_count
  from public.employees e
  left join public.employee_profile_details epd on epd.employee_id = e.id
  left join lateral (
    select *
    from public.employee_assignments current_ea
    where current_ea.employee_id = e.id
      and current_ea.is_primary = true
    order by
      case when current_ea.effective_to is null or current_ea.effective_to >= current_date then 0 else 1 end,
      current_ea.effective_from desc,
      current_ea.created_at desc
    limit 1
  ) ea on true
  left join public.companies c on c.id = ea.company_id
  left join public.departments d on d.id = ea.department_id
  left join public.positions p on p.id = ea.position_id
  where e.id = p_employee_id
  limit 1;
end;
$$;

grant execute on function public.hr_employee_profile_detail(text, text, uuid) to anon, authenticated;

drop function if exists public.create_employee_profile_with_store(
  text, text, text, text, date, text, text, text, text, text, text, text,
  text, date, text, text, text, text, text, text, text, text, text, text, jsonb
);

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
  p_document_refs jsonb default null,
  p_emergency_contact_no text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee_id uuid;
  v_store_id uuid;
  v_store_name text := nullif(trim(coalesce(p_store, '')), '');
begin
  if v_store_name is null then
    raise exception 'Please select a store or N/A.';
  end if;

  if lower(v_store_name) <> 'n/a' then
    select s.id into v_store_id
    from public.stores s
    join public.companies c on c.id = s.company_id
    where lower(s.name) = lower(v_store_name)
      and lower(c.name) = lower(trim(p_company))
      and s.is_active = true
      and c.is_active = true
    limit 1;

    if v_store_id is null then
      raise exception 'Selected store was not found for this company.';
    end if;
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

  update public.employee_profile_details
  set emergency_contact_no = nullif(trim(coalesce(p_emergency_contact_no, '')), ''),
      updated_at = now()
  where employee_id = v_employee_id;

  return v_employee_id;
end;
$$;

grant execute on function public.create_employee_profile_with_store(
  text, text, text, text, date, text, text, text, text, text, text, text,
  text, date, text, text, text, text, text, text, text, text, text, text, jsonb, text
) to anon, authenticated;

create or replace function public.update_own_employee_profile_v2(p_profile jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_username text := nullif(lower(trim(p_profile->>'username')), '');
  v_email text := nullif(lower(trim(p_profile->>'email')), '');
  v_birth_date date := nullif(trim(p_profile->>'birthDate'), '')::date;
  v_company_name text := nullif(trim(p_profile->>'company'), '');
  v_company_id uuid;
  v_assignment_updates int := 0;
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

  if nullif(trim(p_profile->>'firstName'), '') is null
    or nullif(trim(p_profile->>'lastName'), '') is null
    or nullif(trim(p_profile->>'cellphone'), '') is null then
    raise exception 'First name, last name, and cellphone number are required.';
  end if;

  if v_company_name is not null then
    select id
    into v_company_id
    from public.companies
    where lower(name) = lower(v_company_name)
    limit 1;

    if v_company_id is null then
      insert into public.companies (name, code, is_active)
      values (
        v_company_name,
        upper(regexp_replace(v_company_name, '[^a-zA-Z0-9]+', '_', 'g')),
        true
      )
      on conflict (code) do update
      set
        name = excluded.name,
        is_active = true
      returning id into v_company_id;
    elsif exists (
      select 1
      from public.companies
      where id = v_company_id
        and is_active = false
    ) then
      update public.companies
      set is_active = true
      where id = v_company_id;
    end if;
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
    first_name = trim(p_profile->>'firstName'),
    middle_name = nullif(trim(p_profile->>'middleName'), ''),
    last_name = trim(p_profile->>'lastName'),
    suffix = nullif(trim(p_profile->>'suffix'), ''),
    birth_date = v_birth_date,
    gender = nullif(trim(p_profile->>'gender'), ''),
    civil_status = nullif(trim(p_profile->>'civilStatus'), ''),
    email = v_email,
    phone = trim(p_profile->>'cellphone'),
    updated_at = now()
  where id = v_profile.employee_id;

  if v_company_id is not null then
    update public.employee_assignments
    set company_id = v_company_id
    where employee_id = v_profile.employee_id
      and is_primary = true
      and effective_from <= current_date
      and (effective_to is null or effective_to >= current_date);

    get diagnostics v_assignment_updates = row_count;

    if v_assignment_updates = 0 then
      raise exception 'No active employee assignment found for company update.';
    end if;
  end if;

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
    emergency_contact_no,
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
    nullif(trim(p_profile->>'employeeType'), ''),
    nullif(trim(p_profile->>'tin'), ''),
    nullif(trim(p_profile->>'sss'), ''),
    nullif(trim(p_profile->>'pagibig'), ''),
    nullif(trim(p_profile->>'philhealth'), ''),
    nullif(trim(p_profile->>'bankType'), ''),
    nullif(trim(p_profile->>'accountNo'), ''),
    nullif(trim(p_profile->>'education'), ''),
    nullif(trim(p_profile->>'presentAddress'), ''),
    nullif(trim(p_profile->>'emergencyContact'), ''),
    nullif(trim(p_profile->>'emergencyContactNo'), ''),
    nullif(trim(p_profile->>'religion'), ''),
    nullif(trim(p_profile->>'birthPlace'), ''),
    nullif(trim(p_profile->>'nationality'), ''),
    nullif(trim(p_profile->>'height'), ''),
    nullif(trim(p_profile->>'weight'), ''),
    nullif(trim(p_profile->>'otherPhone'), ''),
    nullif(trim(p_profile->>'socialMediaType'), ''),
    nullif(trim(p_profile->>'socialMediaDetail'), ''),
    nullif(trim(p_profile->>'zipCode'), ''),
    nullif(trim(p_profile->>'permanentAddress'), ''),
    nullif(trim(p_profile->>'elementarySchool'), ''),
    nullif(trim(p_profile->>'elementaryYear'), ''),
    nullif(trim(p_profile->>'secondarySchool'), ''),
    nullif(trim(p_profile->>'secondaryYear'), ''),
    nullif(trim(p_profile->>'collegeSchool'), ''),
    nullif(trim(p_profile->>'collegeYear'), ''),
    nullif(trim(p_profile->>'collegeCourse'), ''),
    nullif(trim(p_profile->>'yearGraduated'), ''),
    nullif(trim(p_profile->>'fatherName'), ''),
    nullif(trim(p_profile->>'fatherOccupation'), ''),
    nullif(trim(p_profile->>'motherMaidenName'), ''),
    nullif(trim(p_profile->>'motherOccupation'), ''),
    nullif(trim(p_profile->>'numberOfSiblings'), ''),
    nullif(trim(p_profile->>'birthOrder'), ''),
    nullif(trim(p_profile->>'spouseName'), ''),
    nullif(trim(p_profile->>'spouseOccupation'), ''),
    nullif(trim(p_profile->>'spouseContact'), ''),
    nullif(trim(p_profile->>'childrenNames'), ''),
    nullif(trim(p_profile->>'childrenCount'), '')
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
    emergency_contact_no = excluded.emergency_contact_no,
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

grant execute on function public.update_own_employee_profile_v2(jsonb) to authenticated;

notify pgrst, 'reload schema';
