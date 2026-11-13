-- ============================================================================
-- Migration 0226: Operations Approval Route - Assistant Store Manager Fallback
--
-- Description:
-- In the Operations department approval routes:
-- 1. Level 2 represents the store-level approver (Store Manager).
-- 2. If no Store Manager has been assigned to a specific store (or none is currently
--    active), the Assistant Store Manager (ASM) assigned to that store should be
--    assigned as the approver for the meantime.
-- 3. If neither a Store Manager nor an Assistant Store Manager is assigned,
--    the approval engine maintains existing escalation rules (escalating upward to
--    Level 4 Cluster Manager and Level 5 Area Manager).
-- 4. If the requester themselves is the Assistant Store Manager, the self-approval
--    prevention rule ensures they cannot approve their own request, properly
--    escalating to Cluster Manager.
-- 5. Updates:
--    a) public.find_request_approver - checks for Assistant Store Manager at Level 2
--       when no Store Manager is found for the requester's store.
--       Maintains STRICTLY a single 5-parameter signature to prevent ambiguous
--       function resolution (PostgreSQL 42725).
--    b) public.get_store_approval_route - reflects Assistant Store Manager as Step 1 approver.
--    c) public.hr_admin_store_route_scopes - shows Assistant Store Manager with '(ASM)'
--       in the Admin Desktop Store Route Map preview when no Store Manager is tagged.
--    d) public.submit_time_request, public.submit_travel_order_request, public.submit_leave_request
--       - populates approver metadata (name, position, emp_no) and notifies the ASM.
--    e) Backfills existing pending Step 1 requests from stores without Store Managers.
-- ============================================================================

-- ============================================================================
-- 1. Update public.find_request_approver with Assistant Store Manager Fallback
-- ============================================================================
-- Drop any existing variants to ensure a single unique signature
drop function if exists public.find_request_approver(uuid, uuid, int, uuid, uuid[], uuid);
drop function if exists public.find_request_approver(uuid, uuid, int, uuid, uuid[]);

