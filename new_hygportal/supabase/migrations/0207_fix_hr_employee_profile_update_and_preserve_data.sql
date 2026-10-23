-- Migration 0207: Fix HR employee profile update, prevent data loss/null overwrites, and ensure reliable fetching
-- 1. Protect existing employee details from being overwritten with NULL when saving from the admin portal.
-- 2. Ensure hr_employee_profile_detail safely reads epd.day_off and never crashes if leave credit sync fails.
-- 3. Ensure hr_set_employee_store does not crash the entire update when assignment is being adjusted.
-- 4. Enable full read/write RLS on employee_profile_details for authenticated HR staff.

-- ============================================================================
-- 1. hr_update_employee_profile: Coalesce fields to preserve existing values
-- ============================================================================
drop function if exists public.hr_update_employee_profile(
  text, text, uuid, text, text, text, text, date, text, text, text, text, text, text, text, date, text, text, text, text, text, text, text, text, text, text, text, text
);
drop function if exists public.hr_update_employee_profile(
  text, text, uuid, text, text, text, text, date, text, text, text, text, text, text, text, date, text, text, text, text, text, text, text, text, text, text, text, text, text
);

create or replace function public.hr_update_employee_profile(
  p_username text,
  p_password text,
  p_employee_id uuid,
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
  p_position text,
  p_date_hired date,
  p_employee_type text,
  p_time_schedule text,
  p_day_off_day text,
  p_payroll_class text,
  p_tin text,
  p_sss text,
  p_pagibig text,
  p_philhealth text,
  p_bank_type text,
  p_account_no text,
  p_present_address text,
  p_emergency_contact text,
  p_employment_status text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_function_id uuid;
  v_department_id uuid;
  v_position_id uuid;
  v_assignment_id uuid;
  v_existing_assignment public.employee_assignments%rowtype;
  v_email text := nullif(lower(trim(p_email)), '');
  v_current_employee_no text;
  v_new_employee_no text;
  v_employee_no_prefix text;
  v_status text := nullif(lower(trim(coalesce(p_employment_status, ''))), '');
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

  select e.employee_no
  into v_current_employee_no
  from public.employees e
  where e.id = p_employee_id;

  if nullif(trim(p_last_name), '') is null
    or nullif(trim(p_first_name), '') is null then
    raise exception 'First name and last name are required.';
  end if;

  select * into v_existing_assignment
  from public.employee_assignments
  where employee_id = p_employee_id
    and is_primary = true
  order by
    case
      when effective_to is null or effective_to >= current_date then 0
      else 1
    end,
    effective_from desc,
    created_at desc
  limit 1;

  if nullif(trim(coalesce(p_company, '')), '') is null then
    v_company_id := v_existing_assignment.company_id;
  else
    select id into v_company_id
    from public.companies
    where lower(name) = lower(trim(p_company))
    limit 1;

    if v_company_id is null then
      v_company_id := v_existing_assignment.company_id;
    end if;
  end if;

  if nullif(trim(coalesce(p_work_unit, '')), '') is null then
    v_department_id := v_existing_assignment.department_id;
    v_function_id := v_existing_assignment.function_id;
  else
    select id, function_id
    into v_department_id, v_function_id
    from public.departments
    where lower(name) = lower(trim(p_work_unit))
    limit 1;

    if v_department_id is null then
      v_department_id := v_existing_assignment.department_id;
      v_function_id := v_existing_assignment.function_id;
    elsif v_function_id is null then
      insert into public.functions (name, code)
      values (
        trim(p_work_unit),
        upper(regexp_replace(trim(p_work_unit), '[^a-zA-Z0-9]+', '_', 'g'))
      )
      on conflict (name) do update set name = excluded.name
      returning id into v_function_id;

      update public.departments
      set function_id = v_function_id
      where id = v_department_id;
    end if;
  end if;

  if nullif(trim(coalesce(p_position, '')), '') is null then
    v_position_id := v_existing_assignment.position_id;
  else
    select id into v_position_id
    from public.positions
    where lower(name) = lower(trim(p_position))
    limit 1;

    if v_position_id is null then
      v_position_id := v_existing_assignment.position_id;
    end if;
  end if;

  -- Update employees base record, preserving fields if empty/null
  update public.employees
  set
    first_name = trim(p_first_name),
    middle_name = nullif(trim(p_middle_name), ''),
    last_name = trim(p_last_name),
    suffix = nullif(trim(p_suffix), ''),
    birth_date = coalesce(p_birth_date, birth_date),
    gender = coalesce(nullif(trim(coalesce(p_gender, '')), ''), gender),
    civil_status = coalesce(nullif(trim(coalesce(p_civil_status, '')), ''), civil_status),
    email = coalesce(v_email, email),
    phone = coalesce(nullif(trim(coalesce(p_cellphone, '')), ''), phone),
    employment_status = coalesce(v_status, employment_status),
    updated_at = now()
  where id = p_employee_id;

  if p_date_hired is not null then
    v_employee_no_prefix := to_char(p_date_hired, 'MMDDYYYY') || '-';

    if v_current_employee_no is null or v_current_employee_no !~ ('^' || v_employee_no_prefix || '[0-9]+$') then
      loop
        v_new_employee_no := public.next_employee_no_for_hire_date(p_date_hired);
        begin
          update public.employees
          set employee_no = v_new_employee_no,
              updated_at = now()
          where id = p_employee_id;
          exit;
        exception
          when unique_violation then
            null;
        end;
      end loop;
    end if;
  end if;

  v_assignment_id := v_existing_assignment.id;

  if v_assignment_id is null and v_company_id is not null and v_department_id is not null and v_position_id is not null and v_function_id is not null then
    insert into public.employee_assignments (
      employee_id,
      company_id,
      department_id,
      position_id,
      function_id,
      effective_from,
      is_primary
    )
    values (
      p_employee_id,
      v_company_id,
      v_department_id,
      v_position_id,
      v_function_id,
      coalesce(p_date_hired, current_date),
      true
    );
  elsif v_assignment_id is not null then
    update public.employee_assignments
    set
      company_id = coalesce(v_company_id, company_id),
      department_id = coalesce(v_department_id, department_id),
      position_id = coalesce(v_position_id, position_id),
      function_id = coalesce(v_function_id, function_id),
      effective_from = coalesce(p_date_hired, effective_from),
      effective_to = null,
      is_primary = true
    where id = v_assignment_id;
  end if;

  -- Upsert details safely with COALESCE so missing/null parameters NEVER overwrite completed info
  insert into public.employee_profile_details (
    employee_id,
    employee_type,
    time_schedule,
    day_off,
    payroll_class,
    work_unit_name,
    tin,
    sss,
    pagibig,
    philhealth,
    bank_type,
    account_no,
    present_address,
    emergency_contact,
    updated_at
  )
  values (
    p_employee_id,
    nullif(trim(coalesce(p_employee_type, '')), ''),
    nullif(trim(coalesce(p_time_schedule, '')), ''),
    nullif(trim(coalesce(p_day_off_day, '')), ''),
    nullif(trim(coalesce(p_payroll_class, '')), ''),
    nullif(trim(coalesce(p_work_unit, '')), ''),
    nullif(trim(coalesce(p_tin, '')), ''),
    nullif(trim(coalesce(p_sss, '')), ''),
    nullif(trim(coalesce(p_pagibig, '')), ''),
    nullif(trim(coalesce(p_philhealth, '')), ''),
    nullif(trim(coalesce(p_bank_type, '')), ''),
    nullif(trim(coalesce(p_account_no, '')), ''),
    nullif(trim(coalesce(p_present_address, '')), ''),
    nullif(trim(coalesce(p_emergency_contact, '')), ''),
    now()
  )
  on conflict (employee_id) do update
  set
    employee_type = coalesce(excluded.employee_type, employee_profile_details.employee_type),
    time_schedule = coalesce(excluded.time_schedule, employee_profile_details.time_schedule),
    day_off = coalesce(excluded.day_off, employee_profile_details.day_off),
    payroll_class = coalesce(excluded.payroll_class, employee_profile_details.payroll_class),
    work_unit_name = coalesce(excluded.work_unit_name, employee_profile_details.work_unit_name),
    tin = coalesce(excluded.tin, employee_profile_details.tin),
    sss = coalesce(excluded.sss, employee_profile_details.sss),
    pagibig = coalesce(excluded.pagibig, employee_profile_details.pagibig),
    philhealth = coalesce(excluded.philhealth, employee_profile_details.philhealth),
    bank_type = coalesce(excluded.bank_type, employee_profile_details.bank_type),
    account_no = coalesce(excluded.account_no, employee_profile_details.account_no),
    present_address = coalesce(excluded.present_address, employee_profile_details.present_address),
    emergency_contact = coalesce(excluded.emergency_contact, employee_profile_details.emergency_contact),
    updated_at = now();

  return p_employee_id;
end;
$$;

grant execute on function public.hr_update_employee_profile(
  text, text, uuid, text, text, text, text, date, text, text, text, text, text, text, text, date, text, text, text, text, text, text, text, text, text, text, text, text, text
) to anon, authenticated;


-- ============================================================================
-- 2. hr_update_employee_supplemental_details: Safe merge preserving all data
-- ============================================================================
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
    reason_of_inactivity,
    date_inactive,
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
    nullif(trim(p_profile->>'reasonOfInactivity'), ''),
    nullif(trim(p_profile->>'dateInactive'), ''),
    now()
  )
  on conflict (employee_id) do update
  set
    emergency_contact_no = coalesce(excluded.emergency_contact_no, employee_profile_details.emergency_contact_no),
    zip_code = coalesce(excluded.zip_code, employee_profile_details.zip_code),
    social_media_type = coalesce(excluded.social_media_type, employee_profile_details.social_media_type),
    social_media_detail = coalesce(excluded.social_media_detail, employee_profile_details.social_media_detail),
    permanent_address = coalesce(excluded.permanent_address, employee_profile_details.permanent_address),
    religion = coalesce(excluded.religion, employee_profile_details.religion),
    height = coalesce(excluded.height, employee_profile_details.height),
    weight = coalesce(excluded.weight, employee_profile_details.weight),
    elementary_school = coalesce(excluded.elementary_school, employee_profile_details.elementary_school),
    elementary_year = coalesce(excluded.elementary_year, employee_profile_details.elementary_year),
    secondary_school = coalesce(excluded.secondary_school, employee_profile_details.secondary_school),
    secondary_year = coalesce(excluded.secondary_year, employee_profile_details.secondary_year),
    college_school = coalesce(excluded.college_school, employee_profile_details.college_school),
    college_year = coalesce(excluded.college_year, employee_profile_details.college_year),
    college_course = coalesce(excluded.college_course, employee_profile_details.college_course),
    year_graduated = coalesce(excluded.year_graduated, employee_profile_details.year_graduated),
    father_name = coalesce(excluded.father_name, employee_profile_details.father_name),
    father_occupation = coalesce(excluded.father_occupation, employee_profile_details.father_occupation),
    mother_maiden_name = coalesce(excluded.mother_maiden_name, employee_profile_details.mother_maiden_name),
    mother_occupation = coalesce(excluded.mother_occupation, employee_profile_details.mother_occupation),
    number_of_siblings = coalesce(excluded.number_of_siblings, employee_profile_details.number_of_siblings),
    birth_order = coalesce(excluded.birth_order, employee_profile_details.birth_order),
    spouse_name = coalesce(excluded.spouse_name, employee_profile_details.spouse_name),
    spouse_occupation = coalesce(excluded.spouse_occupation, employee_profile_details.spouse_occupation),
    spouse_contact = coalesce(excluded.spouse_contact, employee_profile_details.spouse_contact),
    children_names = coalesce(excluded.children_names, employee_profile_details.children_names),
    children_count = coalesce(excluded.children_count, employee_profile_details.children_count),
    reason_of_inactivity = coalesce(excluded.reason_of_inactivity, employee_profile_details.reason_of_inactivity),
    date_inactive = coalesce(excluded.date_inactive, employee_profile_details.date_inactive),
    updated_at = now();

  return p_employee_id;
