-- Migration 0149: Fix company CRUD operations (Add, Edit, Delete)

-- 1. Ensure updated_at column exists on public.companies
alter table public.companies add column if not exists updated_at timestamptz default now();

-- 2. Create or replace public.hr_create_company
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
  v_base_code text;
  v_code text;
  v_counter integer := 1;
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
    raise exception 'A company with this name already exists.';
  end if;

  v_base_code := upper(regexp_replace(v_name, '[^a-zA-Z0-9]+', '_', 'g'));
  v_base_code := trim(both '_' from v_base_code);

  if v_base_code = '' then
    v_base_code := 'COMPANY';
  end if;

  v_code := v_base_code;

  while exists (select 1 from public.companies where lower(code) = lower(v_code)) loop
    v_code := v_base_code || '_' || v_counter;
    v_counter := v_counter + 1;
  end loop;

  insert into public.companies (
    name,
    code,
    contact_number,
    address,
    logo_url,
    is_active,
    created_at,
    updated_at
  )
  values (
    v_name,
    v_code,
    nullif(trim(coalesce(p_contact_number, '')), ''),
    nullif(trim(coalesce(p_address, '')), ''),
    nullif(trim(coalesce(p_logo_url, '')), ''),
    true,
    now(),
    now()
  )
  returning id into v_company_id;

  return v_company_id;
end;
$$;

grant execute on function public.hr_create_company(text, text, text, text, text, text) to anon, authenticated;

-- 3. Create or replace public.hr_update_company
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

  if exists (
    select 1
    from public.companies
    where lower(name) = lower(v_name)
      and id <> p_company_id
  ) then
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

-- 4. Create or replace public.hr_delete_company
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

  -- Clean up HR user company assignment tags if present
  delete from public.hr_company_assignments
  where company_id = p_company_id;

  -- Attempt hard delete if no critical references exist
  if not exists (
    select 1 from public.employee_assignments where company_id = p_company_id
  ) and not exists (
    select 1 from public.requests where company_id = p_company_id
  ) and not exists (
    select 1 from public.authority_assignments where company_id = p_company_id
  ) and not exists (
    select 1 from public.stores where company_id = p_company_id
  ) and not exists (
    select 1 from public.clusters where company_id = p_company_id
  ) and not exists (
    select 1 from public.areas where company_id = p_company_id
  ) then
    delete from public.companies where id = p_company_id;
  else
    -- Fallback to soft delete / deactivate if company is in use
    update public.companies
    set is_active = false, updated_at = now()
    where id = p_company_id;
  end if;

  return p_company_id;
end;
$$;

grant execute on function public.hr_delete_company(text, text, uuid) to anon, authenticated;

notify pgrst, 'reload schema';
