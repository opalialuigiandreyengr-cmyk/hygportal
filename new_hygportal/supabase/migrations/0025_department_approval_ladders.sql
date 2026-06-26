create table if not exists public.department_approval_ladders (
  department_id uuid not null references public.departments(id) on delete cascade,
  authority_level int not null check (authority_level between 1 and 8),
  created_at timestamptz not null default now(),
  primary key (department_id, authority_level)
);

alter table public.department_approval_ladders enable row level security;

drop policy if exists "Authenticated users can read department approval ladders" on public.department_approval_ladders;
create policy "Authenticated users can read department approval ladders"
on public.department_approval_ladders for select
to authenticated
using (true);

insert into public.department_approval_ladders (department_id, authority_level)
select distinct d.id, p.authority_level
from public.departments d
join public.department_positions dp on dp.department_id = d.id
join public.positions p on p.id = dp.position_id
where d.is_active = true
  and p.is_active = true
  and p.authority_level is not null
on conflict do nothing;

insert into public.department_approval_ladders (department_id, authority_level)
select distinct department_id, approver_level
from public.approval_level_routes
where department_id is not null
on conflict do nothing;

create or replace function public.admin_department_approval_ladders()
returns table (
  department_id uuid,
  department_name text,
  route_levels int[]
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
    d.id,
    d.name,
    coalesce(
      array_agg(l.authority_level order by l.authority_level) filter (where l.authority_level is not null),
      '{}'::int[]
    ) as route_levels
  from public.departments d
  left join public.department_approval_ladders l on l.department_id = d.id
  where d.is_active = true
  group by d.id, d.name
  order by d.name;
end;
$$;

grant execute on function public.admin_department_approval_ladders() to authenticated;

create or replace function public.admin_set_department_approval_ladder(
  p_department_id uuid,
  p_levels int[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_level int;
  v_requester_level int;
  v_step_one int;
  v_step_two int;
begin
  if not public.is_super_admin() then
    raise exception 'Admin access is required.';
  end if;

  if p_department_id is null then
    raise exception 'Department is required.';
  end if;

  if p_levels is null or array_length(p_levels, 1) is null then
    raise exception 'At least one level is required.';
  end if;

  delete from public.department_approval_ladders
  where department_id = p_department_id;

  for v_level in
    select distinct level_value
    from unnest(p_levels) as level_value
    where level_value between 1 and 8
    order by level_value
  loop
    insert into public.department_approval_ladders (department_id, authority_level)
    values (p_department_id, v_level)
    on conflict do nothing;
  end loop;

  delete from public.approval_level_routes
  where department_id = p_department_id;

  for v_requester_level in 1..8 loop
    select authority_level
    into v_step_one
    from public.department_approval_ladders
    where department_id = p_department_id
      and authority_level > v_requester_level
    order by authority_level
    limit 1;

    select authority_level
    into v_step_two
    from public.department_approval_ladders
    where department_id = p_department_id
      and authority_level > coalesce(v_step_one, v_requester_level)
    order by authority_level
    limit 1;

    if v_step_one is not null then
      insert into public.approval_level_routes (department_id, requester_level, step_order, approver_level)
      values (p_department_id, v_requester_level, 1, v_step_one);
    end if;

    if v_step_two is not null then
      insert into public.approval_level_routes (department_id, requester_level, step_order, approver_level)
      values (p_department_id, v_requester_level, 2, v_step_two);
    end if;
  end loop;

  insert into public.audit_logs (action, entity_type, entity_id, metadata)
  values (
    'admin_set_department_approval_ladder',
    'department',
    p_department_id,
    jsonb_build_object('levels', p_levels)
  );

  return p_department_id;
end;
$$;

grant execute on function public.admin_set_department_approval_ladder(uuid, int[]) to authenticated;
