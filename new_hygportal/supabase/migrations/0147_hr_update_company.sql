create or replace function public.hr_update_company(
  p_username text default null,
  p_password text default null,
  p_company_id uuid default null,
  p_name text default null,
  p_contact_number text default null,
  p_address text default null,
  p_logo_url text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := nullif(trim(coalesce(p_name, '')), '');
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
    raise exception 'Company ID is required.';
  end if;

  if v_name is null then
    raise exception 'Company name is required.';
  end if;

  if exists (select 1 from public.companies where lower(name) = lower(v_name) and id <> p_company_id) then
    raise exception 'A company with this name already exists.';
  end if;

  update public.companies
  set
    name = v_name,
    contact_number = nullif(trim(coalesce(p_contact_number, '')), ''),
    address = nullif(trim(coalesce(p_address, '')), ''),
    logo_url = nullif(trim(coalesce(p_logo_url, '')), ''),
    updated_at = now()
  where id = p_company_id;

  return p_company_id;
end;
$$;

grant execute on function public.hr_update_company(text, text, uuid, text, text, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
