-- Migration 0208: Multi-store employee assignment for Operations Department (Store Managers)
-- 1. Create public.employee_store_assignments table to support multiple store assignments per employee.
-- 2. Backfill existing primary store assignments from employee_assignments.
-- 3. Update hr_set_employee_stores RPC to manage both primary and additional assigned stores.
-- 4. Update hr_get_employee_assigned_stores RPC to fetch all assigned stores for an employee.
-- 5. Update find_request_approver to resolve Store Manager (Level 2) across all assigned stores.
-- 6. Update hr_admin_store_route_scopes to display Store Manager names across all assigned stores in Approval Routes.
-- 7. Update manager_my_team_directory to support multi-store managers.

-- ============================================================================
-- 1. Table: public.employee_store_assignments
-- ============================================================================
create table if not exists public.employee_store_assignments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete cascade,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  constraint employee_store_assignments_unique unique (employee_id, store_id)
);

create index if not exists idx_employee_store_assignments_emp on public.employee_store_assignments(employee_id);
create index if not exists idx_employee_store_assignments_store on public.employee_store_assignments(store_id);

alter table public.employee_store_assignments enable row level security;

drop policy if exists "Allow authenticated read employee_store_assignments" on public.employee_store_assignments;
create policy "Allow authenticated read employee_store_assignments"
on public.employee_store_assignments for select
to authenticated
using (true);

drop policy if exists "Allow HR manage employee_store_assignments" on public.employee_store_assignments;
create policy "Allow HR manage employee_store_assignments"
on public.employee_store_assignments for all
to authenticated
using (public.is_hr_staff())
with check (public.is_hr_staff());

-- ============================================================================
-- 2. Backfill existing primary store assignments
-- ============================================================================
insert into public.employee_store_assignments (employee_id, store_id, is_primary)
select distinct ea.employee_id, ea.store_id, true
from public.employee_assignments ea
where ea.store_id is not null
  and ea.is_primary = true
  and (ea.effective_to is null or ea.effective_to >= current_date)
on conflict (employee_id, store_id) do update set is_primary = true;

-- ============================================================================
-- 3. RPC: hr_get_employee_assigned_stores
-- ============================================================================
drop function if exists public.hr_get_employee_assigned_stores(text, text, uuid);

