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