create or replace function public.find_request_approver(
  p_assignment_id uuid,
  p_required_function_id uuid,
  p_starting_level int,
  p_requester_employee_id uuid,
  p_used_employee_ids uuid[] default '{}'
)
returns table (
  approver_employee_id uuid,
  approver_user_profile_id uuid,
  resolved_level int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.employee_assignments;
  v_requester_level int;
  v_search_start_level int;
  v_level int;
  v_authority public.authority_assignments;
  v_required_position_id uuid;
  v_has_configured_ladder boolean := false;
  v_authority_store_id uuid;
  v_authority_cluster_id uuid;
  v_authority_area_id uuid;
begin
  select *
  into v_assignment
  from public.employee_assignments
  where id = p_assignment_id;

  if v_assignment.id is null then
    return;
  end if;

  -- 1. Resolve store, cluster, and area for the requester assignment
  if v_assignment.store_id is not null then
    select
      coalesce(s.area_id, cl.area_id, v_assignment.area_id),
      coalesce(s.cluster_id, v_assignment.cluster_id)
    into v_assignment.area_id, v_assignment.cluster_id
    from public.stores s
    left join public.clusters cl on cl.id = s.cluster_id
    where s.id = v_assignment.store_id;
  elsif v_assignment.cluster_id is not null then
    select coalesce(cl.area_id, v_assignment.area_id)
    into v_assignment.area_id
    from public.clusters cl
    where cl.id = v_assignment.cluster_id;
  end if;

  -- Fallback to authority assignment if area_id or cluster_id is still null
  if v_assignment.area_id is null then
    select aa.area_id
    into v_assignment.area_id
    from public.authority_assignments aa
    where aa.employee_id = v_assignment.employee_id
      and aa.area_id is not null
      and aa.is_active = true
      and aa.effective_from <= current_date
      and (aa.effective_to is null or aa.effective_to >= current_date)
    order by aa.created_at desc
    limit 1;
  end if;

  if v_assignment.cluster_id is null then
    select aa.cluster_id
    into v_assignment.cluster_id
    from public.authority_assignments aa
    where aa.employee_id = v_assignment.employee_id
      and aa.cluster_id is not null
      and aa.is_active = true
      and aa.effective_from <= current_date
      and (aa.effective_to is null or aa.effective_to >= current_date)
    order by aa.created_at desc
    limit 1;
  end if;

  select p.authority_level
  into v_requester_level
  from public.positions p
  where p.id = v_assignment.position_id
  limit 1;

  v_search_start_level := greatest(
    coalesce(p_starting_level, 1),
    coalesce(v_requester_level, 0) + 1
  );

  for v_level in v_search_start_level..8 loop
    v_required_position_id := null;
    v_has_configured_ladder := false;

    select l.approver_position_id, true
    into v_required_position_id, v_has_configured_ladder
    from public.department_approval_ladders l
    where l.department_id = v_assignment.department_id
      and l.authority_level = v_level
    limit 1;

    for v_authority in
      select aa.*
      from public.authority_assignments aa
      where aa.authority_level = v_level
        and (
          v_has_configured_ladder
          or v_level >= 7
          or aa.function_id = p_required_function_id
        )
        and (
          v_required_position_id is null
          or exists (
            select 1
            from public.employee_assignments ea
            where ea.employee_id = aa.employee_id
              and ea.position_id = v_required_position_id
              and ea.is_primary = true
              and ea.effective_from <= current_date
              and (ea.effective_to is null or ea.effective_to >= current_date)
          )
        )
        and aa.is_active = true
        and aa.effective_from <= current_date
        and (aa.effective_to is null or aa.effective_to >= current_date)
        and aa.employee_id <> p_requester_employee_id
        and not (aa.employee_id = any(p_used_employee_ids))
        and exists (
          select 1 from public.employees e
          left join public.user_profiles up on up.employee_id = e.id
          left join auth.users au on au.id = up.auth_user_id
          where e.id = aa.employee_id
            and lower(trim(coalesce(e.employment_status, 'active'))) not in ('banned', 'inactive', 'terminated', 'resigned')
            and coalesce(up.is_active, true) = true
            and (au.banned_until is null or au.banned_until <= now())
        )
      order by
        case when exists (
          select 1 from public.employee_assignments ea_d
          where ea_d.employee_id = aa.employee_id
            and ea_d.is_primary = true
            and ea_d.department_id = v_assignment.department_id
        ) then 0 else 1 end,
        case when exists (
          select 1 from public.employee_assignments ea_c
          where ea_c.employee_id = aa.employee_id
            and ea_c.is_primary = true
            and ea_c.company_id = v_assignment.company_id
        ) then 0 else 1 end,
        aa.created_at asc
    loop
      v_authority_store_id := v_authority.store_id;
      v_authority_cluster_id := v_authority.cluster_id;
      v_authority_area_id := v_authority.area_id;

      select
        coalesce(ea.store_id, v_authority_store_id),
        coalesce(ea.cluster_id, s.cluster_id, v_authority_cluster_id),
        coalesce(ea.area_id, s.area_id, cl.area_id, v_authority_area_id)
      into v_authority_store_id, v_authority_cluster_id, v_authority_area_id
      from public.employee_assignments ea
      left join public.stores s on s.id = ea.store_id
      left join public.clusters cl on cl.id = coalesce(ea.cluster_id, s.cluster_id)
      where ea.employee_id = v_authority.employee_id
        and ea.is_primary = true
        and ea.effective_from <= current_date
        and (ea.effective_to is null or ea.effective_to >= current_date)
      order by ea.created_at desc
      limit 1;

      v_authority.store_id := v_authority_store_id;
      v_authority.cluster_id := v_authority_cluster_id;
      v_authority_area_id := v_authority_area_id;

      if (
        v_has_configured_ladder
        and (
          (
            v_level = 2 and (
              (
                v_authority.store_id is null
                and not exists (
                  select 1 from public.employee_store_assignments esa
                  where esa.employee_id = v_authority.employee_id
                )
              )
              or (
                v_assignment.store_id is not null
                and (
                  v_authority.store_id = v_assignment.store_id
                  or exists (
                    select 1 from public.employee_store_assignments esa
                    where esa.employee_id = v_authority.employee_id
                      and esa.store_id = v_assignment.store_id
                  )
                )
              )
            )
          )
          or (
            v_level = 4 and (
              v_authority.cluster_id is null
              or (
                v_assignment.cluster_id is not null
                and v_authority.cluster_id = v_assignment.cluster_id
              )
            )
          )
          or (
            v_level = 5 and (
              v_authority.area_id is null
              or (
                v_assignment.area_id is not null
                and v_authority.area_id = v_assignment.area_id
              )
            )
          )
          or v_level not in (2, 4, 5)
        )
      )
        or (
          not v_has_configured_ladder
          and (
            v_level >= 7
            or public.scope_matches_assignment(v_level, v_assignment, v_authority)
          )
        ) then
        approver_employee_id := v_authority.employee_id;
        select up.id
        into approver_user_profile_id
        from public.user_profiles up
        where up.employee_id = v_authority.employee_id
        limit 1;
        resolved_level := v_level;
        return next;
        return;
      end if;
    end loop;

    -- Fallback: check matching position in employee_assignments if not found in authority_assignments
    if v_required_position_id is not null then
      select ea.employee_id, up.id
      into approver_employee_id, approver_user_profile_id
      from public.employee_assignments ea
      left join public.stores s on s.id = ea.store_id
      left join public.clusters cl on cl.id = coalesce(ea.cluster_id, s.cluster_id)
      left join public.user_profiles up on up.employee_id = ea.employee_id
      where ea.position_id = v_required_position_id
        and ea.employee_id <> p_requester_employee_id
        and not (ea.employee_id = any(p_used_employee_ids))
        and ea.is_primary = true
        and ea.effective_from <= current_date
        and (ea.effective_to is null or ea.effective_to >= current_date)
        and (
          (
            v_level = 2 and (
              (
                ea.store_id is null
                and not exists (
                  select 1 from public.employee_store_assignments esa
                  where esa.employee_id = ea.employee_id
                )
              )
              or (
                v_assignment.store_id is not null
                and (
                  ea.store_id = v_assignment.store_id
                  or exists (
                    select 1 from public.employee_store_assignments esa
                    where esa.employee_id = ea.employee_id
                      and esa.store_id = v_assignment.store_id
                  )
                )
              )
            )
          )
          or (
            v_level = 4 and (
              coalesce(ea.cluster_id, s.cluster_id) is null
              or (
                v_assignment.cluster_id is not null
                and coalesce(ea.cluster_id, s.cluster_id) = v_assignment.cluster_id
              )
            )
          )
          or (
            v_level = 5 and (
              coalesce(ea.area_id, s.area_id, cl.area_id) is null
              or (
                v_assignment.area_id is not null
                and coalesce(ea.area_id, s.area_id, cl.area_id) = v_assignment.area_id
              )
            )
          )
          or v_level not in (2, 4, 5)
        )
        and exists (
          select 1 from public.employees e
          left join public.user_profiles up2 on up2.employee_id = e.id
          left join auth.users au on au.id = up2.auth_user_id
          where e.id = ea.employee_id
            and lower(trim(coalesce(e.employment_status, 'active'))) not in ('banned', 'inactive', 'terminated', 'resigned')
            and coalesce(up2.is_active, true) = true
            and (au.banned_until is null or au.banned_until <= now())
        )
      order by
        case when ea.department_id = v_assignment.department_id then 0 else 1 end,
        case when ea.company_id = v_assignment.company_id then 0 else 1 end,
        case when ea.store_id = v_assignment.store_id then 0 else 1 end,
        ea.created_at asc
      limit 1;

      if approver_employee_id is not null then
        resolved_level := v_level;
        return next;
        return;
      end if;
    end if;

    -- ========================================================================
    -- LEVEL 2 FALLBACK (OPERATIONS):
    -- If no Store Manager has been assigned to this specific store,
    -- assign the Assistant Store Manager as the approver for the meantime.
    -- ========================================================================
    if approver_employee_id is null and v_level = 2 and v_assignment.store_id is not null then
      -- 1. Check if an active Assistant Store Manager has an authority assignment for this store
      select aa.employee_id, up.id
      into approver_employee_id, approver_user_profile_id
      from public.authority_assignments aa
      join public.employee_assignments ea on ea.employee_id = aa.employee_id and ea.is_primary = true
      join public.positions pos on pos.id = ea.position_id
      left join public.user_profiles up on up.employee_id = aa.employee_id
      where (
        lower(trim(pos.name)) in ('assistant store manager', 'assistant store manager (asm)', 'acting store manager')
        or lower(trim(pos.name)) like '%assistant store manager%'
      )
        and aa.is_active = true
        and aa.effective_from <= current_date
        and (aa.effective_to is null or aa.effective_to >= current_date)
        and aa.employee_id <> p_requester_employee_id
        and not (aa.employee_id = any(p_used_employee_ids))
        and (
          coalesce(aa.store_id, ea.store_id) = v_assignment.store_id
          or exists (
            select 1 from public.employee_store_assignments esa
            where esa.employee_id = aa.employee_id
              and esa.store_id = v_assignment.store_id
          )
        )
        and exists (
          select 1 from public.employees e
          left join public.user_profiles up2 on up2.employee_id = e.id
          left join auth.users au on au.id = up2.auth_user_id
          where e.id = aa.employee_id
            and lower(trim(coalesce(e.employment_status, 'active'))) not in ('banned', 'inactive', 'terminated', 'resigned')
            and coalesce(up2.is_active, true) = true
            and (au.banned_until is null or au.banned_until <= now())
        )
      order by
        case when ea.department_id = v_assignment.department_id then 0 else 1 end,
        case when coalesce(aa.store_id, ea.store_id) = v_assignment.store_id then 0 else 1 end,
        aa.created_at asc
      limit 1;

      -- 2. If not found in authority_assignments, check employee_assignments directly
      if approver_employee_id is null then
        select ea.employee_id, up.id
        into approver_employee_id, approver_user_profile_id
        from public.employee_assignments ea
        join public.positions pos on pos.id = ea.position_id
        left join public.user_profiles up on up.employee_id = ea.employee_id
        where (
          lower(trim(pos.name)) in ('assistant store manager', 'assistant store manager (asm)', 'acting store manager')
          or lower(trim(pos.name)) like '%assistant store manager%'
        )
          and ea.employee_id <> p_requester_employee_id
          and not (ea.employee_id = any(p_used_employee_ids))
          and ea.is_primary = true
          and ea.effective_from <= current_date
          and (ea.effective_to is null or ea.effective_to >= current_date)
          and (
            ea.store_id = v_assignment.store_id
            or exists (
              select 1 from public.employee_store_assignments esa
              where esa.employee_id = ea.employee_id
                and esa.store_id = v_assignment.store_id
            )
          )
          and exists (
            select 1 from public.employees e
            left join public.user_profiles up2 on up2.employee_id = e.id
            left join auth.users au on au.id = up2.auth_user_id
            where e.id = ea.employee_id
              and lower(trim(coalesce(e.employment_status, 'active'))) not in ('banned', 'inactive', 'terminated', 'resigned')
              and coalesce(up2.is_active, true) = true
              and (au.banned_until is null or au.banned_until <= now())
          )
        order by
          case when ea.department_id = v_assignment.department_id then 0 else 1 end,
          case when ea.store_id = v_assignment.store_id then 0 else 1 end,
          ea.created_at asc
        limit 1;
      end if;

      if approver_employee_id is not null then
        resolved_level := v_level;
        return next;
        return;
      end if;
    end if;

  end loop;
end;
$$;

grant execute on function public.find_request_approver(uuid, uuid, int, uuid, uuid[]) to authenticated, anon, service_role;


-- ============================================================================
-- 2. Update public.get_store_approval_route
-- ============================================================================
drop function if exists public.get_store_approval_route(uuid, uuid);
drop function if exists public.get_store_approval_route(text, text);
drop function if exists public.get_store_approval_route(uuid);
drop function if exists public.get_store_approval_route(text);
drop function if exists public.get_store_approval_route();

create or replace function public.get_store_approval_route(
  p_store_id text default null,
  p_employee_id text default null
)
returns table (
  step_order int,
  required_level int,
  approver_level int,
  position_level int,
  role_name text,
  approver_employee_id uuid,
  approver_name text,
  approver_position_name text,
  approver_employee_no text,
  status text,
  store_id uuid,
  store_name text,
  is_reassigned boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee_id uuid;
  v_duty_store_id uuid;
  v_assignment public.employee_assignments;
  v_position public.positions;
  v_route record;
  v_step_order int := 0;
  v_used_employee_ids uuid[] := '{}';
  v_step_approver_emp_id uuid;
  v_step_resolved_level int;
  v_step_approver_name text;
  v_step_approver_pos_name text;
  v_step_approver_emp_no text;
  v_step_approver_level int;
  v_fallback_lvl int;
begin
  -- 1. Identify requester employee (supports UUID or employee_no)
  if p_employee_id is not null and trim(p_employee_id) <> '' and trim(p_employee_id) <> 'N/A' then
    if trim(p_employee_id) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      v_employee_id := trim(p_employee_id)::uuid;
    else
      select e.id into v_employee_id
      from public.employees e
      where lower(trim(e.employee_no)) = lower(trim(p_employee_id))
      limit 1;
    end if;
  end if;

  if v_employee_id is null and auth.uid() is not null then
    select up.employee_id into v_employee_id
    from public.user_profiles up
    where up.auth_user_id = auth.uid()
    limit 1;
  end if;

  if v_employee_id is null then
    return;
  end if;

  -- 2. Identify requester assignment
  select *
  into v_assignment
  from public.employee_assignments
  where employee_id = v_employee_id
    and is_primary = true
    and effective_from <= current_date
    and (effective_to is null or effective_to >= current_date)
  order by effective_from desc
  limit 1;

  if v_assignment.id is null then
    select *
    into v_assignment
    from public.employee_assignments
    where employee_id = v_employee_id
    order by is_primary desc, effective_from desc
    limit 1;
  end if;

  if v_assignment.id is null then
    return;
  end if;

  -- Adjust for store if specific duty store is provided (supports UUID or store name)
  if p_store_id is not null and trim(p_store_id) <> '' and trim(p_store_id) <> 'N/A' then
    if trim(p_store_id) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      v_duty_store_id := trim(p_store_id)::uuid;
    else
      select s.id into v_duty_store_id
      from public.stores s
      where lower(trim(s.name)) = lower(trim(p_store_id))
      limit 1;
    end if;

    if v_duty_store_id is not null then
      v_assignment.store_id := v_duty_store_id;
      select s.cluster_id, coalesce(s.area_id, cl.area_id, v_assignment.area_id)
      into v_assignment.cluster_id, v_assignment.area_id
      from public.stores s
      left join public.clusters cl on cl.id = s.cluster_id
      where s.id = v_duty_store_id;
    end if;
  end if;

  -- Resolve cluster and area for employee assignment
  if v_assignment.store_id is not null and v_assignment.area_id is null then
    select coalesce(s.area_id, cl.area_id, v_assignment.area_id), coalesce(s.cluster_id, v_assignment.cluster_id)
    into v_assignment.area_id, v_assignment.cluster_id
    from public.stores s
    left join public.clusters cl on cl.id = s.cluster_id
    where s.id = v_assignment.store_id;
  elsif v_assignment.cluster_id is not null and v_assignment.area_id is null then
    select coalesce(cl.area_id, v_assignment.area_id)
    into v_assignment.area_id
    from public.clusters cl
    where cl.id = v_assignment.cluster_id;
  end if;

  if v_assignment.area_id is null then
    select aa.area_id
    into v_assignment.area_id
    from public.authority_assignments aa
    where aa.employee_id = v_assignment.employee_id
      and aa.area_id is not null
      and aa.is_active = true
      and aa.effective_from <= current_date
      and (aa.effective_to is null or aa.effective_to >= current_date)
    order by aa.created_at desc
    limit 1;
  end if;

  if v_assignment.cluster_id is null then
    select aa.cluster_id
    into v_assignment.cluster_id
    from public.authority_assignments aa
    where aa.employee_id = v_assignment.employee_id
      and aa.cluster_id is not null
      and aa.is_active = true
      and aa.effective_from <= current_date
      and (aa.effective_to is null or aa.effective_to >= current_date)
    order by aa.created_at desc
    limit 1;
  end if;

  select *
  into v_position
  from public.positions
  where id = v_assignment.position_id;

  -- 3. Query approval routes matching employee's requester level and department
  for v_route in
    select distinct on (alr.step_order) alr.*
    from public.approval_level_routes alr
    where alr.requester_level = coalesce(v_position.authority_level, 1)
      and (alr.department_id = v_assignment.department_id or alr.department_id is null)
    order by
      alr.step_order asc,
      case when alr.department_id = v_assignment.department_id then 0 else 1 end
    limit 2
  loop
    v_step_order := v_step_order + 1;
    v_step_approver_emp_id := null;
    v_step_resolved_level := null;

    select
      (to_jsonb(fa)->>'approver_employee_id')::uuid,
      coalesce((to_jsonb(fa)->>'resolved_level')::integer, v_route.approver_level)
    into
      v_step_approver_emp_id,
      v_step_resolved_level
    from public.find_request_approver(
      v_assignment.id,
      v_assignment.function_id,
      v_route.approver_level,
      v_employee_id,
      v_used_employee_ids
    ) fa
    limit 1;

    if v_step_approver_emp_id is not null then
      v_used_employee_ids := array_append(v_used_employee_ids, v_step_approver_emp_id);

      select
        nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), ''),
        e.employee_no,
        p.name,
        coalesce(p.authority_level, v_step_resolved_level)
      into
        v_step_approver_name,
        v_step_approver_emp_no,
        v_step_approver_pos_name,
        v_step_approver_level
      from public.employees e
      left join public.employee_assignments ea on ea.employee_id = e.id and ea.is_primary = true
      left join public.positions p on p.id = ea.position_id
      where e.id = v_step_approver_emp_id
      limit 1;

      step_order := v_step_order;
      required_level := coalesce(v_step_resolved_level, v_route.approver_level);
      approver_level := coalesce(v_step_approver_level, v_step_resolved_level, v_route.approver_level);
      position_level := coalesce(v_step_approver_level, v_step_resolved_level, v_route.approver_level);
      role_name := coalesce(v_step_approver_pos_name, 'Approver');
      approver_employee_id := v_step_approver_emp_id;
      approver_name := coalesce(v_step_approver_name, v_step_approver_pos_name, 'Approver');
      approver_position_name := v_step_approver_pos_name;
      approver_employee_no := v_step_approver_emp_no;
      status := case when v_step_order = 1 then 'Pending to approve' else 'Not yet processed' end;
      store_id := v_assignment.store_id;
      store_name := (select name from public.stores where id = v_assignment.store_id limit 1);
      is_reassigned := false;

      return next;
    else
      -- If no active employee resolved for route step, provide route position title
      select p.name into v_step_approver_pos_name
      from public.positions p
      where p.id = v_route.approver_position_id;

      if v_step_approver_pos_name is null then
        v_step_approver_pos_name := case v_route.approver_level
          when 2 then 'Store Manager / Supervisor'
          when 3 then 'Department Supervisor'
          when 4 then 'Cluster Manager'
          when 5 then 'Area Operations Manager'
          when 7 then 'Operations Head / Director'
          when 8 then 'General Manager'
          else 'Approver'
        end;
      end if;

      step_order := v_step_order;
      required_level := v_route.approver_level;
      approver_level := v_route.approver_level;
      position_level := v_route.approver_level;
      role_name := v_step_approver_pos_name;
      approver_employee_id := null;
      approver_name := v_step_approver_pos_name;
      approver_position_name := v_step_approver_pos_name;
      approver_employee_no := null;
      status := case when v_step_order = 1 then 'Pending to approve' else 'Not yet processed' end;
      store_id := v_assignment.store_id;
      store_name := (select name from public.stores where id = v_assignment.store_id limit 1);
      is_reassigned := false;

      return next;
    end if;
  end loop;

  -- 4. Fallback ladder if no route was defined in approval_level_routes
  if v_step_order = 0 then
    for v_fallback_lvl in select unnest(array[
      greatest(2, coalesce(v_position.authority_level, 1) + 1),
      greatest(5, coalesce(v_position.authority_level, 1) + 2)
    ]) loop
      v_step_order := v_step_order + 1;
      v_step_approver_emp_id := null;
      v_step_resolved_level := null;

      select
        (to_jsonb(fa)->>'approver_employee_id')::uuid,
        coalesce((to_jsonb(fa)->>'resolved_level')::integer, v_fallback_lvl)
      into
        v_step_approver_emp_id,
        v_step_resolved_level
      from public.find_request_approver(
        v_assignment.id,
        v_assignment.function_id,
        v_fallback_lvl,
        v_employee_id,
        v_used_employee_ids
      ) fa
      limit 1;

      if v_step_approver_emp_id is not null then
        v_used_employee_ids := array_append(v_used_employee_ids, v_step_approver_emp_id);

        select
          nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), ''),
          e.employee_no,
          p.name,
          coalesce(p.authority_level, v_step_resolved_level)
        into
          v_step_approver_name,
          v_step_approver_emp_no,
          v_step_approver_pos_name,
          v_step_approver_level
        from public.employees e
        left join public.employee_assignments ea on ea.employee_id = e.id and ea.is_primary = true
        left join public.positions p on p.id = ea.position_id
        where e.id = v_step_approver_emp_id
        limit 1;

        step_order := v_step_order;
        required_level := coalesce(v_step_resolved_level, v_fallback_lvl);
        approver_level := coalesce(v_step_approver_level, v_step_resolved_level, v_fallback_lvl);
        position_level := coalesce(v_step_approver_level, v_step_resolved_level, v_fallback_lvl);
        role_name := coalesce(v_step_approver_pos_name, 'Approver');
        approver_employee_id := v_step_approver_emp_id;
        approver_name := coalesce(v_step_approver_name, v_step_approver_pos_name, 'Approver');
        approver_position_name := v_step_approver_pos_name;
        approver_employee_no := v_step_approver_emp_no;
        status := case when v_step_order = 1 then 'Pending to approve' else 'Not yet processed' end;
        store_id := v_assignment.store_id;
        store_name := (select name from public.stores where id = v_assignment.store_id limit 1);
        is_reassigned := false;

        return next;
      end if;
    end loop;
  end if;

  return;
