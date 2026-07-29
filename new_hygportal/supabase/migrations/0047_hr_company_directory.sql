create or replace function public.hr_company_directory(
  p_username text default null,
  p_password text default null
)
returns table (
  company_id uuid,
  company_name text,
  company_code text,
  contact_number text,
  address text,
  is_active boolean
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
    c.id as company_id,
    c.name as company_name,
    c.code as company_code,
    '-'::text as contact_number,
    '-'::text as address,
    c.is_active
  from public.companies c
  order by c.name;
end;
$$;

grant execute on function public.hr_company_directory(text, text) to anon, authenticated;
