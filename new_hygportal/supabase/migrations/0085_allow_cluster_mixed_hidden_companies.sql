-- Cluster creation is store-driven in HR; keep company internal and infer it from
-- the first selected store instead of blocking mixed hidden company ids.

create or replace function public.hr_create_cluster_with_stores(
  p_username text default null,
  p_password text default null,
  p_name text default null,
  p_store_ids uuid[] default null
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
  v_store_count int;
  v_valid_store_count int;
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

  v_store_count := coalesce(array_length(p_store_ids, 1), 0);
  if v_name is null or v_store_count = 0 then
    raise exception 'Cluster name and at least one store are required.';
  end if;

  select count(*), (array_agg(s.company_id order by s.name))[1]
  into v_valid_store_count, v_company_id
  from public.stores s
  where s.id = any(p_store_ids)
    and s.is_active = true;

  if v_valid_store_count <> v_store_count then
    raise exception 'One or more selected stores were not found.';
  end if;

  if exists (
    select 1
    from public.clusters cl
    where cl.company_id = v_company_id
      and lower(cl.name) = lower(v_name)
  ) then
    raise exception 'Cluster already exists.';
  end if;

  insert into public.areas (company_id, name, is_active)
  values (v_company_id, 'Default Area', true)
  on conflict (company_id, lower(name)) do update
  set is_active = true
  returning id into v_area_id;

  insert into public.clusters (company_id, area_id, name, is_active)
  values (v_company_id, v_area_id, v_name, true)
  returning id into v_cluster_id;

  update public.stores
  set area_id = v_area_id,
      cluster_id = v_cluster_id
  where id = any(p_store_ids);

  update public.employee_assignments
  set area_id = v_area_id,
      cluster_id = v_cluster_id
  where store_id = any(p_store_ids)
    and effective_to is null;

  return v_cluster_id;
end;
$$;

create or replace function public.hr_update_cluster_with_stores(
  p_username text default null,
  p_password text default null,
  p_cluster_id uuid default null,
  p_name text default null,
  p_store_ids uuid[] default null
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
  v_store_count int;
  v_valid_store_count int;
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

  v_store_count := coalesce(array_length(p_store_ids, 1), 0);
  if p_cluster_id is null or v_name is null or v_store_count = 0 then
    raise exception 'Cluster name and at least one store are required.';
  end if;

  if not exists (select 1 from public.clusters cl where cl.id = p_cluster_id) then
    raise exception 'Cluster was not found.';
  end if;

  select count(*), (array_agg(s.company_id order by s.name))[1]
  into v_valid_store_count, v_company_id
  from public.stores s
  where s.id = any(p_store_ids)
    and s.is_active = true;

  if v_valid_store_count <> v_store_count then
    raise exception 'One or more selected stores were not found.';
  end if;

  if exists (
    select 1
    from public.clusters cl
    where cl.company_id = v_company_id
      and lower(cl.name) = lower(v_name)
      and cl.id <> p_cluster_id
  ) then
    raise exception 'Cluster already exists.';
  end if;

  insert into public.areas (company_id, name, is_active)
  values (v_company_id, 'Default Area', true)
  on conflict (company_id, lower(name)) do update
  set is_active = true
  returning id into v_area_id;

  update public.stores
  set area_id = null,
      cluster_id = null
  where cluster_id = p_cluster_id
    and not (id = any(p_store_ids));

  update public.employee_assignments
  set area_id = null,
      cluster_id = null
  where cluster_id = p_cluster_id
    and effective_to is null
    and not (store_id = any(p_store_ids));

  update public.clusters
  set company_id = v_company_id,
      area_id = v_area_id,
      name = v_name,
      is_active = true
  where id = p_cluster_id;

  update public.stores
  set area_id = v_area_id,
      cluster_id = p_cluster_id
  where id = any(p_store_ids);

  update public.employee_assignments
  set area_id = v_area_id,
      cluster_id = p_cluster_id
  where store_id = any(p_store_ids)
    and effective_to is null;

  return p_cluster_id;
end;
$$;

grant execute on function public.hr_create_cluster_with_stores(text, text, text, uuid[]) to anon, authenticated;
grant execute on function public.hr_update_cluster_with_stores(text, text, uuid, text, uuid[]) to anon, authenticated;

notify pgrst, 'reload schema';