end;
$$;

create or replace function public.get_store_approval_route(
  p_store_id uuid,
  p_employee_id uuid default null
)
returns table (
  step_order int,
  required_level int,
  approver_level int,
  position_level int,
  role_name text,
  approver_employee_id uuid,
  approver_name text,
  approver_position_name text,
  approver_employee_no text,
  status text,
  store_id uuid,
  store_name text,
  is_reassigned boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query select * from public.get_store_approval_route(p_store_id::text, p_employee_id::text);
end;
$$;

grant execute on function public.get_store_approval_route(text, text) to authenticated, anon, service_role;
grant execute on function public.get_store_approval_route(uuid, uuid) to authenticated, anon, service_role;


-- ============================================================================
-- 3. Update public.hr_admin_store_route_scopes
-- ============================================================================
drop function if exists public.hr_admin_store_route_scopes(text, text);
drop function if exists public.hr_admin_store_route_scopes();

create or replace function public.hr_admin_store_route_scopes(
  p_username text default null,
  p_password text default null
)
returns table (
  department_id uuid,
  department_name text,
  store_id uuid,
  store_name text,
  area_id uuid,
  area_name text,
  cluster_id uuid,
  cluster_name text,
  route_approvers jsonb
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.hr_admin_has_access(p_username, p_password) then
    raise exception 'Admin access is required.';
  end if;

  return query
  with store_scopes as (
    select distinct
      d.id as department_id,
      d.name as department_name,
      s.id as store_id,
      s.name as store_name,
      s.company_id,
      coalesce(s.area_id, cl.area_id) as area_id,
      coalesce(a.name, cluster_area.name, 'N/A') as area_name,
      s.cluster_id,
      coalesce(cl.name, 'N/A') as cluster_name
    from public.departments d
    cross join public.stores s
    left join public.clusters cl on cl.id = s.cluster_id
    left join public.areas a on a.id = s.area_id
    left join public.areas cluster_area on cluster_area.id = cl.area_id
    where d.is_active = true
      and s.is_active = true
      and exists (
        select 1 from public.department_approval_ladders dal
        where dal.department_id = d.id
          and dal.authority_level = 2
      )
      and (
        exists (
          select 1 from public.employee_assignments ea
          where ea.department_id = d.id and ea.store_id = s.id and ea.is_primary = true and ea.effective_to is null
        )
        or exists (
          select 1 from public.employee_store_assignments esa
          join public.employee_assignments ea on ea.employee_id = esa.employee_id
          where ea.department_id = d.id and esa.store_id = s.id
        )
      )
  )
  select
    scope.department_id,
    scope.department_name,
    scope.store_id,
    scope.store_name,
    scope.area_id,
    scope.area_name,
    scope.cluster_id,
    scope.cluster_name,
    coalesce((
      select jsonb_object_agg(level_approvers.level_key, level_approvers.names)
      from (
        select
          l.authority_level::text as level_key,
          coalesce(
            (
              select jsonb_agg(named_approvers.full_name order by named_approvers.full_name)
              from (
                select distinct
                  upper(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix))) as full_name
                from public.employees e
                join lateral (
                  select *
                  from public.employee_assignments employee_scope
                  where employee_scope.employee_id = e.id
                    and employee_scope.is_primary = true
                    and employee_scope.effective_to is null
                  order by employee_scope.created_at desc
                  limit 1
                ) ea on true
                join public.positions p on p.id = ea.position_id
                left join public.stores employee_store on employee_store.id = ea.store_id
                left join public.clusters employee_cluster
                  on employee_cluster.id = coalesce(ea.cluster_id, employee_store.cluster_id)
                left join lateral (
                  select current_aa.*
                  from public.authority_assignments current_aa
                  where current_aa.employee_id = e.id
                    and current_aa.function_id = ea.function_id
                    and current_aa.is_active = true
                    and current_aa.effective_from <= current_date
                    and (current_aa.effective_to is null or current_aa.effective_to >= current_date)
                  order by current_aa.created_at desc
                  limit 1
                ) aa on true
                where e.employment_status = 'active'
                  and coalesce(aa.authority_level, p.authority_level, 1) = l.authority_level
                  and (
                    l.approver_position_id is null
                    or ea.position_id = l.approver_position_id
                  )
                  and (
                    (
                      l.authority_level = 2 and (
                        coalesce(ea.store_id, aa.store_id) = scope.store_id
                        or exists (
                          select 1 from public.employee_store_assignments esa
                          where esa.employee_id = e.id
                            and esa.store_id = scope.store_id
                        )
                      )
                    )
                    or (
                      l.authority_level = 4
                      and scope.cluster_id is not null
                      and coalesce(ea.cluster_id, employee_store.cluster_id, aa.cluster_id) = scope.cluster_id
                    )
                    or (
                      l.authority_level = 5
                      and scope.area_id is not null
                      and coalesce(ea.area_id, employee_store.area_id, employee_cluster.area_id, aa.area_id) = scope.area_id
                    )
                    or (
                      l.authority_level not in (2, 4, 5)
                      and coalesce(ea.company_id, aa.company_id) = scope.company_id
                    )
                  )
              ) named_approvers
            ),
            -- Level 2 Fallback: If no Store Manager is assigned to this store,
            -- reflect Assistant Store Manager(s) tagged with (ASM)
            case when l.authority_level = 2 then (
              select jsonb_agg(asm_approvers.full_name order by asm_approvers.full_name)
              from (
                select distinct
                  upper(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix))) || ' (ASM)' as full_name
                from public.employees e
                join lateral (
                  select *
                  from public.employee_assignments employee_scope
                  where employee_scope.employee_id = e.id
                    and employee_scope.is_primary = true
                    and employee_scope.effective_to is null
                  order by employee_scope.created_at desc
                  limit 1
                ) ea on true
                join public.positions p on p.id = ea.position_id
                left join lateral (
                  select current_aa.*
                  from public.authority_assignments current_aa
                  where current_aa.employee_id = e.id
                    and current_aa.function_id = ea.function_id
                    and current_aa.is_active = true
                    and current_aa.effective_from <= current_date
                    and (current_aa.effective_to is null or current_aa.effective_to >= current_date)
                  order by current_aa.created_at desc
                  limit 1
                ) aa on true
                where e.employment_status = 'active'
                  and (
                    lower(trim(p.name)) in ('assistant store manager', 'assistant store manager (asm)', 'acting store manager')
                    or lower(trim(p.name)) like '%assistant store manager%'
                  )
                  and (
                    coalesce(ea.store_id, aa.store_id) = scope.store_id
                    or exists (
                      select 1 from public.employee_store_assignments esa
                      where esa.employee_id = e.id
                        and esa.store_id = scope.store_id
                    )
                  )
              ) asm_approvers
            ) else null end,
            '[]'::jsonb
          ) as names
        from public.department_approval_ladders l
        where l.department_id = scope.department_id
          and l.authority_level > 1
      ) level_approvers
    ), '{}'::jsonb) as route_approvers
  from store_scopes scope
  order by scope.department_name, scope.store_name;
