-- Allow mobile profiles to explicitly choose N/A when no store applies.

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

  return v_employee_id;
end;
$$;

grant execute on function public.create_employee_profile_with_store(
  text, text, text, text, date, text, text, text, text, text, text, text,
  text, date, text, text, text, text, text, text, text, text, text, text, jsonb
) to anon, authenticated;

notify pgrst, 'reload schema';
