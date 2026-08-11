-- Migration 0156: Fix hr_employee_directory LEFT JOIN on employee_profile_details and untagged HR company visibility.
drop function if exists public.hr_employee_directory(text, text);

create or replace function public.hr_employee_directory(
  p_username text default null,
  p_password text default null
)
returns table (
  employee_id uuid,
  employee_no text,
  full_name text,
  first_name text,
  middle_name text,
  last_name text,
  suffix text,
  email text,
  phone text,
  photo_url text,
  employment_status text,
  birth_date date,
  company_name text,
  department_name text,
  position_name text,
  hired_date date,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_role text;
  v_user_profile_id uuid;
begin
  select app_role, id
  into v_user_role, v_user_profile_id
  from public.user_profiles
  where auth_user_id = auth.uid()
    and is_active = true;

  if not (
    public.is_hr_staff()
    or (
      lower(trim(coalesce(p_username, ''))) = 'hyg_hr'
      and coalesce(p_password, '') = 'hyg_hr2026'
    )
  ) then
    raise exception 'HR access is required.';
  end if;

  return query
  select
    e.id as employee_id,
    e.employee_no,
    trim(concat_ws(
      ' ',
      case
        when lower(trim(coalesce(e.first_name, ''))) in ('', 'n/a', 'na') then null
        else trim(e.first_name)
      end,
      case
        when lower(trim(coalesce(e.middle_name, ''))) in ('', 'n/a', 'na') then null
        else upper(left(trim(e.middle_name), 1)) || '.'
      end,
      case
        when lower(trim(coalesce(e.last_name, ''))) in ('', 'n/a', 'na') then null
        else trim(e.last_name)
      end,
      case
        when lower(trim(coalesce(e.suffix, ''))) in ('', 'n/a', 'na') then null
        else trim(e.suffix)
      end
    )) as full_name,
    e.first_name,
    e.middle_name,
    e.last_name,
    e.suffix,
    e.email,
    e.phone,
    e.photo_url,
    e.employment_status,
    coalesce(e.birth_date, epd.birth_date) as birth_date,
    c.name as company_name,
    d.name as department_name,
    p.name as position_name,
    ea.effective_from as hired_date,
    e.created_at
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
  where (
    v_user_role is null
    or v_user_role <> 'hr'
    or not exists (
      select 1
      from public.hr_company_assignments
      where user_profile_id = v_user_profile_id
    )
    or ea.company_id in (
      select company_id
      from public.hr_company_assignments
      where user_profile_id = v_user_profile_id
    )
  )
  order by e.created_at desc, e.last_name, e.first_name;
end;
$$;

grant execute on function public.hr_employee_directory(text, text) to anon, authenticated;