end;
$$;

grant execute on function public.hr_admin_store_route_scopes(text, text) to anon, authenticated;


-- ============================================================================
-- 4. Update public.submit_time_request to populate approver details
-- ============================================================================
create or replace function public.submit_time_request(
  p_request_type_code text,
  p_date_from date,
  p_date_to date,
  p_time_from time,
  p_time_to time,
  p_total_hours numeric,
  p_reason text,
  p_time_schedule text,
  p_day_off text,
  p_payroll_class text,
  p_transaction_type text default null,
  p_store_id uuid default null,
  p_custom_approvers jsonb default null,
  p_is_pre_approved boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_assignment public.employee_assignments;
  v_request_type public.request_types;
  v_position public.positions;
  v_request_id uuid;
  v_route record;
  v_used_employee_ids uuid[] := '{}';
  v_step_order int := 0;
  v_step_approver_emp_id uuid;
  v_step_approver_user_id uuid;
  v_step_resolved_level int;
  v_step_approver_name text;
  v_step_approver_pos_name text;
  v_step_approver_emp_no text;
  v_balance numeric(10, 2);
  v_new_balance numeric(10, 2);
  v_is_use_offset boolean := false;
  v_is_scheduled_ot boolean := false;
  v_trans_lower text;
  v_effective_hours numeric;
  v_initial_status text;
  v_transaction_type text;
  v_custom_app_elem jsonb;
  v_custom_matched boolean;
  v_step1_emp_id uuid;
  v_step1_user_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  if v_profile.employee_id is null then
    raise exception 'User profile not found.';
  end if;

  v_trans_lower := lower(coalesce(p_transaction_type, ''));
  v_is_use_offset := v_trans_lower like '%use_offset%' or v_trans_lower like '%offset_leave%' or lower(coalesce(p_request_type_code, '')) = 'use_offset';

  if v_is_use_offset then
    select *
    into v_request_type
    from public.request_types
    where code = 'use_offset'
      and is_active = true
    limit 1;
  end if;

  if v_request_type.id is null then
    select *
    into v_request_type
    from public.request_types
    where code = p_request_type_code
      and is_active = true
    limit 1;
  end if;

  if v_request_type.id is null then
    select *
    into v_request_type
    from public.request_types
    where code = p_request_type_code
    limit 1;
  end if;

  if v_request_type.id is null and v_is_use_offset then
    select *
    into v_request_type
    from public.request_types
    where code in ('time', 'esarf', 'offset')
      and is_active = true
    order by case when code = 'offset' then 0 when code = 'use_offset' then 1 else 2 end
    limit 1;
  end if;

  if v_request_type.id is null then
    select *
    into v_request_type
    from public.request_types
    where is_active = true
    order by created_at asc
    limit 1;
  end if;

  if v_request_type.id is null then
    raise exception 'Request type not configured.';
  end if;

  select *
  into v_assignment
  from public.employee_assignments
  where employee_id = v_profile.employee_id
    and is_primary = true
    and effective_from <= current_date
    and (effective_to is null or effective_to >= current_date)
  order by effective_from desc
  limit 1;

  if v_assignment.id is null then
    select *
    into v_assignment
    from public.employee_assignments
    where employee_id = v_profile.employee_id
    order by is_primary desc, effective_from desc
    limit 1;
  end if;

  if v_assignment.id is null then
    raise exception 'Active employee assignment not found.';
  end if;

  -- Use specific store if supplied
  if p_store_id is not null then
    v_assignment.store_id := p_store_id;
  end if;

  -- Resolve cluster and area for employee assignment
  if v_assignment.store_id is not null then
    select
      coalesce(s.area_id, cl.area_id, v_assignment.area_id),
      coalesce(s.cluster_id, v_assignment.cluster_id)
    into v_assignment.area_id, v_assignment.cluster_id
    from public.stores s
    left join public.clusters cl on cl.id = s.cluster_id
    where s.id = v_assignment.store_id;
  elsif v_assignment.cluster_id is not null then
    select coalesce(cl.area_id, v_assignment.area_id)
    into v_assignment.area_id
    from public.clusters cl
    where cl.id = v_assignment.cluster_id;
  end if;

  if v_assignment.area_id is null then
    select aa.area_id
    into v_assignment.area_id
    from public.authority_assignments aa
    where aa.employee_id = v_assignment.employee_id
      and aa.area_id is not null
      and aa.is_active = true
      and aa.effective_from <= current_date
      and (aa.effective_to is null or aa.effective_to >= current_date)
    order by aa.created_at desc
    limit 1;
  end if;

  if v_assignment.cluster_id is null then
    select aa.cluster_id
    into v_assignment.cluster_id
    from public.authority_assignments aa
    where aa.employee_id = v_assignment.employee_id
      and aa.cluster_id is not null
      and aa.is_active = true
      and aa.effective_from <= current_date
      and (aa.effective_to is null or aa.effective_to >= current_date)
    order by aa.created_at desc
    limit 1;
  end if;

  select *
  into v_position
  from public.positions
  where id = v_assignment.position_id;

  v_is_scheduled_ot := (
    coalesce(p_is_pre_approved, false) = true
    or lower(coalesce(p_transaction_type, '')) like '%scheduled_ot%'
    or coalesce(p_reason, '') like '%[PreApproved]%'
  ) and not v_is_use_offset;

  v_transaction_type := coalesce(nullif(trim(p_transaction_type), ''), case when p_request_type_code = 'offset_earn' then 'Offset' else 'OT' end);
  v_transaction_type := trim(both ', ' from replace(replace(v_transaction_type, 'scheduled_ot,', ''), ', scheduled_ot', ''));
  v_transaction_type := replace(v_transaction_type, 'scheduled_ot', '');
  v_transaction_type := nullif(trim(v_transaction_type), '');
  v_transaction_type := coalesce(v_transaction_type, case when p_request_type_code = 'offset_earn' then 'Offset' else 'OT' end);

  if v_is_scheduled_ot then
    v_initial_status := 'pre_approved';
  else
    v_initial_status := 'pending';
  end if;

  insert into public.offset_balances (employee_id, balance_hours, updated_at)
  values (v_profile.employee_id, 0, now())
  on conflict (employee_id) do nothing;

  if v_is_use_offset then
    if coalesce(p_total_hours, 0) <= 0 then
      raise exception 'Total hours must be greater than zero for Use Offset.';
    end if;

    select coalesce(balance_hours, 0)
    into v_balance
    from public.offset_balances
    where employee_id = v_profile.employee_id
    for update;

    if coalesce(v_balance, 0) < p_total_hours then
      raise exception 'Insufficient offset balance (available: % hrs, requested: % hrs).',
        coalesce(v_balance, 0), p_total_hours;
    end if;

    v_new_balance := round(coalesce(v_balance, 0) - p_total_hours, 2);

    update public.offset_balances
    set balance_hours = v_new_balance,
        updated_at = now()
    where employee_id = v_profile.employee_id;
  end if;

  if v_is_scheduled_ot then
    v_effective_hours := 0;
  else
    v_effective_hours := p_total_hours;
  end if;

  insert into public.requests (
    request_type_id,
    submitted_by_employee_id,
    submitted_by_user_id,
    company_id,
    department_id,
    area_id,
    cluster_id,
    store_id,
    requester_position_id,
    requester_level,
    status
  )
  values (
    v_request_type.id,
    v_profile.employee_id,
    v_profile.id,
    v_assignment.company_id,
    v_assignment.department_id,
    v_assignment.area_id,
    v_assignment.cluster_id,
    coalesce(p_store_id, v_assignment.store_id),
    v_assignment.position_id,
    coalesce(v_position.authority_level, 1),
    v_initial_status
  )
  returning id into v_request_id;

  insert into public.time_request_details (
    request_id,
    date_from,
    date_to,
    time_from,
    time_to,
    total_hours,
    reason,
    time_schedule,
    day_off,
    payroll_class,
    transaction_type
  )
  values (
    v_request_id,
    p_date_from,
    p_date_to,
    p_time_from,
    p_time_to,
    v_effective_hours,
    p_reason,
    p_time_schedule,
    p_day_off,
    p_payroll_class,
    v_transaction_type
  );

  if v_is_use_offset then
    insert into public.offset_transactions (
      employee_id,
      request_id,
      transaction_type,
      hours,
      balance_after,
      created_at
    )
    values (
      v_profile.employee_id,
      v_request_id,
      'use',
      p_total_hours,
      v_new_balance,
      now()
    );
  end if;

  -- Build approval routes
  for v_route in
    select distinct on (step_order) *
    from public.approval_level_routes
    where requester_level = v_position.authority_level
      and (department_id = v_assignment.department_id or department_id is null)
    order by
      step_order asc,
      case when department_id = v_assignment.department_id then 0 else 1 end
    limit coalesce(v_request_type.approval_count, 2)
  loop
    v_step_order := v_step_order + 1;
    v_custom_matched := false;
    v_step_approver_emp_id := null;
    v_step_approver_user_id := null;
    v_step_resolved_level := null;
    v_step_approver_name := null;
    v_step_approver_pos_name := null;
    v_step_approver_emp_no := null;

    -- Check if custom/reassigned approver was provided for this step
    if p_custom_approvers is not null and jsonb_typeof(p_custom_approvers) = 'array' then
      for v_custom_app_elem in select * from jsonb_array_elements(p_custom_approvers) loop
        if (v_custom_app_elem->>'step_order')::int = v_step_order
           and nullif(trim(v_custom_app_elem->>'approver_employee_id'), '') is not null then
          v_step_approver_emp_id := (v_custom_app_elem->>'approver_employee_id')::uuid;
          select up.id into v_step_approver_user_id
          from public.user_profiles up
          where up.employee_id = v_step_approver_emp_id
          limit 1;
          v_step_resolved_level := coalesce((v_custom_app_elem->>'approver_level')::int, v_route.approver_level);
          v_custom_matched := true;
          exit;
        end if;
      end loop;
    end if;

    if v_custom_matched and v_step_approver_emp_id is not null then
      select
        nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), ''),
        e.employee_no,
        p.name
      into
        v_step_approver_name,
        v_step_approver_emp_no,
        v_step_approver_pos_name
      from public.employees e
      left join public.employee_assignments ea on ea.employee_id = e.id and ea.is_primary = true
      left join public.positions p on p.id = ea.position_id
      where e.id = v_step_approver_emp_id
      limit 1;

      insert into public.request_approval_steps (
        request_id,
        step_order,
        required_function_id,
        required_level,
        assigned_approver_employee_id,
        assigned_approver_user_id,
        status,
        approver_name,
        approver_position_name,
        approver_employee_no,
        is_reassigned
      )
      values (
        v_request_id,
        v_step_order,
        v_assignment.function_id,
        coalesce(v_step_resolved_level, v_route.approver_level),
        v_step_approver_emp_id,
        v_step_approver_user_id,
        case when v_step_order = 1 then 'pending' else 'waiting' end,
        v_step_approver_name,
        v_step_approver_pos_name,
        v_step_approver_emp_no,
        true
      );
      v_used_employee_ids := array_append(v_used_employee_ids, v_step_approver_emp_id);
    else
      -- Standard approver resolution
      select
        (to_jsonb(fa)->>'approver_employee_id')::uuid,
        coalesce(
          (to_jsonb(fa)->>'approver_user_profile_id')::uuid,
          (to_jsonb(fa)->>'approver_user_id')::uuid,
          (select id from public.user_profiles where employee_id = (to_jsonb(fa)->>'approver_employee_id')::uuid limit 1)
        ),
        coalesce((to_jsonb(fa)->>'resolved_level')::integer, v_route.approver_level)
      into
        v_step_approver_emp_id,
        v_step_approver_user_id,
        v_step_resolved_level
      from public.find_request_approver(
        v_assignment.id,
        v_assignment.function_id,
        v_route.approver_level,
        v_profile.employee_id,
        v_used_employee_ids
      ) fa
      limit 1;

      if v_step_approver_emp_id is not null then
        select
          nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), ''),
          e.employee_no,
          p.name
        into
          v_step_approver_name,
          v_step_approver_emp_no,
          v_step_approver_pos_name
        from public.employees e
        left join public.employee_assignments ea on ea.employee_id = e.id and ea.is_primary = true
        left join public.positions p on p.id = ea.position_id
        where e.id = v_step_approver_emp_id
        limit 1;

        insert into public.request_approval_steps (
          request_id,
          step_order,
          required_function_id,
          required_level,
          assigned_approver_employee_id,
          assigned_approver_user_id,
          status,
          approver_name,
          approver_position_name,
          approver_employee_no,
          is_reassigned
        )
        values (
          v_request_id,
          v_step_order,
          v_assignment.function_id,
          coalesce(v_step_resolved_level, v_route.approver_level),
          v_step_approver_emp_id,
          v_step_approver_user_id,
          case when v_step_order = 1 then 'pending' else 'waiting' end,
          v_step_approver_name,
          v_step_approver_pos_name,
          v_step_approver_emp_no,
          false
        );

        v_used_employee_ids := array_append(v_used_employee_ids, v_step_approver_emp_id);
      end if;
    end if;
  end loop;

  -- Fallback if no steps were inserted
  if v_step_order = 0 then
    select
      (to_jsonb(fa)->>'approver_employee_id')::uuid,
      coalesce(
        (to_jsonb(fa)->>'approver_user_profile_id')::uuid,
        (to_jsonb(fa)->>'approver_user_id')::uuid,
        (select id from public.user_profiles where employee_id = (to_jsonb(fa)->>'approver_employee_id')::uuid limit 1)
      ),
      coalesce((to_jsonb(fa)->>'resolved_level')::integer, 2)
    into
      v_step_approver_emp_id,
      v_step_approver_user_id,
      v_step_resolved_level
    from public.find_request_approver(
      v_assignment.id,
      v_assignment.function_id,
      greatest(2, coalesce(v_position.authority_level, 1) + 1),
      v_profile.employee_id,
      v_used_employee_ids
    ) fa
    limit 1;

    if v_step_approver_emp_id is not null then
      select
        nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), ''),
        e.employee_no,
        p.name
      into
        v_step_approver_name,
        v_step_approver_emp_no,
        v_step_approver_pos_name
      from public.employees e
      left join public.employee_assignments ea on ea.employee_id = e.id and ea.is_primary = true
      left join public.positions p on p.id = ea.position_id
      where e.id = v_step_approver_emp_id
      limit 1;

      insert into public.request_approval_steps (
        request_id,
        step_order,
        required_function_id,
        required_level,
        assigned_approver_employee_id,
        assigned_approver_user_id,
        status,
        approver_name,
        approver_position_name,
        approver_employee_no,
        is_reassigned
      )
      values (
        v_request_id,
        1,
        v_assignment.function_id,
        coalesce(v_step_resolved_level, 2),
        v_step_approver_emp_id,
        v_step_approver_user_id,
        'pending',
        v_step_approver_name,
        v_step_approver_pos_name,
        v_step_approver_emp_no,
        false
      );
    end if;
  end if;

  -- Send notification to Step 1 Approver if user account exists
  select assigned_approver_employee_id, assigned_approver_user_id
  into v_step1_emp_id, v_step1_user_id
  from public.request_approval_steps
  where request_id = v_request_id and step_order = 1;

  if v_step1_emp_id is not null then
    insert into public.notifications (
      employee_id,
      user_profile_id,
      title,
      message,
      link_type,
      link_id
    )
    values (
      v_step1_emp_id,
      v_step1_user_id,
      'Time/Offset Request Pending Approval',
      coalesce(
        (select trim(concat_ws(' ', first_name, last_name)) from public.employees where id = v_profile.employee_id),
        'An employee'
      ) || ' submitted a time request.',
      'approval',
      v_request_id
    );
  end if;

  return v_request_id;