end;
$$;

grant execute on function public.hr_update_employee_supplemental_details(text, text, uuid, jsonb) to anon, authenticated;


-- ============================================================================
-- 3. hr_employee_profile_detail: Safe, robust fetching with no crashes
-- ============================================================================
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
  employment_status text,
  time_schedule text,
  day_off_day text,
  payroll_class text,
  religion text,
  height text,
  weight text,
  other_phone text,
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
  reason_of_inactivity text,
  date_inactive text,
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

  -- Safe background auto-updates: never allow errors here to crash reading the profile
  begin
    update public.employee_profile_details epd_up
    set employee_type = case
          when current_date >= (ea_up.effective_from + interval '6 months') then 'Regular'
          when lower(trim(coalesce(epd_up.employee_type, ''))) = 'trainee'
           and current_date >= (ea_up.effective_from + interval '1 month') then 'Probationary'
          else epd_up.employee_type
        end,
        updated_at = now()
    from (
      select employee_id, min(effective_from) as effective_from
      from public.employee_assignments
      where employee_id = p_employee_id
      group by employee_id
    ) ea_up
    where epd_up.employee_id = ea_up.employee_id
      and (
        (current_date >= (ea_up.effective_from + interval '6 months') and lower(trim(coalesce(epd_up.employee_type, ''))) <> 'regular')
        or
        (lower(trim(coalesce(epd_up.employee_type, ''))) = 'trainee' and current_date >= (ea_up.effective_from + interval '1 month'))
      );
  exception
    when others then null;
  end;

  begin
    if exists (
      select 1 from pg_proc where proname = 'sync_employee_leave_credits'
    ) then
      perform public.sync_employee_leave_credits(p_employee_id, current_date);
    end if;
  exception
    when others then null;
  end;

  return query
  select
    e.id as employee_id,
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
    c.name as company_name,
    d.name as department_name,
    p.name as position_name,
    ea.effective_from as hired_date,
    case
      when lower(trim(coalesce(epd.employee_type, ''))) in ('probationary', 'trainee')
       and ea.effective_from is not null
       and current_date >= (ea.effective_from + interval '6 months')
      then 'Regular'
      when lower(trim(coalesce(epd.employee_type, ''))) = 'trainee'
       and ea.effective_from is not null
       and current_date >= (ea.effective_from + interval '1 month')
      then 'Probationary'
      else coalesce(epd.employee_type, 'Regular')
    end as employee_type,
    e.employment_status,
    epd.time_schedule,
    epd.day_off as day_off_day,
    epd.payroll_class,
    epd.religion,
    epd.height,
    epd.weight,
    epd.other_phone,
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
    epd.reason_of_inactivity,
    epd.date_inactive,
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
      case
        when current_ea.effective_to is null or current_ea.effective_to >= current_date then 0
        else 1
      end,
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


