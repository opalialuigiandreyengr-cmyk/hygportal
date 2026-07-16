-- Let HR assign stores to company-level clusters from the Flutter admin app.

drop function if exists public.hr_store_directory(text, text);
drop function if exists public.hr_create_store(text, text, text, text);
drop function if exists public.hr_update_store(text, text, uuid, text, text);

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
    s.id,
    s.name,
    s.company_id,
    c.name,
    cl.id,
    cl.name,
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
  group by s.id, s.name, s.company_id, c.name, cl.id, cl.name, s.created_at, s.is_active
  order by c.name, coalesce(cl.name, ''), s.name;
end;
$$;

create or replace function public.hr_create_store(
  p_username text default null,
  p_password text default null,
  p_company_name text default null,
  p_name text default null,
  p_cluster_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
  v_company_id uuid;
  v_cluster_id uuid;
  v_area_id uuid;
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_cluster_name text := nullif(trim(coalesce(p_cluster_name, '')), '');
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
    raise exception 'Store name is required.';
  end if;

  select c.id into v_company_id
  from public.companies c
  where lower(c.name) = lower(trim(coalesce(p_company_name, '')))
    and c.is_active = true
  limit 1;

  if v_company_id is null then
    raise exception 'Selected company was not found.';
  end if;

  if v_cluster_name is not null and lower(v_cluster_name) <> 'unassigned' then
    select cl.id, cl.area_id
    into v_cluster_id, v_area_id
    from public.clusters cl
    where cl.company_id = v_company_id
      and lower(cl.name) = lower(v_cluster_name)
      and cl.is_active = true
    limit 1;

    if v_cluster_id is null then
      raise exception 'Selected cluster was not found for this company.';
    end if;
  end if;

  if exists (
    select 1 from public.stores s
    where s.company_id = v_company_id
      and lower(s.name) = lower(v_name)
  ) then
    raise exception 'Store already exists for this company.';
  end if;

  insert into public.stores (company_id, area_id, cluster_id, name, is_active)
  values (v_company_id, v_area_id, v_cluster_id, v_name, true)
  returning id into v_store_id;

  return v_store_id;
end;
$$;

create or replace function public.hr_update_store(
  p_username text default null,
  p_password text default null,
  p_store_id uuid default null,
  p_company_name text default null,
  p_name text default null,
  p_cluster_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company_id uuid;
  v_cluster_id uuid;
  v_area_id uuid;
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_cluster_name text := nullif(trim(coalesce(p_cluster_name, '')), '');
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

  if p_store_id is null or v_name is null then
    raise exception 'Store id and name are required.';
  end if;

  select c.id into v_company_id
  from public.companies c
  where lower(c.name) = lower(trim(coalesce(p_company_name, '')))
    and c.is_active = true
  limit 1;

  if v_company_id is null then
    raise exception 'Selected company was not found.';
  end if;

  if v_cluster_name is not null and lower(v_cluster_name) <> 'unassigned' then
    select cl.id, cl.area_id
    into v_cluster_id, v_area_id
    from public.clusters cl
    where cl.company_id = v_company_id
      and lower(cl.name) = lower(v_cluster_name)
      and cl.is_active = true
    limit 1;

    if v_cluster_id is null then
      raise exception 'Selected cluster was not found for this company.';
    end if;
  end if;

  if exists (
    select 1 from public.stores s
    where s.company_id = v_company_id
      and lower(s.name) = lower(v_name)
      and s.id <> p_store_id
  ) then
    raise exception 'Store already exists for this company.';
  end if;

  update public.stores
  set company_id = v_company_id,
      area_id = v_area_id,
      cluster_id = v_cluster_id,
      name = v_name
  where id = p_store_id;

  if not found then
    raise exception 'Store was not found.';
  end if;

  return p_store_id;
end;
$$;

grant execute on function public.hr_store_directory(text, text) to anon, authenticated;
grant execute on function public.hr_create_store(text, text, text, text, text) to anon, authenticated;
grant execute on function public.hr_update_store(text, text, uuid, text, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
