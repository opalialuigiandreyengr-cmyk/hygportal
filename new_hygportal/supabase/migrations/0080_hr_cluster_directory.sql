-- HR cluster maintenance for company-level cluster master data.

create unique index if not exists idx_areas_company_name_unique
  on public.areas(company_id, lower(name));

create unique index if not exists idx_clusters_company_name_unique
  on public.clusters(company_id, lower(name));

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
  created_at timestamptz,
  updated_at timestamptz,
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
    cl.id,
    cl.name,
    c.id,
    c.name,
    count(s.id) filter (where s.is_active = true),
    cl.created_at,
    cl.created_at,
    cl.is_active
  from public.clusters cl
  join public.companies c on c.id = cl.company_id
  left join public.stores s on s.cluster_id = cl.id
  where cl.is_active = true
  group by cl.id, cl.name, c.id, c.name, cl.created_at, cl.is_active
  order by c.name, cl.name;
end;
$$;

create or replace function public.hr_create_cluster(
  p_username text default null,
  p_password text default null,
  p_company_name text default null,
  p_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_area_id uuid;
  v_cluster_id uuid;
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

  if v_name is null or nullif(trim(coalesce(p_company_name, '')), '') is null then
    raise exception 'Company and cluster name are required.';
  end if;

  select c.id
  into v_company_id
  from public.companies c
  where lower(c.name) = lower(trim(p_company_name))
    and c.is_active = true
  limit 1;

  if v_company_id is null then
    raise exception 'Selected company was not found.';
  end if;

  if exists (
    select 1
    from public.clusters cl
    where cl.company_id = v_company_id
      and lower(cl.name) = lower(v_name)
  ) then
    raise exception 'Cluster already exists for this company.';
  end if;

  insert into public.areas (company_id, name, is_active)
  values (v_company_id, 'Default Area', true)
  on conflict (company_id, lower(name)) do update
  set is_active = true
  returning id into v_area_id;

  insert into public.clusters (company_id, area_id, name, is_active)
  values (v_company_id, v_area_id, v_name, true)
  returning id into v_cluster_id;

  return v_cluster_id;
end;
$$;

create or replace function public.hr_update_cluster(
  p_username text default null,
  p_password text default null,
  p_cluster_id uuid default null,
  p_company_name text default null,
  p_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_area_id uuid;
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

  if p_cluster_id is null then
    raise exception 'Cluster id is required.';
  end if;

  if v_name is null or nullif(trim(coalesce(p_company_name, '')), '') is null then
    raise exception 'Company and cluster name are required.';
  end if;

  if not exists (
    select 1 from public.clusters cl where cl.id = p_cluster_id
  ) then
    raise exception 'Cluster was not found.';
  end if;

  select c.id
  into v_company_id
  from public.companies c
  where lower(c.name) = lower(trim(p_company_name))
    and c.is_active = true
  limit 1;

  if v_company_id is null then
    raise exception 'Selected company was not found.';
  end if;

  if exists (
    select 1
    from public.clusters cl
    where cl.company_id = v_company_id
      and lower(cl.name) = lower(v_name)
      and cl.id <> p_cluster_id
  ) then
    raise exception 'Cluster already exists for this company.';
  end if;

  insert into public.areas (company_id, name, is_active)
  values (v_company_id, 'Default Area', true)
  on conflict (company_id, lower(name)) do update
  set is_active = true
  returning id into v_area_id;

  update public.clusters
  set company_id = v_company_id,
      area_id = v_area_id,
      name = v_name,
      is_active = true
  where id = p_cluster_id;

  return p_cluster_id;
end;
$$;

create or replace function public.hr_delete_cluster(
  p_username text default null,
  p_password text default null,
  p_cluster_id uuid default null
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

  if p_cluster_id is null then
    raise exception 'Cluster id is required.';
  end if;

  if exists (
    select 1 from public.stores s where s.cluster_id = p_cluster_id
  ) or exists (
    select 1 from public.employee_assignments ea where ea.cluster_id = p_cluster_id
  ) or exists (
    select 1 from public.authority_assignments aa where aa.cluster_id = p_cluster_id
  ) then
    raise exception 'This cluster is still in use and cannot be deleted.';
  end if;

  delete from public.clusters
  where id = p_cluster_id;

  if not found then
    raise exception 'Cluster was not found.';
  end if;

  return p_cluster_id;
end;
$$;

grant execute on function public.hr_cluster_directory(text, text) to anon, authenticated;
grant execute on function public.hr_create_cluster(text, text, text, text) to anon, authenticated;
grant execute on function public.hr_update_cluster(text, text, uuid, text, text) to anon, authenticated;
grant execute on function public.hr_delete_cluster(text, text, uuid) to anon, authenticated;

notify pgrst, 'reload schema';
