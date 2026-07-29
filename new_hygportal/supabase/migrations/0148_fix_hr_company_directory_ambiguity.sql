-- Fix column reference "is_active" is ambiguous in hr_company_directory PL/pgSQL function

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
  select
    c.id as company_id,
    c.name as company_name,
    c.code as company_code,
    coalesce(nullif(c.contact_number, ''), '-') as contact_number,
    coalesce(nullif(c.address, ''), '-') as address,
    c.logo_url,
    c.is_active
  from public.companies c
  where (
    v_user_role is null
    or v_user_role <> 'hr'
    or not exists (
      select 1
      from public.hr_company_assignments hca
      where hca.user_profile_id = v_user_profile_id
    )
    or c.id in (
      select hca.company_id
      from public.hr_company_assignments hca
      where hca.user_profile_id = v_user_profile_id
    )
  )
  order by c.name;
end;
$$;

grant execute on function public.hr_company_directory(text, text) to anon, authenticated;

notify pgrst, 'reload schema';
