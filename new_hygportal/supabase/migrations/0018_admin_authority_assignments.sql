create or replace function public.is_super_admin()
returns boolean
language sql
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from auth.users au
    left join public.user_profiles up on up.auth_user_id = au.id
    where au.id = auth.uid()
      and (
        lower(au.email) = 'hygportal@gmail.com'
        or up.app_role = 'super_admin'
      )
  );
$$;

grant execute on function public.is_super_admin() to authenticated;

create or replace function public.admin_authority_candidates()
returns table (
  employee_id uuid,
  employee_no text,
  full_name text,
  position_id uuid,
  position_name text,
  position_level int,
  function_id uuid,
  function_name text,
  company_id uuid,
  company_name text,
  department_id uuid,
  department_name text,
  current_authority_level int
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
    e.id,
    e.employee_no,
    trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)) as full_name,
    p.id as position_id,
    p.name as position_name,
    p.authority_level as position_level,
    f.id as function_id,
    f.name as function_name,
    c.id as company_id,
    c.name as company_name,
    d.id as department_id,
    d.name as department_name,
    aa.authority_level as current_authority_level
  from public.employees e
  join lateral (
    select *
    from public.employee_assignments ea
    where ea.employee_id = e.id
      and ea.is_primary = true
      and ea.effective_to is null
    order by ea.created_at desc
    limit 1
  ) ea on true
  join public.positions p on p.id = ea.position_id
  join public.functions f on f.id = ea.function_id
  join public.companies c on c.id = ea.company_id
  left join public.departments d on d.id = ea.department_id
  left join lateral (
    select authority_level
    from public.authority_assignments current_aa
    where current_aa.employee_id = e.id
      and current_aa.function_id = ea.function_id
      and current_aa.is_active = true
      and current_aa.effective_to is null
    order by current_aa.created_at desc
    limit 1
  ) aa on true
  where e.employment_status = 'active'
  order by e.last_name, e.first_name;
end;
$$;

grant execute on function public.admin_authority_candidates() to authenticated;

create or replace function public.admin_set_authority_assignment(
  p_employee_id uuid,
  p_function_id uuid,
  p_authority_level int
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.employee_assignments;
  v_authority_id uuid;
begin
  if not public.is_super_admin() then
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

  update public.authority_assignments
  set
    is_active = false,
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
    v_assignment.company_id,
    v_assignment.area_id,
    v_assignment.cluster_id,
    v_assignment.store_id,
    v_assignment.department_id,
    current_date,
    true
  )
  returning id into v_authority_id;

  insert into public.audit_logs (
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    'admin_set_authority_assignment',
    'authority_assignment',
    v_authority_id,
    jsonb_build_object(
      'employee_id', p_employee_id,
      'function_id', p_function_id,
      'authority_level', p_authority_level
    )
  );

  return v_authority_id;
end;
$$;

grant execute on function public.admin_set_authority_assignment(uuid, uuid, int) to authenticated;
