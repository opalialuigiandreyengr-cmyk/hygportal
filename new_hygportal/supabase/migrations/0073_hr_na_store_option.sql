-- HR desktop can explicitly clear an employee store by choosing N/A.

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

    if v_store_id is null then
      raise exception 'Selected store was not found for this company.';
    end if;
  end if;

  update public.employee_assignments
  set store_id = v_store_id
  where id = (
    select ea.id
    from public.employee_assignments ea
    where ea.employee_id = p_employee_id
      and ea.is_primary = true
    order by
      case when ea.effective_to is null or ea.effective_to >= current_date then 0 else 1 end,
      ea.effective_from desc,
      ea.created_at desc
    limit 1
  );

  if not found then
    raise exception 'Employee primary assignment was not found.';
  end if;

  return p_employee_id;
end;
$$;

grant execute on function public.hr_set_employee_store(text, text, uuid, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
