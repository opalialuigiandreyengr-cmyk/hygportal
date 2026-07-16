drop function if exists public.hr_update_employee_profile(
  text,
  text,
  uuid,
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
  date,
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

alter table public.employee_profile_details
  add column if not exists payroll_class text;

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
  p_payroll_class text,
  p_tin text,
  p_sss text,
  p_pagibig text,
  p_philhealth text,
  p_bank_type text,
  p_account_no text,
  p_present_address text,
  p_emergency_contact text
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
      raise exception 'Selected company was not found.';
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
      raise exception 'Selected department was not found.';
    end if;

    if v_function_id is null then
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
      raise exception 'Selected position was not found.';
    end if;
  end if;

  update public.employees
  set
    first_name = trim(p_first_name),
    middle_name = nullif(trim(p_middle_name), ''),
    last_name = trim(p_last_name),
    suffix = nullif(trim(p_suffix), ''),
    birth_date = p_birth_date,
    gender = nullif(trim(coalesce(p_gender, '')), ''),
    civil_status = nullif(trim(coalesce(p_civil_status, '')), ''),
    email = v_email,
    phone = coalesce(nullif(trim(coalesce(p_cellphone, '')), ''), phone),
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
            -- Retry until a free sequence slot is generated.
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

  insert into public.employee_profile_details (
    employee_id,
    employee_type,
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
    employee_type = excluded.employee_type,
    payroll_class = excluded.payroll_class,
    work_unit_name = coalesce(excluded.work_unit_name, employee_profile_details.work_unit_name),
    tin = excluded.tin,
    sss = excluded.sss,
    pagibig = excluded.pagibig,
    philhealth = excluded.philhealth,
    bank_type = excluded.bank_type,
    account_no = excluded.account_no,
    present_address = excluded.present_address,
    emergency_contact = excluded.emergency_contact,
    updated_at = now();

  return p_employee_id;
end;
$$;

grant execute on function public.hr_update_employee_profile(
  text,
  text,
  uuid,
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

notify pgrst, 'reload schema';
