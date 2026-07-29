alter table public.positions
alter column authority_level drop not null;

create or replace function public.admin_clear_position_authority_level(
  p_position_id uuid
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

  if p_position_id is null then
    raise exception 'Position is required.';
  end if;

  update public.positions
  set authority_level = null
  where id = p_position_id;

  insert into public.audit_logs (
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    'admin_clear_position_authority_level',
    'position',
    p_position_id,
    jsonb_build_object('authority_level', null)
  );

  return p_position_id;
end;
$$;

grant execute on function public.admin_clear_position_authority_level(uuid) to authenticated;
