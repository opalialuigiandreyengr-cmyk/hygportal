create or replace function public.admin_position_authority_levels()
returns table (
  position_id uuid,
  position_name text,
  authority_level int,
  employee_count bigint
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
    p.id,
    p.name,
    p.authority_level,
    count(distinct ea.employee_id) as employee_count
  from public.positions p
  left join public.employee_assignments ea
    on ea.position_id = p.id
   and ea.is_primary = true
   and ea.effective_to is null
  where p.is_active = true
  group by p.id, p.name, p.authority_level
  order by p.authority_level, p.name;
end;
$$;

grant execute on function public.admin_position_authority_levels() to authenticated;

create or replace function public.admin_set_position_authority_level(
  p_position_id uuid,
  p_authority_level int
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Admin access is required.';
  end if;

  if p_position_id is null or p_authority_level not between 1 and 8 then
    raise exception 'Position and level 1-8 are required.';
  end if;

  update public.positions
  set authority_level = p_authority_level
  where id = p_position_id;

  insert into public.audit_logs (
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    'admin_set_position_authority_level',
    'position',
    p_position_id,
    jsonb_build_object('authority_level', p_authority_level)
  );

  return p_position_id;
end;
$$;

grant execute on function public.admin_set_position_authority_level(uuid, int) to authenticated;
