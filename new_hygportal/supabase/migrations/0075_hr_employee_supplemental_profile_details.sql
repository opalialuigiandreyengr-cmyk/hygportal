-- Expose and preserve the extended employee profile fields used by the HR editor.

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

notify pgrst, 'reload schema';
