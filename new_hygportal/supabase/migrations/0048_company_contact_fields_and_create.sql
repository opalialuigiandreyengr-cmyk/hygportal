alter table public.companies
add column if not exists contact_number text,
add column if not exists address text,
add column if not exists logo_url text;

drop function if exists public.hr_company_directory(text, text);

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
  logo_url text,
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
    coalesce(nullif(c.contact_number, ''), '-') as contact_number,
    coalesce(nullif(c.address, ''), '-') as address,
    c.logo_url,
    c.is_active
  from public.companies c
  order by c.name;
end;
$$;

grant execute on function public.hr_company_directory(text, text) to anon, authenticated;

create or replace function public.hr_create_company(
  p_username text default null,
  p_password text default null,
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
  v_company_id uuid;
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_code text;
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

  if v_name is null then
    raise exception 'Company name is required.';
  end if;

  if exists (
    select 1
    from public.companies c
    where lower(c.name) = lower(v_name)
  ) then
    raise exception 'Company already exists.';
  end if;

  v_code := upper(regexp_replace(v_name, '[^a-zA-Z0-9]+', '_', 'g'));
  v_code := trim(both '_' from v_code);

  if v_code = '' then
    v_code := 'COMPANY';
  end if;

  insert into public.companies (
    name,
    code,
    contact_number,
    address,
    logo_url,
    is_active
  )
  values (
    v_name,
    v_code,
    nullif(trim(coalesce(p_contact_number, '')), ''),
    nullif(trim(coalesce(p_address, '')), ''),
    nullif(trim(coalesce(p_logo_url, '')), ''),
    true
  )
  returning id into v_company_id;

  return v_company_id;
end;
$$;

grant execute on function public.hr_create_company(text, text, text, text, text, text) to anon, authenticated;
