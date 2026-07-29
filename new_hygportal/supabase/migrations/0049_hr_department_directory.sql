create or replace function public.hr_department_directory(
  p_username text default null,
  p_password text default null
)
returns table (
  department_id uuid,
  department_name text,
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
    d.id as department_id,
    d.name as department_name,
    count(distinct ea.employee_id) filter (
      where ea.is_primary = true
        and ea.effective_to is null
    ) as employee_count,
    d.created_at,
    d.created_at as updated_at,
    d.is_active
  from public.departments d
  left join public.employee_assignments ea
    on ea.department_id = d.id
  where d.is_active = true
  group by d.id, d.name, d.created_at, d.is_active
  order by d.name;
end;
$$;

grant execute on function public.hr_department_directory(text, text) to anon, authenticated;

create or replace function public.hr_create_department(
  p_username text default null,
  p_password text default null,
  p_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_department_id uuid;
  v_name text := nullif(trim(coalesce(p_name, '')), '');
  v_function_id uuid;
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
    raise exception 'Department name is required.';
  end if;

  if exists (
    select 1
    from public.departments d
    where lower(d.name) = lower(v_name)
  ) then
    raise exception 'Department already exists.';
  end if;

  select id into v_function_id
  from public.functions
  where lower(name) = 'operations'
  order by created_at
  limit 1;

  insert into public.departments (name, function_id, is_active)
  values (v_name, v_function_id, true)
  returning id into v_department_id;

  return v_department_id;
end;
$$;

grant execute on function public.hr_create_department(text, text, text) to anon, authenticated;

create or replace function public.hr_update_department(
  p_username text default null,
  p_password text default null,
  p_department_id uuid default null,
  p_name text default null
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

  if p_department_id is null then
    raise exception 'Department id is required.';
  end if;

  if v_name is null then
    raise exception 'Department name is required.';
  end if;

  if not exists (
    select 1
    from public.departments d
    where d.id = p_department_id
  ) then
    raise exception 'Department was not found.';
  end if;

  if exists (
    select 1
    from public.departments d
    where lower(d.name) = lower(v_name)
      and d.id <> p_department_id
  ) then
    raise exception 'Department already exists.';
  end if;

  update public.departments
  set name = v_name
  where id = p_department_id;

  return p_department_id;
end;
$$;

grant execute on function public.hr_update_department(text, text, uuid, text) to anon, authenticated;

create or replace function public.hr_delete_department(
  p_username text default null,
  p_password text default null,
  p_department_id uuid default null
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

  if p_department_id is null then
    raise exception 'Department id is required.';
  end if;

  if not exists (
    select 1
    from public.departments d
    where d.id = p_department_id
  ) then
    raise exception 'Department was not found.';
  end if;

  if exists (
    select 1
    from public.employee_assignments ea
    where ea.department_id = p_department_id
  ) then
    raise exception 'This department has employee references and cannot be deleted.';
  end if;

  delete from public.approval_level_routes
  where department_id = p_department_id;

  delete from public.department_approval_ladders
  where department_id = p_department_id;

  delete from public.department_positions
  where department_id = p_department_id;

  delete from public.authority_assignments
  where department_id = p_department_id;

  delete from public.departments
  where id = p_department_id;

  return p_department_id;
end;
$$;

grant execute on function public.hr_delete_department(text, text, uuid) to anon, authenticated;

notify pgrst, 'reload schema';