end;
$$;

grant execute on function public.submit_time_request(
  text, date, date, time, time, numeric, text, text, text, text, text, uuid, jsonb, boolean
) to authenticated, anon, service_role;


-- ============================================================================
-- 5. Update public.submit_leave_request to populate approver details
-- ============================================================================
drop function if exists public.submit_leave_request(text, text, date, date, text);
drop function if exists public.submit_leave_request(text, text, date, date, numeric, numeric, text);
drop function if exists public.submit_leave_request(text, date, date, text, text, numeric, numeric, numeric, jsonb);

create or replace function public.submit_leave_request(
  p_leave_type text,
  p_leave_category text,
  p_start_date date,
  p_end_date date,
  p_paid_days numeric,
  p_unpaid_days numeric,
  p_reason text,
  p_total_days numeric default null,
  p_custom_approvers jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_assignment public.employee_assignments;
  v_request_type public.request_types;
  v_position public.positions;
  v_request_id uuid;
  v_route record;
  v_step_order int := 0;
  v_step_approver_emp_id uuid;
  v_step_approver_user_id uuid;
  v_step_resolved_level int;
  v_step_approver_name text;
  v_step_approver_pos_name text;
  v_step_approver_emp_no text;
  v_used_employee_ids uuid[] := '{}';
  v_total_days numeric;
  v_paid_days numeric;
  v_unpaid_days numeric;
  v_available_credits numeric;
  v_custom_app_elem jsonb;
  v_custom_matched boolean;
  v_step1_emp_id uuid;
  v_step1_user_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  if v_profile.employee_id is null then
    raise exception 'User profile not found.';
  end if;

  select *
  into v_request_type
  from public.request_types
  where code in ('leave', 'leave_request')
    and is_active = true
  order by case when code = 'leave' then 0 else 1 end
  limit 1;

  if v_request_type.id is null then
    raise exception 'Leave request type not configured.';
  end if;

  select *
  into v_assignment
  from public.employee_assignments
  where employee_id = v_profile.employee_id
    and is_primary = true
    and effective_from <= current_date
    and (effective_to is null or effective_to >= current_date)
  order by effective_from desc
  limit 1;

  if v_assignment.id is null then
    select *
    into v_assignment
    from public.employee_assignments
    where employee_id = v_profile.employee_id
    order by is_primary desc, effective_from desc
    limit 1;
  end if;

  if v_assignment.id is null then
    raise exception 'Active employee assignment not found.';
  end if;

  -- Resolve cluster and area for employee assignment
  if v_assignment.store_id is not null then
    select
      coalesce(s.area_id, cl.area_id, v_assignment.area_id),
      coalesce(s.cluster_id, v_assignment.cluster_id)
    into v_assignment.area_id, v_assignment.cluster_id
    from public.stores s
    left join public.clusters cl on cl.id = s.cluster_id
    where s.id = v_assignment.store_id;
  elsif v_assignment.cluster_id is not null then
    select coalesce(cl.area_id, v_assignment.area_id)
    into v_assignment.area_id
    from public.clusters cl
    where cl.id = v_assignment.cluster_id;
  end if;

  if v_assignment.area_id is null then
    select aa.area_id
    into v_assignment.area_id
    from public.authority_assignments aa
    where aa.employee_id = v_assignment.employee_id
      and aa.area_id is not null
      and aa.is_active = true
      and aa.effective_from <= current_date
      and (aa.effective_to is null or aa.effective_to >= current_date)
    order by aa.created_at desc
    limit 1;
  end if;

  if v_assignment.cluster_id is null then
    select aa.cluster_id
    into v_assignment.cluster_id
    from public.authority_assignments aa
    where aa.employee_id = v_assignment.employee_id
      and aa.cluster_id is not null
      and aa.is_active = true
      and aa.effective_from <= current_date
      and (aa.effective_to is null or aa.effective_to >= current_date)
    order by aa.created_at desc
    limit 1;
  end if;

  select *
  into v_position
  from public.positions
  where id = v_assignment.position_id;

  v_total_days := coalesce(p_total_days, greatest(1, (p_end_date - p_start_date + 1)));

  -- Check available leave credits if paid leave requested
  if coalesce(p_paid_days, 0) > 0 or lower(coalesce(p_leave_type, '')) like '%paid%' then
    select coalesce(balance_days, 0)
    into v_available_credits
    from public.leave_balances
    where employee_id = v_profile.employee_id
      and lower(trim(leave_type)) = lower(trim(coalesce(p_leave_category, 'vacation_leave')))
    limit 1;

    v_paid_days := least(coalesce(p_paid_days, v_total_days), coalesce(v_available_credits, 0));
    v_unpaid_days := greatest(0, v_total_days - v_paid_days);
  else
    v_paid_days := coalesce(p_paid_days, 0);
    v_unpaid_days := coalesce(p_unpaid_days, v_total_days);
  end if;

  insert into public.requests (
    request_type_id,
    submitted_by_employee_id,
    submitted_by_user_id,
    company_id,
    department_id,
    area_id,
    cluster_id,
    store_id,
    requester_position_id,
    requester_level,
    status
  )
  values (
    v_request_type.id,
    v_profile.employee_id,
    v_profile.id,
    v_assignment.company_id,
    v_assignment.department_id,
    v_assignment.area_id,
    v_assignment.cluster_id,
    v_assignment.store_id,
    v_assignment.position_id,
    coalesce(v_position.authority_level, 1),
    'pending'
  )
  returning id into v_request_id;

  insert into public.leave_request_details (
    request_id,
    leave_type,
    leave_category,
    start_date,
    end_date,
    total_days,
    paid_days,
    unpaid_days,
    reason
  )
  values (
    v_request_id,
    p_leave_type,
    p_leave_category,
    p_start_date,
    p_end_date,
    v_total_days,
    v_paid_days,
    v_unpaid_days,
    p_reason
  );

  -- Build approval routes
  for v_route in
    select distinct on (step_order) *
    from public.approval_level_routes
    where requester_level = v_position.authority_level
      and (department_id = v_assignment.department_id or department_id is null)
    order by
      step_order asc,
      case when department_id = v_assignment.department_id then 0 else 1 end
    limit coalesce(v_request_type.approval_count, 2)
  loop
    v_step_order := v_step_order + 1;
    v_custom_matched := false;
    v_step_approver_emp_id := null;
    v_step_approver_user_id := null;
    v_step_resolved_level := null;
    v_step_approver_name := null;
    v_step_approver_pos_name := null;
    v_step_approver_emp_no := null;

    if p_custom_approvers is not null and jsonb_typeof(p_custom_approvers) = 'array' then
      for v_custom_app_elem in select * from jsonb_array_elements(p_custom_approvers) loop
        if (v_custom_app_elem->>'step_order')::int = v_step_order
           and nullif(trim(v_custom_app_elem->>'approver_employee_id'), '') is not null then
          v_step_approver_emp_id := (v_custom_app_elem->>'approver_employee_id')::uuid;
          select up.id into v_step_approver_user_id
          from public.user_profiles up
          where up.employee_id = v_step_approver_emp_id
          limit 1;
          v_step_resolved_level := coalesce((v_custom_app_elem->>'approver_level')::int, v_route.approver_level);
          v_custom_matched := true;
          exit;
        end if;
      end loop;
    end if;

    if v_custom_matched and v_step_approver_emp_id is not null then
      select
        nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), ''),
        e.employee_no,
        p.name
      into
        v_step_approver_name,
        v_step_approver_emp_no,
        v_step_approver_pos_name
      from public.employees e
      left join public.employee_assignments ea on ea.employee_id = e.id and ea.is_primary = true
      left join public.positions p on p.id = ea.position_id
      where e.id = v_step_approver_emp_id
      limit 1;

      insert into public.request_approval_steps (
        request_id,
        step_order,
        required_function_id,
        required_level,
        assigned_approver_employee_id,
        assigned_approver_user_id,
        status,
        approver_name,
        approver_position_name,
        approver_employee_no,
        is_reassigned
      )
      values (
        v_request_id,
        v_step_order,
        v_assignment.function_id,
        coalesce(v_step_resolved_level, v_route.approver_level),
        v_step_approver_emp_id,
        v_step_approver_user_id,
        case when v_step_order = 1 then 'pending' else 'waiting' end,
        v_step_approver_name,
        v_step_approver_pos_name,
        v_step_approver_emp_no,
        true
      );
      v_used_employee_ids := array_append(v_used_employee_ids, v_step_approver_emp_id);
    else
      -- Standard approver resolution
      select
        (to_jsonb(fa)->>'approver_employee_id')::uuid,
        coalesce(
          (to_jsonb(fa)->>'approver_user_profile_id')::uuid,
          (to_jsonb(fa)->>'approver_user_id')::uuid,
          (select id from public.user_profiles where employee_id = (to_jsonb(fa)->>'approver_employee_id')::uuid limit 1)
        ),
        coalesce((to_jsonb(fa)->>'resolved_level')::integer, v_route.approver_level)
      into
        v_step_approver_emp_id,
        v_step_approver_user_id,
        v_step_resolved_level
      from public.find_request_approver(
        v_assignment.id,
        v_assignment.function_id,
        v_route.approver_level,
        v_profile.employee_id,
        v_used_employee_ids
      ) fa
      limit 1;

      if v_step_approver_emp_id is not null then
        select
          nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), ''),
          e.employee_no,
          p.name
        into
          v_step_approver_name,
          v_step_approver_emp_no,
          v_step_approver_pos_name
        from public.employees e
        left join public.employee_assignments ea on ea.employee_id = e.id and ea.is_primary = true
        left join public.positions p on p.id = ea.position_id
        where e.id = v_step_approver_emp_id
        limit 1;

        insert into public.request_approval_steps (
          request_id,
          step_order,
          required_function_id,
          required_level,
          assigned_approver_employee_id,
          assigned_approver_user_id,
          status,
          approver_name,
          approver_position_name,
          approver_employee_no,
          is_reassigned
        )
        values (
          v_request_id,
          v_step_order,
          v_assignment.function_id,
          coalesce(v_step_resolved_level, v_route.approver_level),
          v_step_approver_emp_id,
          v_step_approver_user_id,
          case when v_step_order = 1 then 'pending' else 'waiting' end,
          v_step_approver_name,
          v_step_approver_pos_name,
          v_step_approver_emp_no,
          false
        );

        v_used_employee_ids := array_append(v_used_employee_ids, v_step_approver_emp_id);
      end if;
    end if;
  end loop;

  -- Fallback if no steps were inserted
  if v_step_order = 0 then
    select
      (to_jsonb(fa)->>'approver_employee_id')::uuid,
      coalesce(
        (to_jsonb(fa)->>'approver_user_profile_id')::uuid,
        (to_jsonb(fa)->>'approver_user_id')::uuid,
        (select id from public.user_profiles where employee_id = (to_jsonb(fa)->>'approver_employee_id')::uuid limit 1)
      ),
      coalesce((to_jsonb(fa)->>'resolved_level')::integer, 2)
    into
      v_step_approver_emp_id,
      v_step_approver_user_id,
      v_step_resolved_level
    from public.find_request_approver(
      v_assignment.id,
      v_assignment.function_id,
      greatest(2, coalesce(v_position.authority_level, 1) + 1),
      v_profile.employee_id,
      v_used_employee_ids
    ) fa
    limit 1;

    if v_step_approver_emp_id is not null then
      select
        nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), ''),
        e.employee_no,
        p.name
      into
        v_step_approver_name,
        v_step_approver_emp_no,
        v_step_approver_pos_name
      from public.employees e
      left join public.employee_assignments ea on ea.employee_id = e.id and ea.is_primary = true
      left join public.positions p on p.id = ea.position_id
      where e.id = v_step_approver_emp_id
      limit 1;

      insert into public.request_approval_steps (
        request_id,
        step_order,
        required_function_id,
        required_level,
        assigned_approver_employee_id,
        assigned_approver_user_id,
        status,
        approver_name,
        approver_position_name,
        approver_employee_no,
        is_reassigned
      )
      values (
        v_request_id,
        1,
        v_assignment.function_id,
        coalesce(v_step_resolved_level, 2),
        v_step_approver_emp_id,
        v_step_approver_user_id,
        'pending',
        v_step_approver_name,
        v_step_approver_pos_name,
        v_step_approver_emp_no,
        false
      );
    end if;
  end if;

  -- Send notification to Step 1 Approver if user account exists
  select assigned_approver_employee_id, assigned_approver_user_id
  into v_step1_emp_id, v_step1_user_id
  from public.request_approval_steps
  where request_id = v_request_id and step_order = 1;

  if v_step1_emp_id is not null then
    insert into public.notifications (
      employee_id,
      user_profile_id,
      title,
      message,
      link_type,
      link_id
    )
    values (
      v_step1_emp_id,
      v_step1_user_id,
      'Leave Request Pending Approval',
      coalesce(
        (select trim(concat_ws(' ', first_name, last_name)) from public.employees where id = v_profile.employee_id),
        'An employee'
      ) || ' submitted a leave request.',
      'approval',
      v_request_id
    );
  end if;

  return v_request_id;
