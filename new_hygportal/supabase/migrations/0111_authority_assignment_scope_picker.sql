-- Allow approver assignments to carry explicit store/cluster/area scope.
-- This is required for Cluster/Area Managers whose employee store is N/A.

drop function if exists public.hr_admin_set_authority_assignment(text, text, uuid, uuid, int);

create or replace function public.hr_admin_set_authority_assignment(
  p_username text default null,
  p_password text default null,
  p_employee_id uuid default null,
  p_function_id uuid default null,
  p_authority_level int default null,
  p_store_id uuid default null,
  p_cluster_id uuid default null,
  p_area_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.employee_assignments;
  v_authority_id uuid;
  v_company_id uuid;
  v_area_id uuid;
  v_cluster_id uuid;
  v_store_id uuid;
begin
  if not public.hr_admin_has_access(p_username, p_password) then
    raise exception 'Admin access is required.';
  end if;

  if p_employee_id is null or p_function_id is null or p_authority_level not between 1 and 8 then
    raise exception 'Employee, function, and level 1-8 are required.';
  end if;

  select *
  into v_assignment
  from public.employee_assignments
  where employee_id = p_employee_id
    and is_primary = true
    and effective_to is null
  order by created_at desc
  limit 1;

  if v_assignment.id is null then
    raise exception 'No active employee assignment found.';
  end if;

  v_company_id := v_assignment.company_id;
  v_area_id := v_assignment.area_id;
  v_cluster_id := v_assignment.cluster_id;
  v_store_id := v_assignment.store_id;

  if p_store_id is not null then
    select s.company_id, coalesce(s.area_id, cl.area_id), s.cluster_id, s.id
    into v_company_id, v_area_id, v_cluster_id, v_store_id
    from public.stores s
    left join public.clusters cl on cl.id = s.cluster_id
    where s.id = p_store_id
      and s.is_active = true;

    if v_store_id is null then
      raise exception 'Selected store was not found.';
    end if;
  elsif p_cluster_id is not null then
    select cl.company_id, cl.area_id, cl.id
    into v_company_id, v_area_id, v_cluster_id
    from public.clusters cl
    where cl.id = p_cluster_id
      and cl.is_active = true;

    if v_cluster_id is null then
      raise exception 'Selected cluster was not found.';
    end if;

    v_store_id := null;
  elsif p_area_id is not null then
    select a.company_id, a.id
    into v_company_id, v_area_id
    from public.areas a
    where a.id = p_area_id
      and a.is_active = true;

    if v_area_id is null then
      raise exception 'Selected area was not found.';
    end if;

    v_cluster_id := null;
    v_store_id := null;
  end if;

  update public.authority_assignments
  set is_active = false,
      effective_to = current_date
  where employee_id = p_employee_id
    and function_id = p_function_id
    and is_active = true
    and effective_to is null;

  insert into public.authority_assignments (
    employee_id,
    function_id,
    authority_level,
    company_id,
    area_id,
    cluster_id,
    store_id,
    department_id,
    effective_from,
    is_active
  )
  values (
    p_employee_id,
    p_function_id,
    p_authority_level,
    v_company_id,
    v_area_id,
    v_cluster_id,
    v_store_id,
    v_assignment.department_id,
    current_date,
    true
  )
  returning id into v_authority_id;

  insert into public.audit_logs (action, entity_type, entity_id, metadata)
  values (
    'hr_admin_set_authority_assignment',
    'authority_assignment',
    v_authority_id,
    jsonb_build_object(
      'employee_id', p_employee_id,
      'function_id', p_function_id,
      'authority_level', p_authority_level,
      'store_id', v_store_id,
      'cluster_id', v_cluster_id,
      'area_id', v_area_id
    )
  );

  return v_authority_id;
end;
$$;

grant execute on function public.hr_admin_set_authority_assignment(text, text, uuid, uuid, int, uuid, uuid, uuid) to anon, authenticated;

notify pgrst, 'reload schema';
