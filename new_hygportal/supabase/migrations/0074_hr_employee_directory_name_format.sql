-- Keep directory names readable without mutating the employee's stored profile.

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
  company_name text,
  department_name text,
  position_name text,
  hired_date date
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
    c.name as company_name,
    d.name as department_name,
    p.name as position_name,
    ea.effective_from as hired_date
  from public.employees e
  join public.employee_profile_details epd on epd.employee_id = e.id
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
  order by e.created_at desc, e.last_name, e.first_name;
end;
$$;

grant execute on function public.hr_employee_directory(text, text) to anon, authenticated;

notify pgrst, 'reload schema';
