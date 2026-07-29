create or replace function public.admin_approval_route_matrix()
returns table (
  department_id uuid,
  department_name text,
  requester_level int,
  step_order int,
  approver_level int
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
    requester_levels.level,
    step_orders.step_order,
    r.approver_level
  from public.departments d
  cross join generate_series(1, 8) as requester_levels(level)
  cross join generate_series(1, 2) as step_orders(step_order)
  left join public.approval_level_routes r
    on r.department_id = d.id
   and r.requester_level = requester_levels.level
   and r.step_order = step_orders.step_order
  where d.is_active = true
  order by d.name, requester_levels.level, step_orders.step_order;
end;
$$;

grant execute on function public.admin_approval_route_matrix() to authenticated;

create or replace function public.admin_set_approval_route(
  p_department_id uuid,
  p_requester_level int,
  p_step_order int,
  p_approver_level int
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_route_id uuid;
begin
  if not public.is_super_admin() then
    raise exception 'Admin access is required.';
  end if;

  if p_department_id is null
    or p_requester_level not between 1 and 8
    or p_step_order not between 1 and 2
    or p_approver_level not between 1 and 8 then
    raise exception 'Department, requester level, step 1-2, and approver level 1-8 are required.';
  end if;

  update public.approval_level_routes
  set approver_level = p_approver_level
  where department_id = p_department_id
    and requester_level = p_requester_level
    and step_order = p_step_order
  returning id into v_route_id;

  if v_route_id is null then
    insert into public.approval_level_routes (
      department_id,
      requester_level,
      step_order,
      approver_level
    )
    values (
      p_department_id,
      p_requester_level,
      p_step_order,
      p_approver_level
    )
    returning id into v_route_id;
  end if;

  insert into public.audit_logs (action, entity_type, entity_id, metadata)
  values (
    'admin_set_approval_route',
    'approval_route',
    v_route_id,
    jsonb_build_object(
      'department_id', p_department_id,
      'requester_level', p_requester_level,
      'step_order', p_step_order,
      'approver_level', p_approver_level
    )
  );

  return v_route_id;
end;
$$;

grant execute on function public.admin_set_approval_route(uuid, int, int, int) to authenticated;
