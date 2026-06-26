create or replace function public.check_employee_profile_duplicate(
  p_last_name text,
  p_first_name text,
  p_middle_name text,
  p_suffix text,
  p_email text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_duplicate_name boolean;
  v_duplicate_email boolean;
  v_email text := nullif(lower(trim(p_email)), '');
begin
  select exists (
    select 1
    from public.employees e
    where lower(trim(e.last_name)) = lower(trim(p_last_name))
      and lower(trim(e.first_name)) = lower(trim(p_first_name))
      and lower(trim(coalesce(e.middle_name, ''))) = lower(trim(coalesce(p_middle_name, '')))
      and lower(trim(coalesce(e.suffix, ''))) = lower(trim(coalesce(p_suffix, '')))
  )
  into v_duplicate_name;

  if v_email is null then
    v_duplicate_email := false;
  else
    select exists (
      select 1
      from public.employees e
      where lower(trim(coalesce(e.email, ''))) = v_email
    )
    into v_duplicate_email;
  end if;

  return jsonb_build_object(
    'duplicate_name', v_duplicate_name,
    'duplicate_email', v_duplicate_email
  );
end;
$$;

grant execute on function public.check_employee_profile_duplicate(
  text,
  text,
  text,
  text,
  text
) to anon, authenticated;

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
  v_duplicate jsonb;
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

  v_duplicate := public.check_employee_profile_duplicate(
    p_last_name,
    p_first_name,
    p_middle_name,
    p_suffix,
    p_email
  );

  if (v_duplicate->>'duplicate_name')::boolean then
    raise exception 'An employee profile with this name already exists.';
  end if;

  if (v_duplicate->>'duplicate_email')::boolean then
    raise exception 'An employee profile with this email address already exists.';
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
  );

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
