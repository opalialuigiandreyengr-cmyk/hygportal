-- Migration 0193: Fix hr_employee_profile_detail day_off column reference
-- Migration 0192 accidentally queried epd.day_off_day which does not exist in employee_profile_details (actual column is day_off).
-- This caused hr_employee_profile_detail RPC to fail and fall back to stale cached profile data in the desktop admin portal.

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

  -- Auto-update employee_profile_details if reached 6 months (Regular) or 1 month (Probationary)
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

  -- Synchronize leave credits for this employee if function exists
  if exists (
    select 1 from pg_proc where proname = 'sync_employee_leave_credits'
  ) then
    perform public.sync_employee_leave_credits(p_employee_id, current_date);
  end if;

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
    epd.employee_type,
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
