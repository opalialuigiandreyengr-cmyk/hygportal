create or replace function public.hr_create_position(
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
  v_position_id uuid;
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
    raise exception 'Position name is required.';
  end if;

  if exists (
    select 1
    from public.positions p
    where lower(p.name) = lower(v_name)
  ) then
    raise exception 'Position already exists.';
  end if;

  insert into public.positions (name, authority_level, is_active)
  values (v_name, 1, true)
  returning id into v_position_id;

  return v_position_id;
end;
$$;

grant execute on function public.hr_create_position(text, text, text) to anon, authenticated;

create or replace function public.hr_update_position(
  p_username text default null,
  p_password text default null,
  p_position_id uuid default null,
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

  if p_position_id is null then
    raise exception 'Position id is required.';
  end if;

  if v_name is null then
    raise exception 'Position name is required.';
  end if;

  if not exists (
    select 1
    from public.positions p
    where p.id = p_position_id
  ) then
    raise exception 'Position was not found.';
  end if;

  if exists (
    select 1
    from public.positions p
    where lower(p.name) = lower(v_name)
      and p.id <> p_position_id
  ) then
    raise exception 'Position already exists.';
  end if;

  update public.positions
  set name = v_name
  where id = p_position_id;

  return p_position_id;
end;
$$;

grant execute on function public.hr_update_position(text, text, uuid, text) to anon, authenticated;

create or replace function public.hr_delete_position(
  p_username text default null,
  p_password text default null,
  p_position_id uuid default null
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

  if p_position_id is null then
    raise exception 'Position id is required.';
  end if;

  if not exists (
    select 1
    from public.positions p
    where p.id = p_position_id
  ) then
    raise exception 'Position was not found.';
  end if;

  if exists (
    select 1
    from public.employee_assignments ea
    where ea.position_id = p_position_id
  ) then
    raise exception 'This position has employee references and cannot be deleted.';
  end if;

  if exists (
    select 1
    from public.requests r
    where r.requester_position_id = p_position_id
  ) then
    raise exception 'This position has request references and cannot be deleted.';
  end if;

  delete from public.department_positions
  where position_id = p_position_id;

  delete from public.positions
  where id = p_position_id;

  return p_position_id;
end;
$$;

grant execute on function public.hr_delete_position(text, text, uuid) to anon, authenticated;

notify pgrst, 'reload schema';
