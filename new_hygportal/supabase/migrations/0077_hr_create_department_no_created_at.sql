-- Avoid relying on functions.created_at when creating HR departments.

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
  order by name, id
  limit 1;

  if v_function_id is null then
    insert into public.functions (name, code)
    values ('Operations', 'OPERATIONS')
    on conflict (name) do update set name = excluded.name
    returning id into v_function_id;
  end if;

  insert into public.departments (name, function_id, is_active)
  values (v_name, v_function_id, true)
  returning id into v_department_id;

  return v_department_id;
end;
$$;

grant execute on function public.hr_create_department(text, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
