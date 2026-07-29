-- Manage store clusters and let cluster-level approvers cover all stores in a cluster.

alter table public.stores
  alter column area_id drop not null,
  alter column cluster_id drop not null;

create unique index if not exists idx_areas_company_name_unique
  on public.areas(company_id, lower(name));

create unique index if not exists idx_clusters_company_name_unique
  on public.clusters(company_id, lower(name));

create or replace function public.scope_matches_assignment(
  p_level int,
  p_assignment public.employee_assignments,
  p_authority public.authority_assignments
)
returns boolean
language plpgsql
stable
as $$
begin
  if p_authority.company_id is not null and p_authority.company_id <> p_assignment.company_id then
    return false;
  end if;

  if p_authority.department_id is not null
    and p_assignment.department_id is not null
    and p_authority.department_id <> p_assignment.department_id then
    return false;
  end if;

  if p_level = 2 then
    return p_authority.store_id is not null and p_authority.store_id = p_assignment.store_id;
  elsif p_level = 3 then
    return (
      (p_authority.cluster_id is not null and p_authority.cluster_id = p_assignment.cluster_id)
      or (
        p_authority.cluster_id is null
        and p_authority.store_id is null
        and p_authority.company_id = p_assignment.company_id
      )
    );
  elsif p_level = 4 then
    return (
      (p_authority.area_id is not null and p_authority.area_id = p_assignment.area_id)
      or (p_authority.area_id is null and p_authority.cluster_id is not null and p_authority.cluster_id = p_assignment.cluster_id)
      or (p_authority.area_id is null and p_authority.cluster_id is null and p_authority.company_id = p_assignment.company_id)
    );
  elsif p_level = 5 then
    return (
      (p_authority.area_id is not null and p_authority.area_id = p_assignment.area_id)
      or (p_authority.area_id is null and p_authority.company_id = p_assignment.company_id)
    );
  else
    return p_authority.company_id is not null and p_authority.company_id = p_assignment.company_id;
  end if;
end;
$$;

create or replace function public.admin_cluster_directory()
returns table (
  cluster_id uuid,
  cluster_name text,
  company_id uuid,
  company_name text,
  area_id uuid,
  area_name text,
  store_count bigint,
  is_active boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Admin access is required.';
  end if;

  return query
  select
    cl.id,
    cl.name,
    cl.company_id,
    c.name,
    cl.area_id,
    a.name,
    count(distinct s.id) filter (where s.is_active = true),
    cl.is_active
  from public.clusters cl
  join public.companies c on c.id = cl.company_id
  left join public.areas a on a.id = cl.area_id
  left join public.stores s on s.cluster_id = cl.id
  where cl.is_active = true
  group by cl.id, cl.name, cl.company_id, c.name, cl.area_id, a.name, cl.is_active
  order by c.name, cl.name;
end;
$$;

grant execute on function public.admin_cluster_directory() to authenticated;

create or replace function public.admin_store_cluster_catalog()
returns table (
  store_id uuid,
  store_name text,
  company_id uuid,
  company_name text,
  cluster_id uuid,
  cluster_name text,
  area_id uuid,
  area_name text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Admin access is required.';
  end if;

  return query
  select
    s.id,
    s.name,
    s.company_id,
    c.name,
    s.cluster_id,
    cl.name,
    s.area_id,
    a.name
  from public.stores s
  join public.companies c on c.id = s.company_id
  left join public.clusters cl on cl.id = s.cluster_id
  left join public.areas a on a.id = s.area_id
  where s.is_active = true
  order by c.name, s.name;
end;
$$;

grant execute on function public.admin_store_cluster_catalog() to authenticated;

create or replace function public.admin_create_cluster(
  p_company_name text,
  p_name text
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
  if not public.is_super_admin() then
    raise exception 'Admin access is required.';
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

grant execute on function public.admin_create_cluster(text, text) to authenticated;

create or replace function public.admin_assign_store_cluster(
  p_store_id uuid,
  p_cluster_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store public.stores;
  v_cluster public.clusters;
begin
  if not public.is_super_admin() then
    raise exception 'Admin access is required.';
  end if;

  if p_store_id is null then
    raise exception 'Store is required.';
  end if;

  select *
  into v_store
  from public.stores
  where id = p_store_id
    and is_active = true;

  if v_store.id is null then
    raise exception 'Store was not found.';
  end if;

  if p_cluster_id is not null then
    select *
    into v_cluster
    from public.clusters
    where id = p_cluster_id
      and is_active = true;

    if v_cluster.id is null then
      raise exception 'Cluster was not found.';
    end if;

    if v_cluster.company_id <> v_store.company_id then
      raise exception 'Cluster and store must belong to the same company.';
    end if;
  end if;

  update public.stores
  set cluster_id = p_cluster_id,
      area_id = case when p_cluster_id is null then null else v_cluster.area_id end
  where id = p_store_id;

  update public.employee_assignments
  set cluster_id = p_cluster_id,
      area_id = case when p_cluster_id is null then null else v_cluster.area_id end
  where store_id = p_store_id
    and is_primary = true
    and (effective_to is null or effective_to >= current_date);

  return p_store_id;
end;
$$;

grant execute on function public.admin_assign_store_cluster(uuid, uuid) to authenticated;

create or replace function public.admin_set_employee_cluster_scope(
  p_employee_id uuid,
  p_cluster_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cluster public.clusters;
begin
  if not public.is_super_admin() then
    raise exception 'Admin access is required.';
  end if;

  if p_employee_id is null or p_cluster_id is null then
    raise exception 'Employee and cluster are required.';
  end if;

  select *
  into v_cluster
  from public.clusters
  where id = p_cluster_id
    and is_active = true;

  if v_cluster.id is null then
    raise exception 'Cluster was not found.';
  end if;

  update public.employee_assignments
  set company_id = v_cluster.company_id,
      area_id = v_cluster.area_id,
      cluster_id = v_cluster.id,
      store_id = null
  where id = (
    select ea.id
    from public.employee_assignments ea
    where ea.employee_id = p_employee_id
      and ea.is_primary = true
      and (ea.effective_to is null or ea.effective_to >= current_date)
    order by ea.effective_from desc, ea.created_at desc
    limit 1
  );

  if not found then
    raise exception 'Employee primary assignment was not found.';
  end if;

  return p_employee_id;
end;
$$;

grant execute on function public.admin_set_employee_cluster_scope(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