create or replace function public.hr_get_employee_assigned_stores(
  p_username text default null,
  p_password text default null,
  p_employee_id uuid default null
)
returns table (
  store_id uuid,
  store_name text,
  is_primary boolean
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

  if p_employee_id is null then
    return;
  end if;

  return query
  select
    s.id as store_id,
    s.name as store_name,
    esa.is_primary
  from public.employee_store_assignments esa
  join public.stores s on s.id = esa.store_id
  where esa.employee_id = p_employee_id
    and s.is_active = true
  order by esa.is_primary desc, s.name asc;
end;
$$;

grant execute on function public.hr_get_employee_assigned_stores(text, text, uuid) to anon, authenticated;

-- ============================================================================
-- 4. RPC: hr_set_employee_stores & hr_set_employee_store
-- ============================================================================
drop function if exists public.hr_set_employee_stores(text, text, uuid, text, text, text[]);

create or replace function public.hr_set_employee_stores(
  p_username text default null,
  p_password text default null,
  p_employee_id uuid default null,
  p_company_name text default null,
  p_primary_store_name text default null,
  p_additional_store_names text[] default '{}'::text[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_primary_store_id uuid;
  v_add_store_id uuid;
  v_store_name text;
  v_primary_name text := nullif(trim(coalesce(p_primary_store_name, '')), '');
  v_target_ea_id uuid;
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

  if p_employee_id is null then
    raise exception 'Employee id is required.';
  end if;

  -- Resolve Primary Store ID
  if v_primary_name is not null and lower(v_primary_name) <> 'n/a' and lower(v_primary_name) <> 'select' then
    select s.id into v_primary_store_id
    from public.stores s
    join public.companies c on c.id = s.company_id
    where lower(s.name) = lower(v_primary_name)
      and (
        nullif(trim(coalesce(p_company_name, '')), '') is null
        or lower(c.name) = lower(trim(p_company_name))
      )
      and s.is_active = true
    limit 1;
  end if;

  -- Update primary employee_assignments record
  select ea.id into v_target_ea_id
  from public.employee_assignments ea
  where ea.employee_id = p_employee_id
    and ea.is_primary = true
  order by
    case when ea.effective_to is null or ea.effective_to >= current_date then 0 else 1 end,
    ea.effective_from desc,
    ea.created_at desc
  limit 1;

  if v_target_ea_id is not null then
    update public.employee_assignments
    set store_id = v_primary_store_id
    where id = v_target_ea_id;
  end if;

  -- Synchronize employee_store_assignments
  delete from public.employee_store_assignments
  where employee_id = p_employee_id;

  if v_primary_store_id is not null then
    insert into public.employee_store_assignments (employee_id, store_id, is_primary)
    values (p_employee_id, v_primary_store_id, true)
    on conflict (employee_id, store_id) do update set is_primary = true;
  end if;

  if p_additional_store_names is not null and array_length(p_additional_store_names, 1) > 0 then
    foreach v_store_name in array p_additional_store_names loop
      v_store_name := nullif(trim(coalesce(v_store_name, '')), '');
      if v_store_name is not null
         and lower(v_store_name) <> 'n/a'
         and lower(v_store_name) <> 'select'
         and (v_primary_name is null or lower(v_store_name) <> lower(v_primary_name)) then
        select s.id into v_add_store_id
        from public.stores s
        join public.companies c on c.id = s.company_id
        where lower(s.name) = lower(v_store_name)
          and (
            nullif(trim(coalesce(p_company_name, '')), '') is null
            or lower(c.name) = lower(trim(p_company_name))
          )
          and s.is_active = true
        limit 1;

        if v_add_store_id is not null then
          insert into public.employee_store_assignments (employee_id, store_id, is_primary)
          values (p_employee_id, v_add_store_id, false)
          on conflict (employee_id, store_id) do nothing;
        end if;
      end if;
    end loop;
  end if;

  return p_employee_id;
end;
$$;

grant execute on function public.hr_set_employee_stores(text, text, uuid, text, text, text[]) to anon, authenticated;

-- Legacy 5-parameter adapter
drop function if exists public.hr_set_employee_store(text, text, uuid, text, text);

create or replace function public.hr_set_employee_store(
  p_username text default null,
  p_password text default null,
  p_employee_id uuid default null,
  p_company_name text default null,
  p_store_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.hr_set_employee_stores(
    p_username,
    p_password,
    p_employee_id,
    p_company_name,
    p_store_name,
    '{}'::text[]
  );
end;
$$;

grant execute on function public.hr_set_employee_store(text, text, uuid, text, text) to anon, authenticated;

-- ============================================================================
-- 5. RPC: find_request_approver (Multi-store aware for Level 2)
-- ============================================================================
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

  if v_assignment.store_id is not null then
    select
      coalesce(s.area_id, cl.area_id, v_assignment.area_id),
      coalesce(s.cluster_id, v_assignment.cluster_id)
    into v_assignment.area_id, v_assignment.cluster_id
    from public.stores s
    left join public.clusters cl on cl.id = s.cluster_id
    where s.id = v_assignment.store_id;
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
      order by aa.created_at asc
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
      v_authority.area_id := v_authority_area_id;

      if (
        v_has_configured_ladder
        and (
          (
            v_level = 2 and (
              (v_authority.store_id is not null and v_authority.store_id = v_assignment.store_id)
              or exists (
                select 1 from public.employee_store_assignments esa
                where esa.employee_id = v_authority.employee_id
                  and esa.store_id = v_assignment.store_id
              )
            )
          )
          or (v_level = 4 and v_authority.cluster_id is not null and v_authority.cluster_id = v_assignment.cluster_id)
          or (v_level = 5 and v_authority.area_id is not null and v_authority.area_id = v_assignment.area_id)
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
              (ea.store_id is not null and ea.store_id = v_assignment.store_id)
              or exists (
                select 1 from public.employee_store_assignments esa
                where esa.employee_id = ea.employee_id
                  and esa.store_id = v_assignment.store_id
              )
            )
          )
          or (v_level = 4 and coalesce(ea.cluster_id, s.cluster_id) is not null and coalesce(ea.cluster_id, s.cluster_id) = v_assignment.cluster_id)
          or (v_level = 5 and coalesce(ea.area_id, s.area_id, cl.area_id) is not null and coalesce(ea.area_id, s.area_id, cl.area_id) = v_assignment.area_id)
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
        -- Prefer manager who has this as primary store, followed by additional store assignment
        case when ea.store_id = v_assignment.store_id then 0 else 1 end,
        ea.created_at asc
      limit 1;

      if approver_employee_id is not null then
        resolved_level := v_level;
        return next;
        return;
      end if;
    end if;
  end loop;
end;
$$;

grant execute on function public.find_request_approver(uuid, uuid, int, uuid, uuid[]) to authenticated;

-- ============================================================================
-- 6. RPC: hr_admin_store_route_scopes (Reflects managers across all assigned stores)
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
          coalesce((
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
          ), '[]'::jsonb) as names
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
-- 7. Manager RPCs: Support Multi-Store Managers in Team Views
-- ============================================================================
drop function if exists public.manager_my_team_directory();

create or replace function public.manager_my_team_directory()
returns table (
  employee_id uuid,
  employee_no text,
  full_name text,
  photo_url text,
  employment_status text,
  department_name text,
  position_name text,
  time_schedule text,
  day_off text,
  store_name text
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_manager_employee_id uuid;
  v_manager_store_id uuid;
  v_manager_position text;
begin
  select up.employee_id
  into v_manager_employee_id
  from public.user_profiles up
  where up.auth_user_id = auth.uid()
    and up.is_active = true
  limit 1;

  if v_manager_employee_id is null then
    return;
  end if;

  select ea.store_id, p.name
  into v_manager_store_id, v_manager_position
  from public.employee_assignments ea
  join public.positions p on p.id = ea.position_id
  where ea.employee_id = v_manager_employee_id
    and ea.is_primary = true
    and ea.effective_from <= current_date
    and (ea.effective_to is null or ea.effective_to >= current_date)
  order by ea.effective_from desc, ea.created_at desc
  limit 1;

  if lower(trim(coalesce(v_manager_position, ''))) <> 'store manager' then
    raise exception 'Store Manager access is required.';
  end if;

  return query
  select
    e.id as employee_id,
    e.employee_no,
    nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), '') as full_name,
    e.photo_url,
    e.employment_status,
    d.name as department_name,
    p.name as position_name,
    epd.time_schedule,
    epd.day_off,
    s.name as store_name
  from public.employee_assignments ea
  join public.employees e on e.id = ea.employee_id
  left join public.departments d on d.id = ea.department_id
  left join public.positions p on p.id = ea.position_id
  left join public.stores s on s.id = ea.store_id
  left join public.employee_profile_details epd on epd.employee_id = e.id
  where ea.is_primary = true
    and ea.effective_from <= current_date
    and (ea.effective_to is null or ea.effective_to >= current_date)
    and (
      ea.store_id = v_manager_store_id
      or exists (
        select 1 from public.employee_store_assignments esa
        where esa.employee_id = v_manager_employee_id
          and esa.store_id = ea.store_id
      )
    )
  order by
    case when e.id = v_manager_employee_id then 0 else 1 end,
    s.name,
    e.last_name,
    e.first_name;
end;
$$;

grant execute on function public.manager_my_team_directory() to authenticated;

notify pgrst, 'reload schema';
