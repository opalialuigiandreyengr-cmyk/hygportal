-- Migration 0151: Filter stores, clusters, and areas by HR tagged companies

-- 1. Update hr_store_directory to filter by company if HR role
drop function if exists public.hr_store_directory(text, text);

create or replace function public.hr_store_directory(
  p_username text default null,
  p_password text default null
)
returns table (
  store_id uuid,
  store_name text,
  company_id uuid,
  company_name text,
  cluster_id uuid,
  cluster_name text,
  employee_count bigint,
  created_at timestamptz,
  updated_at timestamptz,
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
    s.id as store_id,
    s.name as store_name,
    s.company_id,
    c.name as company_name,
    cl.id as cluster_id,
    cl.name as cluster_name,
    count(distinct ea.employee_id) filter (
      where ea.is_primary = true
        and ea.effective_to is null
    ),
    s.created_at,
    s.created_at,
    s.is_active
  from public.stores s
  join public.companies c on c.id = s.company_id
  left join public.clusters cl on cl.id = s.cluster_id
  left join public.employee_assignments ea on ea.store_id = s.id
  where s.is_active = true
    and (
      v_user_role is null
      or v_user_role <> 'hr'
      or not exists (
        select 1
        from public.hr_company_assignments hca
        where hca.user_profile_id = v_user_profile_id
      )
      or s.company_id in (
        select hca.company_id
        from public.hr_company_assignments hca
        where hca.user_profile_id = v_user_profile_id
      )
    )
  group by s.id, s.name, s.company_id, c.name, cl.id, cl.name, s.created_at, s.is_active
  order by c.name, coalesce(cl.name, ''), s.name;
end;
$$;

grant execute on function public.hr_store_directory(text, text) to anon, authenticated;

-- 2. Update hr_cluster_directory to filter by company if HR role
drop function if exists public.hr_cluster_directory(text, text);

create or replace function public.hr_cluster_directory(
  p_username text default null,
  p_password text default null
)
returns table (
  cluster_id uuid,
  cluster_name text,
  company_id uuid,
  company_name text,
  store_count bigint,
  store_names text,
  created_at timestamptz,
  updated_at timestamptz,
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
    cl.id as cluster_id,
    cl.name as cluster_name,
    c.id as company_id,
    c.name as company_name,
    count(s.id) filter (where s.is_active = true),
    coalesce(
      string_agg(s.name, ', ' order by s.name) filter (where s.is_active = true),
      ''
    ),
    cl.created_at,
    cl.created_at,
    cl.is_active
  from public.clusters cl
  join public.companies c on c.id = cl.company_id
  left join public.stores s on s.cluster_id = cl.id
  where cl.is_active = true
    and (
      v_user_role is null
      or v_user_role <> 'hr'
      or not exists (
        select 1
        from public.hr_company_assignments hca
        where hca.user_profile_id = v_user_profile_id
      )
      or cl.company_id in (
        select hca.company_id
        from public.hr_company_assignments hca
        where hca.user_profile_id = v_user_profile_id
      )
    )
  group by cl.id, cl.name, c.id, c.name, cl.created_at, cl.is_active
  order by cl.name;
end;
$$;

grant execute on function public.hr_cluster_directory(text, text) to anon, authenticated;

-- 3. Update hr_area_directory to filter by company if HR role
drop function if exists public.hr_area_directory(text, text);

create or replace function public.hr_area_directory(
  p_username text default null,
  p_password text default null
)
returns table (
  area_id uuid,
  area_name text,
  cluster_count bigint,
  store_count bigint,
  cluster_names text,
  created_at timestamptz,
  updated_at timestamptz,
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
    a.id as area_id,
    a.name as area_name,
    count(distinct cl.id) filter (where cl.is_active = true),
    count(distinct s.id) filter (where s.is_active = true),
    coalesce(
      string_agg(distinct cl.name, ', ' order by cl.name) filter (where cl.is_active = true),
      ''
    ),
    a.created_at,
    a.created_at,
    a.is_active
  from public.areas a
  left join public.clusters cl on cl.area_id = a.id
  left join public.stores s on s.cluster_id = cl.id
  where a.is_active = true
    and a.name <> 'Default Area'
    and (
      v_user_role is null
      or v_user_role <> 'hr'
      or not exists (
        select 1
        from public.hr_company_assignments hca
        where hca.user_profile_id = v_user_profile_id
      )
      or a.company_id in (
        select hca.company_id
        from public.hr_company_assignments hca
        where hca.user_profile_id = v_user_profile_id
      )
      or exists (
        select 1
        from public.clusters cl_sub
        where cl_sub.area_id = a.id
          and cl_sub.company_id in (
            select hca.company_id
            from public.hr_company_assignments hca
            where hca.user_profile_id = v_user_profile_id
          )
      )
    )
  group by a.id, a.name, a.created_at, a.is_active
  order by a.name;
end;
$$;

grant execute on function public.hr_area_directory(text, text) to anon, authenticated;

notify pgrst, 'reload schema';
