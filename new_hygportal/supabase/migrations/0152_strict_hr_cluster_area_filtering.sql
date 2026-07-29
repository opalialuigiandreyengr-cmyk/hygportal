-- Migration 0152: Strict cluster and area directory filtering for HR tagged companies

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
  v_has_tagged_companies boolean := false;
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

  if v_user_role = 'hr' then
    select exists (
      select 1
      from public.hr_company_assignments hca
      where hca.user_profile_id = v_user_profile_id
    ) into v_has_tagged_companies;
  end if;

  return query
  select
    cl.id as cluster_id,
    cl.name as cluster_name,
    c.id as company_id,
    c.name as company_name,
    count(distinct s.id) filter (
      where s.is_active = true
        and (
          not v_has_tagged_companies
          or s.company_id in (
            select hca.company_id
            from public.hr_company_assignments hca
            where hca.user_profile_id = v_user_profile_id
          )
        )
    ),
    coalesce(
      string_agg(s.name, ', ' order by s.name) filter (
        where s.is_active = true
          and (
            not v_has_tagged_companies
            or s.company_id in (
              select hca.company_id
              from public.hr_company_assignments hca
              where hca.user_profile_id = v_user_profile_id
            )
          )
      ),
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
      or not v_has_tagged_companies
      or cl.company_id in (
        select hca.company_id
        from public.hr_company_assignments hca
        where hca.user_profile_id = v_user_profile_id
      )
      or exists (
        select 1
        from public.stores s_sub
        where s_sub.cluster_id = cl.id
          and s_sub.is_active = true
          and s_sub.company_id in (
            select hca.company_id
            from public.hr_company_assignments hca
            where hca.user_profile_id = v_user_profile_id
          )
      )
    )
  group by cl.id, cl.name, c.id, c.name, cl.created_at, cl.is_active
  order by cl.name;
end;
$$;

grant execute on function public.hr_cluster_directory(text, text) to anon, authenticated;


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
  v_has_tagged_companies boolean := false;
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

  if v_user_role = 'hr' then
    select exists (
      select 1
      from public.hr_company_assignments hca
      where hca.user_profile_id = v_user_profile_id
    ) into v_has_tagged_companies;
  end if;

  return query
  select
    a.id as area_id,
    a.name as area_name,
    count(distinct cl.id) filter (
      where cl.is_active = true
        and (
          not v_has_tagged_companies
          or cl.company_id in (
            select hca.company_id
            from public.hr_company_assignments hca
            where hca.user_profile_id = v_user_profile_id
          )
        )
    ),
    count(distinct s.id) filter (
      where s.is_active = true
        and (
          not v_has_tagged_companies
          or s.company_id in (
            select hca.company_id
            from public.hr_company_assignments hca
            where hca.user_profile_id = v_user_profile_id
          )
        )
    ),
    coalesce(
      string_agg(distinct cl.name, ', ' order by cl.name) filter (
        where cl.is_active = true
          and (
            not v_has_tagged_companies
            or cl.company_id in (
              select hca.company_id
              from public.hr_company_assignments hca
              where hca.user_profile_id = v_user_profile_id
            )
          )
      ),
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
      or not v_has_tagged_companies
      or a.company_id in (
        select hca.company_id
        from public.hr_company_assignments hca
        where hca.user_profile_id = v_user_profile_id
      )
      or exists (
        select 1
        from public.clusters cl_sub
        where cl_sub.area_id = a.id
          and cl_sub.is_active = true
          and cl_sub.company_id in (
            select hca.company_id
            from public.hr_company_assignments hca
            where hca.user_profile_id = v_user_profile_id
          )
      )
      or exists (
        select 1
        from public.stores s_sub
        join public.clusters cl_sub2 on cl_sub2.id = s_sub.cluster_id
        where cl_sub2.area_id = a.id
          and s_sub.is_active = true
          and s_sub.company_id in (
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