end;
$$;

grant execute on function public.submit_leave_request(
  text, text, date, date, numeric, numeric, text, numeric, jsonb
) to authenticated, anon, service_role;


-- ============================================================================
-- 6. Update public.submit_travel_order_request
-- ============================================================================
create or replace function public.submit_travel_order_request(
  p_destination_stores text[],
  p_departure_date date,
  p_return_date date,
  p_departure_time time default null,
  p_return_time time default null,
  p_transport_mode text default null,
  p_plate_no text default null,
  p_purpose_of_travel text default null,
  p_purpose_details text default null,
  p_transport_budget numeric default 0,
  p_meal_budget numeric default 0,
  p_emergency_budget numeric default 0,
  p_cost_center_code text default null,
  p_charge_to_store text default null,
  p_custom_approvers jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_assignment public.employee_assignments;
  v_position public.positions;
  v_request_type public.request_types;
  v_request_id uuid;
  v_route record;
  v_step_order int := 0;
  v_step_approver_emp_id uuid;
  v_step_approver_user_id uuid;
  v_step_resolved_level int;
  v_step_approver_name text;
  v_step_approver_pos_name text;
  v_step_approver_emp_no text;
  v_used_employee_ids uuid[] := '{}';
  v_total_budget numeric(12, 2);
  v_destinations text;
  v_fallback_lvl int;
  v_custom_app_elem jsonb;
  v_custom_matched boolean;
  v_step1_emp_id uuid;
  v_step1_user_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  if v_profile.employee_id is null then
    raise exception 'User profile not found.';
  end if;

  if p_departure_date is null or p_return_date is null then
    raise exception 'Departure date and return date are required.';
  end if;

  if p_return_date < p_departure_date then
    raise exception 'Return date cannot be earlier than departure date.';
  end if;

  select *
  into v_assignment
  from public.employee_assignments
  where employee_id = v_profile.employee_id
    and is_primary = true
    and effective_from <= current_date
    and (effective_to is null or effective_to >= current_date)
  order by effective_from desc
  limit 1;

  if v_assignment.id is null then
    select *
    into v_assignment
    from public.employee_assignments
    where employee_id = v_profile.employee_id
    order by is_primary desc, effective_from desc
    limit 1;
  end if;

  if v_assignment.id is null then
    raise exception 'Active employee assignment not found.';
  end if;

  if v_assignment.store_id is not null then
    select
      coalesce(s.area_id, cl.area_id, v_assignment.area_id),
      coalesce(s.cluster_id, v_assignment.cluster_id)
    into v_assignment.area_id, v_assignment.cluster_id
    from public.stores s
    left join public.clusters cl on cl.id = s.cluster_id
    where s.id = v_assignment.store_id;
  elsif v_assignment.cluster_id is not null then
    select coalesce(cl.area_id, v_assignment.area_id)
    into v_assignment.area_id
    from public.clusters cl
    where cl.id = v_assignment.cluster_id;
  end if;

  if v_assignment.area_id is null then
    select aa.area_id
    into v_assignment.area_id
    from public.authority_assignments aa
    where aa.employee_id = v_assignment.employee_id
      and aa.area_id is not null
      and aa.is_active = true
      and aa.effective_from <= current_date
      and (aa.effective_to is null or aa.effective_to >= current_date)
    order by aa.created_at desc
    limit 1;
  end if;

  if v_assignment.cluster_id is null then
    select aa.cluster_id
    into v_assignment.cluster_id
    from public.authority_assignments aa
    where aa.employee_id = v_assignment.employee_id
      and aa.cluster_id is not null
      and aa.is_active = true
      and aa.effective_from <= current_date
      and (aa.effective_to is null or aa.effective_to >= current_date)
    order by aa.created_at desc
    limit 1;
  end if;

  select *
  into v_position
  from public.positions
  where id = v_assignment.position_id;

  select *
  into v_request_type
  from public.request_types
  where code = 'travel_order'
    and is_active = true
  limit 1;

  if v_request_type.id is null then
    raise exception 'Travel Order request type is not configured or active.';
  end if;

  v_total_budget := coalesce(p_transport_budget, 0) + coalesce(p_meal_budget, 0) + coalesce(p_emergency_budget, 0);

  if p_destination_stores is not null and array_length(p_destination_stores, 1) > 0 then
    v_destinations := array_to_string(p_destination_stores, ', ');
  else
    v_destinations := coalesce(nullif(trim(p_charge_to_store), ''), 'Official Business');
  end if;

  insert into public.requests (
    request_type_id,
    submitted_by_employee_id,
    submitted_by_user_id,
    company_id,
    department_id,
    area_id,
    cluster_id,
    store_id,
    requester_position_id,
    requester_level,
    status
  )
  values (
    v_request_type.id,
    v_profile.employee_id,
    v_profile.id,
    v_assignment.company_id,
    v_assignment.department_id,
    v_assignment.area_id,
    v_assignment.cluster_id,
    v_assignment.store_id,
    v_assignment.position_id,
    coalesce(v_position.authority_level, 1),
    'pending'
  )
  returning id into v_request_id;

  insert into public.travel_order_request_details (
    request_id,
    destination_stores,
    destinations,
    departure_date,
    return_date,
    departure_time,
    return_time,
    transport_mode,
    plate_no,
    purpose_of_travel,
    purpose_details,
    transport_budget,
    meal_budget,
    emergency_budget,
    total_budget,
    cost_center_code,
    charge_to_store
  )
  values (
    v_request_id,
    coalesce(p_destination_stores, '{}'::text[]),
    v_destinations,
    p_departure_date,
    p_return_date,
    p_departure_time,
    p_return_time,
    nullif(trim(p_transport_mode), ''),
    nullif(trim(p_plate_no), ''),
    nullif(trim(p_purpose_of_travel), ''),
    nullif(trim(p_purpose_details), ''),
    coalesce(p_transport_budget, 0),
    coalesce(p_meal_budget, 0),
    coalesce(p_emergency_budget, 0),
    v_total_budget,
    nullif(trim(p_cost_center_code), ''),
    nullif(trim(p_charge_to_store), '')
  );

  -- Build approval routes
  for v_route in
    select distinct on (alr.step_order) alr.*
    from public.approval_level_routes alr
    where alr.requester_level = coalesce(v_position.authority_level, 1)
      and (alr.department_id = v_assignment.department_id or alr.department_id is null)
    order by
      alr.step_order asc,
      case when alr.department_id = v_assignment.department_id then 0 else 1 end
    limit 2
  loop
    v_step_order := v_step_order + 1;
    v_custom_matched := false;
    v_step_approver_emp_id := null;
    v_step_approver_user_id := null;
    v_step_resolved_level := null;
    v_step_approver_name := null;
    v_step_approver_pos_name := null;
    v_step_approver_emp_no := null;

    if p_custom_approvers is not null and jsonb_typeof(p_custom_approvers) = 'array' then
      for v_custom_app_elem in select * from jsonb_array_elements(p_custom_approvers) loop
        if (v_custom_app_elem->>'step_order')::int = v_step_order
           and nullif(trim(v_custom_app_elem->>'approver_employee_id'), '') is not null then
          v_step_approver_emp_id := (v_custom_app_elem->>'approver_employee_id')::uuid;
          select up.id into v_step_approver_user_id
          from public.user_profiles up
          where up.employee_id = v_step_approver_emp_id
          limit 1;
          v_step_resolved_level := coalesce((v_custom_app_elem->>'approver_level')::int, v_route.approver_level);
          v_custom_matched := true;
          exit;
        end if;
      end loop;
    end if;

    if v_custom_matched and v_step_approver_emp_id is not null then
      select
        nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), ''),
        e.employee_no,
        p.name
      into
        v_step_approver_name,
        v_step_approver_emp_no,
        v_step_approver_pos_name
      from public.employees e
      left join public.employee_assignments ea on ea.employee_id = e.id and ea.is_primary = true
      left join public.positions p on p.id = ea.position_id
      where e.id = v_step_approver_emp_id
      limit 1;

      insert into public.request_approval_steps (
        request_id,
        step_order,
        required_function_id,
        required_level,
        assigned_approver_employee_id,
        assigned_approver_user_id,
        status,
        approver_name,
        approver_position_name,
        approver_employee_no,
        is_reassigned
      )
      values (
        v_request_id,
        v_step_order,
        v_assignment.function_id,
        coalesce(v_step_resolved_level, v_route.approver_level),
        v_step_approver_emp_id,
        v_step_approver_user_id,
        case when v_step_order = 1 then 'pending' else 'waiting' end,
        v_step_approver_name,
        v_step_approver_pos_name,
        v_step_approver_emp_no,
        true
      );
      v_used_employee_ids := array_append(v_used_employee_ids, v_step_approver_emp_id);
    else
      -- Standard approver resolution
      select
        (to_jsonb(fa)->>'approver_employee_id')::uuid,
        coalesce(
          (to_jsonb(fa)->>'approver_user_profile_id')::uuid,
          (to_jsonb(fa)->>'approver_user_id')::uuid,
          (select id from public.user_profiles where employee_id = (to_jsonb(fa)->>'approver_employee_id')::uuid limit 1)
        ),
        coalesce((to_jsonb(fa)->>'resolved_level')::integer, v_route.approver_level)
      into
        v_step_approver_emp_id,
        v_step_approver_user_id,
        v_step_resolved_level
      from public.find_request_approver(
        v_assignment.id,
        v_assignment.function_id,
        v_route.approver_level,
        v_profile.employee_id,
        v_used_employee_ids
      ) fa
      limit 1;

      if v_step_approver_emp_id is not null then
        select
          nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), ''),
          e.employee_no,
          p.name
        into
          v_step_approver_name,
          v_step_approver_emp_no,
          v_step_approver_pos_name
        from public.employees e
        left join public.employee_assignments ea on ea.employee_id = e.id and ea.is_primary = true
        left join public.positions p on p.id = ea.position_id
        where e.id = v_step_approver_emp_id
        limit 1;

        insert into public.request_approval_steps (
          request_id,
          step_order,
          required_function_id,
          required_level,
          assigned_approver_employee_id,
          assigned_approver_user_id,
          status,
          approver_name,
          approver_position_name,
          approver_employee_no,
          is_reassigned
        )
        values (
          v_request_id,
          v_step_order,
          v_assignment.function_id,
          coalesce(v_step_resolved_level, v_route.approver_level),
          v_step_approver_emp_id,
          v_step_approver_user_id,
          case when v_step_order = 1 then 'pending' else 'waiting' end,
          v_step_approver_name,
          v_step_approver_pos_name,
          v_step_approver_emp_no,
          false
        );

        v_used_employee_ids := array_append(v_used_employee_ids, v_step_approver_emp_id);
      end if;
    end if;
  end loop;

  -- Fallback if no steps were inserted
  if v_step_order = 0 then
    for v_fallback_lvl in select unnest(array[
      greatest(2, coalesce(v_position.authority_level, 1) + 1),
      greatest(5, coalesce(v_position.authority_level, 1) + 2)
    ]) loop
      v_step_order := v_step_order + 1;
      v_step_approver_emp_id := null;
      v_step_approver_user_id := null;
      v_step_resolved_level := null;
      v_step_approver_name := null;
      v_step_approver_pos_name := null;
      v_step_approver_emp_no := null;

      select
        (to_jsonb(fa)->>'approver_employee_id')::uuid,
        coalesce(
          (to_jsonb(fa)->>'approver_user_profile_id')::uuid,
          (to_jsonb(fa)->>'approver_user_id')::uuid,
          (select id from public.user_profiles where employee_id = (to_jsonb(fa)->>'approver_employee_id')::uuid limit 1)
        ),
        coalesce((to_jsonb(fa)->>'resolved_level')::integer, v_fallback_lvl)
      into
        v_step_approver_emp_id,
        v_step_approver_user_id,
        v_step_resolved_level
      from public.find_request_approver(
        v_assignment.id,
        v_assignment.function_id,
        v_fallback_lvl,
        v_profile.employee_id,
        v_used_employee_ids
      ) fa
      limit 1;

      if v_step_approver_emp_id is not null then
        select
          nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), ''),
          e.employee_no,
          p.name
        into
          v_step_approver_name,
          v_step_approver_emp_no,
          v_step_approver_pos_name
        from public.employees e
        left join public.employee_assignments ea on ea.employee_id = e.id and ea.is_primary = true
        left join public.positions p on p.id = ea.position_id
        where e.id = v_step_approver_emp_id
        limit 1;

        insert into public.request_approval_steps (
          request_id,
          step_order,
          required_function_id,
          required_level,
          assigned_approver_employee_id,
          assigned_approver_user_id,
          status,
          approver_name,
          approver_position_name,
          approver_employee_no,
          is_reassigned
        )
        values (
          v_request_id,
          v_step_order,
          v_assignment.function_id,
          coalesce(v_step_resolved_level, v_fallback_lvl),
          v_step_approver_emp_id,
          v_step_approver_user_id,
          case when v_step_order = 1 then 'pending' else 'waiting' end,
          v_step_approver_name,
          v_step_approver_pos_name,
          v_step_approver_emp_no,
          false
        );

        v_used_employee_ids := array_append(v_used_employee_ids, v_step_approver_emp_id);
      end if;
    end loop;
  end if;

  -- Send notification to Step 1 Approver if user account exists
  select assigned_approver_employee_id, assigned_approver_user_id
  into v_step1_emp_id, v_step1_user_id
  from public.request_approval_steps
  where request_id = v_request_id and step_order = 1;

  if v_step1_emp_id is not null then
    insert into public.notifications (
      employee_id,
      user_profile_id,
      title,
      message,
      link_type,
      link_id
    )
    values (
      v_step1_emp_id,
      v_step1_user_id,
      'Official Travel Order Pending Endorsement',
      coalesce(
        (select trim(concat_ws(' ', first_name, last_name)) from public.employees where id = v_profile.employee_id),
        'An employee'
      ) || ' submitted an Official Travel Order.',
      'approval',
      v_request_id
    );
  end if;

  return v_request_id;
