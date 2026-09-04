-- Migration 0170: Bulk load employee store assignments for HR and Photo Proofs

drop function if exists public.hr_employee_store_assignments(text, text);

create or replace function public.hr_employee_store_assignments(
  p_username text default null,
  p_password text default null
)
returns table (
  employee_id uuid,
  employee_name text,
  store_id uuid,
  store_name text,
  department_name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_role text;
  v_user_profile_id uuid;
begin
  select up.app_role, up.id
  into v_user_role, v_user_profile_id
  from public.user_profiles up
  where up.auth_user_id = auth.uid()
    and up.is_active = true;

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
  select distinct on (e.id)
    e.id as employee_id,
    trim(concat_ws(' ',
      nullif(trim(e.first_name), ''),
      case
        when lower(trim(coalesce(e.middle_name, ''))) in ('', 'n/a', 'na') then null
        else upper(left(trim(e.middle_name), 1)) || '.'
      end,
      nullif(trim(e.last_name), ''),
      nullif(trim(e.suffix), '')
    )) as employee_name,
    s.id as store_id,
    s.name as store_name,
    d.name as department_name
  from public.employees e
  join public.employee_assignments ea on ea.employee_id = e.id
  join public.stores s on s.id = ea.store_id
  left join public.departments d on d.id = ea.department_id
  where ea.is_primary = true
    and (ea.effective_to is null or ea.effective_to >= current_date)
    and s.is_active = true
    and (
      v_user_role is null
      or v_user_role <> 'hr'
      or not exists (
        select 1
        from public.hr_company_assignments hca
        where hca.user_profile_id = v_user_profile_id
      )
      or ea.company_id in (
        select hca.company_id
        from public.hr_company_assignments hca
        where hca.user_profile_id = v_user_profile_id
      )
    )
  order by e.id, ea.effective_from desc, ea.created_at desc;
end;
$$;

grant execute on function public.hr_employee_store_assignments(text, text) to anon, authenticated;

notify pgrst, 'reload schema';

