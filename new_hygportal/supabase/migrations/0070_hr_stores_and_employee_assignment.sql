-- Expose stores to HR and allow employee profiles to select a company store.

alter table public.stores
  alter column area_id drop not null,
  alter column cluster_id drop not null;

create unique index if not exists idx_stores_company_name_unique
  on public.stores(company_id, lower(name));

create or replace function public.hr_store_directory(
  p_username text default null,
  p_password text default null
)
returns table (
  store_id uuid,
  store_name text,
  company_id uuid,
  company_name text,
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
    count(distinct ea.employee_id) filter (
      where ea.is_primary = true
        and ea.effective_to is null
    ),
    s.created_at,
    s.created_at,
    s.is_active
  from public.stores s
  join public.companies c on c.id = s.company_id
  left join public.employee_assignments ea on ea.store_id = s.id
  where s.is_active = true
  group by s.id, s.name, s.company_id, c.name, s.created_at, s.is_active
  order by c.name, s.name;
end;
$$;

create or replace function public.hr_create_store(
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
  v_store_id uuid;
  v_company_id uuid;
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

  if exists (
    select 1 from public.stores s
    where s.company_id = v_company_id
      and lower(s.name) = lower(v_name)
  ) then
    raise exception 'Store already exists for this company.';
  end if;

  insert into public.stores (company_id, name, is_active)
  values (v_company_id, v_name, true)
  returning id into v_store_id;

  return v_store_id;
end;
$$;

create or replace function public.hr_update_store(
  p_username text default null,
  p_password text default null,
  p_store_id uuid default null,
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
      name = v_name
  where id = p_store_id;

  if not found then
    raise exception 'Store was not found.';
  end if;

  return p_store_id;
end;
$$;

create or replace function public.hr_delete_store(
  p_username text default null,
  p_password text default null,
  p_store_id uuid default null
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

  if p_store_id is null then
    raise exception 'Store id is required.';
  end if;

  if exists (select 1 from public.employee_assignments where store_id = p_store_id)
    or exists (select 1 from public.requests where store_id = p_store_id)
    or exists (select 1 from public.authority_assignments where store_id = p_store_id) then
    raise exception 'This store has employee or request references and cannot be deleted.';
  end if;

  delete from public.stores where id = p_store_id;
  if not found then
    raise exception 'Store was not found.';
  end if;

  return p_store_id;
end;
$$;

create or replace function public.hr_set_employee_store(
  p_username text default null,
  p_password text default null,
  p_employee_id uuid default null,
  p_company_name text default null,
  p_store_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_store_id uuid;
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

  if p_employee_id is null then
    raise exception 'Employee id is required.';
  end if;

  if nullif(trim(coalesce(p_store_name, '')), '') is not null then
    select s.id into v_store_id
    from public.stores s
    join public.companies c on c.id = s.company_id
    where lower(s.name) = lower(trim(p_store_name))
      and lower(c.name) = lower(trim(coalesce(p_company_name, '')))
      and s.is_active = true
    limit 1;

    if v_store_id is null then
      raise exception 'Selected store was not found for this company.';
    end if;
  end if;

  update public.employee_assignments
  set store_id = v_store_id
  where id = (
    select ea.id
    from public.employee_assignments ea
    where ea.employee_id = p_employee_id
      and ea.is_primary = true
    order by
      case when ea.effective_to is null or ea.effective_to >= current_date then 0 else 1 end,
      ea.effective_from desc,
      ea.created_at desc
    limit 1
  );

  if not found then
    raise exception 'Employee primary assignment was not found.';
  end if;

  return p_employee_id;
end;
$$;

create or replace function public.hr_employee_store_detail(
  p_username text default null,
  p_password text default null,
  p_employee_id uuid default null
)
returns table (store_name text)
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
  select s.name
  from public.employee_assignments ea
  left join public.stores s on s.id = ea.store_id
  where ea.employee_id = p_employee_id
    and ea.is_primary = true
  order by
    case when ea.effective_to is null or ea.effective_to >= current_date then 0 else 1 end,
    ea.effective_from desc,
    ea.created_at desc
  limit 1;
end;
$$;

grant execute on function public.hr_store_directory(text, text) to anon, authenticated;
grant execute on function public.hr_create_store(text, text, text, text) to anon, authenticated;
grant execute on function public.hr_update_store(text, text, uuid, text, text) to anon, authenticated;
grant execute on function public.hr_delete_store(text, text, uuid) to anon, authenticated;
grant execute on function public.hr_set_employee_store(text, text, uuid, text, text) to anon, authenticated;
grant execute on function public.hr_employee_store_detail(text, text, uuid) to anon, authenticated;

notify pgrst, 'reload schema';