end;
$$;

grant execute on function public.submit_travel_order_request(
  text[], date, date, time, time, text, text, text, text, numeric, numeric, numeric, text, text, jsonb
) to authenticated, anon, service_role;


-- ============================================================================
-- 7. Backfill Existing Pending Requests for Stores without Store Manager
-- ============================================================================
do $$
declare
  v_req record;
  v_approver record;
begin
  for v_req in
    select
      r.id as request_id,
      r.submitted_by_employee_id,
      ea.id as assignment_id,
      ea.function_id,
      r.store_id
    from public.requests r
    join public.departments d on d.id = r.department_id
    join public.employee_assignments ea on ea.employee_id = r.submitted_by_employee_id and ea.is_primary = true
    join public.request_approval_steps ras on ras.request_id = r.id and ras.step_order = 1
    where r.status in ('pending', 'waiting')
      and ras.status = 'pending'
      and coalesce(ras.is_reassigned, false) = false
      and lower(trim(d.name)) = 'operations'
      and r.store_id is not null
      and not exists (
        -- Store currently has no active Store Manager
        select 1 from public.employee_assignments sm_ea
        join public.positions sm_p on sm_p.id = sm_ea.position_id
        where lower(trim(sm_p.name)) = 'store manager'
          and (
            sm_ea.store_id = r.store_id
            or exists (
              select 1 from public.employee_store_assignments esa
              where esa.employee_id = sm_ea.employee_id
                and esa.store_id = r.store_id
            )
          )
          and sm_ea.is_primary = true
          and sm_ea.effective_from <= current_date
          and (sm_ea.effective_to is null or sm_ea.effective_to >= current_date)
      )
      and exists (
        -- Store has an active Assistant Store Manager
        select 1 from public.employee_assignments asm_ea
        join public.positions asm_p on asm_p.id = asm_ea.position_id
        where (
          lower(trim(asm_p.name)) in ('assistant store manager', 'assistant store manager (asm)', 'acting store manager')
          or lower(trim(asm_p.name)) like '%assistant store manager%'
        )
          and (
            asm_ea.store_id = r.store_id
            or exists (
              select 1 from public.employee_store_assignments esa
              where esa.employee_id = asm_ea.employee_id
                and esa.store_id = r.store_id
            )
          )
          and asm_ea.is_primary = true
          and asm_ea.effective_from <= current_date
          and (asm_ea.effective_to is null or asm_ea.effective_to >= current_date)
          and asm_ea.employee_id <> r.submitted_by_employee_id
      )
  loop
    select * into v_approver
    from public.find_request_approver(
      v_req.assignment_id,
      v_req.function_id,
      2,
      v_req.submitted_by_employee_id,
      '{}'::uuid[]
    );

    if v_approver.approver_employee_id is not null then
      update public.request_approval_steps ras
      set assigned_approver_employee_id = v_approver.approver_employee_id,
          assigned_approver_user_id = v_approver.approver_user_profile_id,
          required_level = 2,
          approver_name = (select trim(concat_ws(' ', first_name, middle_name, last_name, suffix)) from public.employees where id = v_approver.approver_employee_id),
          approver_position_name = (
            select pos.name from public.employee_assignments ea
            join public.positions pos on pos.id = ea.position_id
            where ea.employee_id = v_approver.approver_employee_id and ea.is_primary = true limit 1
          ),
          approver_employee_no = (select employee_no from public.employees where id = v_approver.approver_employee_id)
      where ras.request_id = v_req.request_id
        and ras.step_order = 1
        and coalesce(ras.is_reassigned, false) = false;
    end if;
  end loop;
end $$;
