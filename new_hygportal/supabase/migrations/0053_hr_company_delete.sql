create or replace function public.hr_delete_company(
  p_username text default null,
  p_password text default null,
  p_company_id uuid default null
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

  if p_company_id is null then
    raise exception 'Company id is required.';
  end if;

  if not exists (
    select 1
    from public.companies c
    where c.id = p_company_id
  ) then
    raise exception 'Company was not found.';
  end if;

  if exists (
    select 1
    from public.employee_assignments ea
    where ea.company_id = p_company_id
  ) then
    raise exception 'Company has employee references and cannot be deleted.';
  end if;

  if exists (
    select 1
    from public.requests r
    where r.company_id = p_company_id
  ) then
    raise exception 'Company has request references and cannot be deleted.';
  end if;

  if exists (
    select 1
    from public.authority_assignments aa
    where aa.company_id = p_company_id
  ) then
    raise exception 'Company has authority assignment references and cannot be deleted.';
  end if;

  if exists (
    select 1
    from public.stores s
    where s.company_id = p_company_id
  ) then
    raise exception 'Company has store references and cannot be deleted.';
  end if;

  if exists (
    select 1
    from public.clusters cl
    where cl.company_id = p_company_id
  ) then
    raise exception 'Company has cluster references and cannot be deleted.';
  end if;

  if exists (
    select 1
    from public.areas a
    where a.company_id = p_company_id
  ) then
    raise exception 'Company has area references and cannot be deleted.';
  end if;

  delete from public.companies
  where id = p_company_id;

  return p_company_id;
end;
$$;

grant execute on function public.hr_delete_company(text, text, uuid) to anon, authenticated;

notify pgrst, 'reload schema';
