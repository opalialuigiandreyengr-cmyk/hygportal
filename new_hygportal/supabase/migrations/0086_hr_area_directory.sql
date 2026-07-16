-- HR area maintenance from Flutter Cluster / Area screen.

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
    a.id,
    a.name,
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
  group by a.id, a.name, a.created_at, a.is_active
  order by a.name;
end;
$$;

create or replace function public.hr_create_area_with_clusters(
  p_username text default null,
  p_password text default null,
  p_name text default null,
  p_cluster_ids uuid[] default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_area_id uuid;
  v_company_id uuid;
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_cluster_count int;
  v_valid_cluster_count int;
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

  v_cluster_count := coalesce(array_length(p_cluster_ids, 1), 0);
  if v_name is null or v_cluster_count = 0 then
    raise exception 'Area name and at least one cluster are required.';
  end if;

  select count(*), (array_agg(cl.company_id order by cl.name))[1]
  into v_valid_cluster_count, v_company_id
  from public.clusters cl
  where cl.id = any(p_cluster_ids)
    and cl.is_active = true;

  if v_valid_cluster_count <> v_cluster_count then
    raise exception 'One or more selected clusters were not found.';
  end if;

  if exists (
    select 1
    from public.areas a
    where a.company_id = v_company_id
      and lower(a.name) = lower(v_name)
  ) then
    raise exception 'Area already exists.';
  end if;

  insert into public.areas (company_id, name, is_active)
  values (v_company_id, v_name, true)
  returning id into v_area_id;

  update public.clusters
  set area_id = v_area_id
  where id = any(p_cluster_ids);

  update public.stores
  set area_id = v_area_id
  where cluster_id = any(p_cluster_ids);

  update public.employee_assignments
  set area_id = v_area_id
  where cluster_id = any(p_cluster_ids)
    and effective_to is null;

  return v_area_id;
end;
$$;

create or replace function public.hr_update_area_with_clusters(
  p_username text default null,
  p_password text default null,
  p_area_id uuid default null,
  p_name text default null,
  p_cluster_ids uuid[] default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_default_area_id uuid;
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_cluster_count int;
  v_valid_cluster_count int;
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

  v_cluster_count := coalesce(array_length(p_cluster_ids, 1), 0);
  if p_area_id is null or v_name is null or v_cluster_count = 0 then
    raise exception 'Area name and at least one cluster are required.';
  end if;

  if not exists (select 1 from public.areas a where a.id = p_area_id) then
    raise exception 'Area was not found.';
  end if;

  select count(*), (array_agg(cl.company_id order by cl.name))[1]
  into v_valid_cluster_count, v_company_id
  from public.clusters cl
  where cl.id = any(p_cluster_ids)
    and cl.is_active = true;

  if v_valid_cluster_count <> v_cluster_count then
    raise exception 'One or more selected clusters were not found.';
  end if;

  if exists (
    select 1
    from public.areas a
    where a.company_id = v_company_id
      and lower(a.name) = lower(v_name)
      and a.id <> p_area_id
  ) then
    raise exception 'Area already exists.';
  end if;

  insert into public.areas (company_id, name, is_active)
  values (v_company_id, 'Default Area', true)
  on conflict (company_id, lower(name)) do update
  set is_active = true
  returning id into v_default_area_id;

  update public.clusters
  set area_id = v_default_area_id
  where area_id = p_area_id
    and not (id = any(p_cluster_ids));

  update public.stores s
  set area_id = v_default_area_id
  from public.clusters cl
  where s.cluster_id = cl.id
    and cl.area_id = v_default_area_id;

  update public.employee_assignments ea
  set area_id = v_default_area_id
  from public.clusters cl
  where ea.cluster_id = cl.id
    and cl.area_id = v_default_area_id
    and ea.effective_to is null;

  update public.areas
  set company_id = v_company_id,
      name = v_name,
      is_active = true
  where id = p_area_id;

  update public.clusters
  set area_id = p_area_id
  where id = any(p_cluster_ids);

  update public.stores
  set area_id = p_area_id
  where cluster_id = any(p_cluster_ids);

  update public.employee_assignments
  set area_id = p_area_id
  where cluster_id = any(p_cluster_ids)
    and effective_to is null;

  return p_area_id;
end;
$$;

create or replace function public.hr_delete_area(
  p_username text default null,
  p_password text default null,
  p_area_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_default_area_id uuid;
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

  select a.company_id
  into v_company_id
  from public.areas a
  where a.id = p_area_id;

  if v_company_id is null then
    raise exception 'Area was not found.';
  end if;

  insert into public.areas (company_id, name, is_active)
  values (v_company_id, 'Default Area', true)
  on conflict (company_id, lower(name)) do update
  set is_active = true
  returning id into v_default_area_id;

  update public.clusters
  set area_id = v_default_area_id
  where area_id = p_area_id;

  update public.stores s
  set area_id = v_default_area_id
  from public.clusters cl
  where s.cluster_id = cl.id
    and cl.area_id = v_default_area_id;

  update public.employee_assignments ea
  set area_id = v_default_area_id
  from public.clusters cl
  where ea.cluster_id = cl.id
    and cl.area_id = v_default_area_id
    and ea.effective_to is null;

  delete from public.areas
  where id = p_area_id;

  return p_area_id;
end;
$$;

grant execute on function public.hr_area_directory(text, text) to anon, authenticated;
grant execute on function public.hr_create_area_with_clusters(text, text, text, uuid[]) to anon, authenticated;
grant execute on function public.hr_update_area_with_clusters(text, text, uuid, text, uuid[]) to anon, authenticated;
grant execute on function public.hr_delete_area(text, text, uuid) to anon, authenticated;

notify pgrst, 'reload schema';
