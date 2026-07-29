create table if not exists public.employee_profile_details (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null unique references public.employees(id) on delete cascade,
  employee_type text,
  work_unit_name text,
  tin text,
  sss text,
  pagibig text,
  philhealth text,
  bank_type text,
  account_no text,
  education text,
  present_address text,
  emergency_contact text,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.employee_profile_details enable row level security;

drop policy if exists "Users can read own employee profile details" on public.employee_profile_details;

create policy "Users can read own employee profile details"
on public.employee_profile_details for select
to authenticated
using (
  exists (
    select 1
    from public.user_profiles up
    where up.auth_user_id = auth.uid()
      and up.employee_id = employee_profile_details.employee_id
  )
);

create or replace function public.position_level_for_profile(p_position text)
returns int
language plpgsql
immutable
as $$
begin
  return case lower(trim(coalesce(p_position, '')))
    when 'crew' then 1
    when 'staff' then 1
    when 'assistant' then 1
    when 'officer' then 2
    when 'specialist' then 2
    when 'analyst' then 2
    when 'coordinator' then 2
    when 'team leader' then 2
    when 'supervisor' then 2
    when 'store manager' then 3
    when 'department manager' then 3
    when 'cluster manager' then 4
    when 'area manager' then 5
    when 'operations manager' then 5
    when 'director' then 7
    when 'operations director' then 7
    when 'finance director' then 7
    when 'general manager' then 8
    else 1
  end;
end;
$$;

create or replace function public.create_employee_profile(
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
  v_employee_id uuid;
  v_company_id uuid;
  v_function_id uuid;
  v_department_id uuid;
  v_position_id uuid;
  v_authority_level int;
  v_email text := nullif(lower(trim(p_email)), '');
begin
  if nullif(trim(p_last_name), '') is null
    or nullif(trim(p_first_name), '') is null
    or nullif(trim(p_cellphone), '') is null
    or nullif(trim(p_company), '') is null
    or nullif(trim(p_work_unit), '') is null
    or nullif(trim(p_position), '') is null
    or p_date_hired is null then
    raise exception 'Please complete all required employee profile fields.';
  end if;

  select id into v_company_id
  from public.companies
  where lower(name) = lower(trim(p_company))
  limit 1;

  if v_company_id is null then
    insert into public.companies (name, code)
    values (trim(p_company), upper(regexp_replace(trim(p_company), '[^a-zA-Z0-9]+', '_', 'g')))
    returning id into v_company_id;
  end if;

  select id into v_function_id
  from public.functions
  where lower(name) = lower(trim(p_work_unit))
  limit 1;

  if v_function_id is null then
    insert into public.functions (name, code)
    values (trim(p_work_unit), upper(regexp_replace(trim(p_work_unit), '[^a-zA-Z0-9]+', '_', 'g')))
    returning id into v_function_id;
  end if;

  select id into v_department_id
  from public.departments
  where lower(name) = lower(trim(p_work_unit))
  limit 1;

  if v_department_id is null then
    insert into public.departments (name, function_id)
    values (trim(p_work_unit), v_function_id)
    returning id into v_department_id;
  end if;

  v_authority_level := public.position_level_for_profile(p_position);

  select id into v_position_id
  from public.positions
  where lower(name) = lower(trim(p_position))
  limit 1;

  if v_position_id is null then
    insert into public.positions (name, authority_level, default_function_id)
    values (trim(p_position), v_authority_level, v_function_id)
    returning id into v_position_id;
  end if;

  if v_email is not null then
    select id into v_employee_id
    from public.employees
    where lower(email) = v_email
    limit 1;
  end if;

  if v_employee_id is null then
    insert into public.employees (
      first_name,
      middle_name,
      last_name,
      suffix,
      birth_date,
      gender,
      civil_status,
      email,
      phone,
      employment_status
    )
    values (
      trim(p_first_name),
      nullif(trim(p_middle_name), ''),
      trim(p_last_name),
      nullif(trim(p_suffix), ''),
      p_birth_date,
      nullif(trim(p_gender), ''),
      nullif(trim(p_civil_status), ''),
      v_email,
      trim(p_cellphone),
      'active'
    )
    returning id into v_employee_id;
  else
    update public.employees
    set
      first_name = trim(p_first_name),
      middle_name = nullif(trim(p_middle_name), ''),
      last_name = trim(p_last_name),
      suffix = nullif(trim(p_suffix), ''),
      birth_date = p_birth_date,
      gender = nullif(trim(p_gender), ''),
      civil_status = nullif(trim(p_civil_status), ''),
      phone = trim(p_cellphone),
      employment_status = 'active',
      updated_at = now()
    where id = v_employee_id;
  end if;

  update public.employee_assignments
  set effective_to = p_date_hired
  where employee_id = v_employee_id
    and is_primary = true
    and effective_to is null;

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
    v_employee_id,
    v_company_id,
    v_department_id,
    v_position_id,
    v_function_id,
    p_date_hired,
    true
  );

  insert into public.employee_profile_details (
    employee_id,
    employee_type,
    work_unit_name,
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
    v_employee_id,
    nullif(trim(p_employee_type), ''),
    trim(p_work_unit),
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
    work_unit_name = excluded.work_unit_name,
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

  return v_employee_id;
end;
$$;

grant execute on function public.create_employee_profile(
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
  text
) to anon, authenticated;