-- ============================================================================
-- 4. hr_set_employee_store: Non-fatal assignment updates
-- ============================================================================
create or replace function public.hr_set_employee_store(
  p_username text default null,
  p_password text default null,
  p_employee_id uuid default null,
  p_company_name text default null,
  p_store_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
  v_store_name text := nullif(trim(coalesce(p_store_name, '')), '');
  v_target_ea_id uuid;
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

  if v_store_name is not null and lower(v_store_name) <> 'n/a' then
    select s.id into v_store_id
    from public.stores s
    join public.companies c on c.id = s.company_id
    where lower(s.name) = lower(v_store_name)
      and lower(c.name) = lower(trim(coalesce(p_company_name, '')))
      and s.is_active = true
    limit 1;
  end if;

  select ea.id into v_target_ea_id
  from public.employee_assignments ea
  where ea.employee_id = p_employee_id
    and ea.is_primary = true
  order by
    case when ea.effective_to is null or ea.effective_to >= current_date then 0 else 1 end,
    ea.effective_from desc,
    ea.created_at desc
  limit 1;

  if v_target_ea_id is not null then
    update public.employee_assignments
    set store_id = v_store_id
    where id = v_target_ea_id;
  end if;

  return p_employee_id;
end;
$$;

grant execute on function public.hr_set_employee_store(text, text, uuid, text, text) to anon, authenticated;


-- ============================================================================
-- 5. RLS Policies: Ensure authenticated HR staff have full access
-- ============================================================================
drop policy if exists "HR can insert or update employee profile details" on public.employee_profile_details;

create policy "HR can insert or update employee profile details"
on public.employee_profile_details for all
to authenticated
using (public.is_hr_staff())
with check (public.is_hr_staff());

notify pgrst, 'reload schema';
