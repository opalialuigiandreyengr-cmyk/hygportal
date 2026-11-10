-- Migration 0218: Exclude Management & Executive Roles from Leave Credit Usable Cap Policy
-- Specific Role Annual Quotas:
-- 1. General Manager: 20 Days
-- 2. Operations Director / Finance Director: 15 Days
-- 3. Corporate HR and Legal Head (Single Position): 7 Days
-- 4. HR Manager: 7 Days
-- 5. Area Managers: 7 Days
--
-- Business Reason:
-- These senior roles are exempt from the 1-year tenure proration and progressive monthly
-- usable cap schedule (Jan 1d, Mar 2d, Jun 3d, etc.). They receive their dedicated annual
-- leave credits in full (GM: 20d, Directors: 15d, Head/Managers: 7d), all of which are 100%
-- usable at any time throughout the calendar year, and refreshes in full every year.

-- 1. Helper function to identify excluded leadership and area management positions
create or replace function public.is_leave_policy_excluded_position(p_position_name text)
returns boolean
language sql
immutable
as $$
  select (
    -- 1. General Manager
    coalesce(lower(trim(p_position_name)), '') like '%general manager%'
    -- 2. Finance Director
    or coalesce(lower(trim(p_position_name)), '') like '%finance director%'
    -- 3. Operations Director
    or coalesce(lower(trim(p_position_name)), '') like '%operations director%'
    -- 4. Corporate HR and Legal Head (Single Position)
    or coalesce(lower(trim(p_position_name)), '') like '%corporate hr and legal head%'
    or coalesce(lower(trim(p_position_name)), '') like '%corporate hr & legal head%'
    or coalesce(lower(trim(p_position_name)), '') like '%legal head%'
    -- 5. HR Manager
    or coalesce(lower(trim(p_position_name)), '') like '%hr manager%'
    or coalesce(lower(trim(p_position_name)), '') like '%human resource manager%'
    or coalesce(lower(trim(p_position_name)), '') like '%human resources manager%'
    -- 6. Area Managers
    or coalesce(lower(trim(p_position_name)), '') like '%area manager%'
  );
$$;

grant execute on function public.is_leave_policy_excluded_position(text) to anon, authenticated, service_role;

-- 2. Update public.calculate_policy_leave_credits
create or replace function public.calculate_policy_leave_credits(
  p_employee_id uuid,
  p_target_date date default current_date
)
returns table (
  allocated_days numeric,
  usable_days numeric,
  annual_quota numeric,
  is_eligible boolean,
  anniversary_month integer,
  anniversary_year integer,
  role_tier text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_date date := coalesce(p_target_date, current_date);
  v_hire_date date;
  v_position_name text;
  v_employee_type text;
  v_employment_status text;
  v_is_excluded boolean := false;
  v_is_manager boolean := false;
  v_is_regular boolean := false;
  v_anniversary_date date;
  v_anniversary_year int;
  v_anniversary_month int;
  v_target_year int;
  v_target_month int;
  v_allocated numeric := 0;
  v_usable numeric := 0;
  v_annual_quota numeric := 0;
  v_role_tier text := 'none';
begin
  if p_employee_id is null then
    return query select 0::numeric, 0::numeric, 0::numeric, false, null::int, null::int, 'none'::text;
    return;
  end if;

  select
    coalesce(min(ea.effective_from), e.created_at::date),
    e.employment_status
  into
    v_hire_date,
    v_employment_status
  from public.employees e
  left join public.employee_assignments ea on ea.employee_id = e.id
  where e.id = p_employee_id
  group by e.id, e.created_at, e.employment_status;

  if v_hire_date is null then
    return query select 0::numeric, 0::numeric, 0::numeric, false, null::int, null::int, 'none'::text;
    return;
  end if;

  -- Get position and employee_type (prioritize primary active assignment)
  select
    p.name,
    epd.employee_type
  into
    v_position_name,
    v_employee_type
  from public.employees e
  left join public.employee_profile_details epd on epd.employee_id = e.id
  left join lateral (
    select current_ea.position_id
    from public.employee_assignments current_ea
    where current_ea.employee_id = e.id
    order by
      case when current_ea.is_primary = true then 0 else 1 end,
      case
        when current_ea.effective_to is null or current_ea.effective_to >= v_target_date then 0
        else 1
      end,
      current_ea.effective_from desc,
      current_ea.created_at desc
    limit 1
  ) ea on true
  left join public.positions p on p.id = ea.position_id
  where e.id = p_employee_id;

  -- 1. Excluded Roles: General Manager (20d), Operations Director / Finance Director (15d),
  --    Corporate HR and Legal Head (7d), HR Manager (7d), Area Managers (7d)
  v_is_excluded := public.is_leave_policy_excluded_position(v_position_name);

  if v_is_excluded then
    if coalesce(lower(trim(v_position_name)), '') like '%general manager%' then
      v_allocated := 20;
    elsif coalesce(lower(trim(v_position_name)), '') like '%operations director%'
       or coalesce(lower(trim(v_position_name)), '') like '%finance director%' then
      v_allocated := 15;
    else
      -- Corporate HR and Legal Head, HR Manager, Area Managers: 7 Days
      v_allocated := 7;
    end if;

    v_usable := v_allocated;
    v_annual_quota := v_allocated;

    -- Excluded from tenure anniversary proration and monthly usable cap schedule.
    -- They receive their full dedicated quota, 100% usable whenever they want!
    return query select
      v_allocated,        -- allocated_days (GM: 20, Director: 15, Head/Mgr: 7)
      v_usable,           -- usable_days (100% usable immediately, no monthly cap!)
      v_annual_quota,     -- annual_quota
      true,               -- is_eligible
      null::int,          -- anniversary_month
      null::int,          -- anniversary_year
      'excluded'::text;   -- role_tier
    return;
  end if;

  -- 2. Determine Role Tier: Standard Manager or Regular Employee
  v_is_manager := coalesce(lower(trim(v_position_name)), '') like '%manager%';
  v_is_regular := coalesce(lower(trim(v_employee_type)), '') = 'regular';

  if v_is_manager then
    v_role_tier := 'manager';
    v_annual_quota := 7;
  elsif v_is_regular then
    v_role_tier := 'regular';
    v_annual_quota := 5;
  else
    return query select 0::numeric, 0::numeric, 0::numeric, false, null::int, null::int, 'ineligible'::text;
    return;
  end if;

  -- 3. Check 1-Year Tenure Anniversary
  v_anniversary_date := v_hire_date + interval '1 year';
  v_anniversary_year := extract(year from v_anniversary_date)::int;
  v_anniversary_month := extract(month from v_anniversary_date)::int;
  v_target_year := extract(year from v_target_date)::int;
  v_target_month := extract(month from v_target_date)::int;

  -- Has not completed 1 year of service yet as of target date
  if v_target_date < v_anniversary_date then
    return query select 0::numeric, 0::numeric, v_annual_quota, false, v_anniversary_month, v_anniversary_year, v_role_tier;
    return;
  end if;

  -- 4. Calculate Total Allocated Leave Credits for Standard Eligible Employees
  if v_target_year = v_anniversary_year then
    -- Completed 1 year in the target calendar year (1-Year Tenure Table)
    if v_role_tier = 'regular' then
      case
        when v_anniversary_month in (1, 2) then v_allocated := 5;
        when v_anniversary_month in (3, 4) then v_allocated := 4;
        when v_anniversary_month in (5, 6, 7) then v_allocated := 3;
        when v_anniversary_month in (8, 9) then v_allocated := 2;
        when v_anniversary_month in (10, 11) then v_allocated := 1;
        when v_anniversary_month = 12 then v_allocated := 0;
        else v_allocated := 0;
      end case;
    elsif v_role_tier = 'manager' then
      case v_anniversary_month
        when 1, 2 then v_allocated := 7;
        when 3, 4 then v_allocated := 6;
        when 5, 6 then v_allocated := 5;
        when 7, 8 then v_allocated := 4;
        when 9, 10 then v_allocated := 2;
        when 11 then v_allocated := 1;
        when 12 then v_allocated := 0;
        else v_allocated := 0;
      end case;
    end if;
  elsif v_target_year > v_anniversary_year then
    -- Subsequent year (Year 2+): Refreshed in full
    if v_role_tier = 'regular' then
      v_allocated := 5;
    elsif v_role_tier = 'manager' then
      v_allocated := 7;
    end if;
  else
    v_allocated := 0;
  end if;

  -- 5. Calculate Total Usable Leave Credits Cap (based on target month)
  if v_role_tier = 'regular' then
    case
      when v_target_month in (1, 2) then v_usable := 1;
      when v_target_month in (3, 4, 5) then v_usable := 2;
      when v_target_month in (6, 7, 8) then v_usable := 3;
      when v_target_month in (9, 10) then v_usable := 4;
      when v_target_month in (11, 12) then v_usable := 5;
      else v_usable := 0;
    end case;
  elsif v_role_tier = 'manager' then
    case
      when v_target_month in (1, 2) then v_usable := 1;
      when v_target_month in (3, 4) then v_usable := 2;
      when v_target_month in (5, 6) then v_usable := 3;
      when v_target_month in (7, 8) then v_usable := 4;
      when v_target_month in (9, 10) then v_usable := 5;
      when v_target_month = 11 then v_usable := 6;
      when v_target_month = 12 then v_usable := 7;
      else v_usable := 0;
    end case;
  end if;

  -- Usable cannot exceed total allocated credits
  v_usable := least(v_allocated, v_usable);

  return query select
    v_allocated,
    v_usable,
    v_annual_quota,
    true,
    v_anniversary_month,
    v_anniversary_year,
    v_role_tier;
end;
$$;

grant execute on function public.calculate_policy_leave_credits(uuid, date) to anon, authenticated, service_role;

-- 3. Update public.sync_employee_leave_credits
create or replace function public.sync_employee_leave_credits(
  p_employee_id uuid,
  p_target_date date default current_date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_date date := coalesce(p_target_date, current_date);
  v_policy record;
  v_lb public.leave_balances;
  v_target_year int := extract(year from v_target_date)::int;
begin
  if p_employee_id is null then
    return;
  end if;

  select * into v_policy
  from public.calculate_policy_leave_credits(p_employee_id, v_target_date)
  limit 1;

  select * into v_lb
  from public.leave_balances
  where employee_id = p_employee_id;

  if v_lb.id is null then
    insert into public.leave_balances (
      employee_id,
      annual_credit_days,
      used_days,
      usable_credit_days,
      allocated_year,
      last_allocated_at,
      updated_at
    )
    values (
      p_employee_id,
      coalesce(v_policy.allocated_days, 0),
      0,
      coalesce(v_policy.usable_days, 0),
      v_target_year,
      now(),
      now()
    )
    on conflict (employee_id) do nothing;
    return;
  end if;

  -- CASE A: Excluded Roles (GM: 20d, Directors: 15d, Head/Managers: 7d)
  -- They receive their full dedicated quota, 100% usable whenever they want (no monthly cap)
  -- and it refreshes in full every year!
  if coalesce(v_policy.role_tier, '') = 'excluded' then
    if v_lb.allocated_year is null or v_lb.allocated_year < v_target_year then
      -- Annual rollover: Reset used_days, grant fresh annual credits, all usable immediately
      update public.leave_balances
      set annual_credit_days = coalesce(v_policy.allocated_days, 7),
          used_days = 0,
          usable_credit_days = coalesce(v_policy.usable_days, 7),
          allocated_year = v_target_year,
          last_allocated_at = now(),
          updated_at = now()
      where employee_id = p_employee_id;
    else
      -- Within current year: Ensure their annual credits meet their role quota
      -- (20 for GM, 15 for Directors, 7 for Corporate HR & Legal Head, HR Mgr, Area Mgrs),
      -- and ensure usable_credit_days always equals annual_credit_days!
      update public.leave_balances
      set annual_credit_days = case
            when coalesce(annual_credit_days, 0) < v_policy.allocated_days then v_policy.allocated_days
            else annual_credit_days
          end,
          usable_credit_days = case
            when coalesce(annual_credit_days, 0) < v_policy.allocated_days then v_policy.allocated_days
            else annual_credit_days
          end,
          updated_at = now()
      where employee_id = p_employee_id;
    end if;
    return;
  end if;

  -- CASE B: Standard Ineligible / Non-regular roles under 1 year
  if not coalesce(v_policy.is_eligible, false) then
    update public.leave_balances
    set annual_credit_days = 0,
        usable_credit_days = 0,
        allocated_year = v_target_year,
        updated_at = now()
    where employee_id = p_employee_id
      and (annual_credit_days <> 0 or usable_credit_days <> 0 or allocated_year is distinct from v_target_year);
    return;
  end if;

  -- CASE C: Standard Eligible Roles (Rollover)
  if v_lb.allocated_year is null or v_lb.allocated_year < v_target_year then
    update public.leave_balances
    set annual_credit_days = coalesce(v_policy.allocated_days, 0),
        used_days = 0,
        usable_credit_days = coalesce(v_policy.usable_days, 0),
        allocated_year = v_target_year,
        last_allocated_at = now(),
        updated_at = now()
    where employee_id = p_employee_id;
    return;
  end if;

  -- CASE D: Standard Eligible Roles (Within same year)
  if v_lb.allocated_year = v_target_year then
    if coalesce(v_lb.annual_credit_days, 0) = 0 and coalesce(v_policy.allocated_days, 0) > 0 then
      update public.leave_balances
      set annual_credit_days = v_policy.allocated_days,
          usable_credit_days = v_policy.usable_days,
          last_allocated_at = now(),
          updated_at = now()
      where employee_id = p_employee_id;
    else
      -- Update monthly usable credit cap according to the current month's bracket
      update public.leave_balances
      set usable_credit_days = least(coalesce(v_lb.annual_credit_days, 0), coalesce(v_policy.usable_days, 0)),
          updated_at = now()
      where employee_id = p_employee_id;
    end if;
  end if;
end;
$$;

grant execute on function public.sync_employee_leave_credits(uuid, date) to anon, authenticated, service_role;

-- 4. Update public.get_available_leave_days
create or replace function public.get_available_leave_days(
  p_employee_id uuid,
  p_target_date date default current_date
)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_date date := coalesce(p_target_date, current_date);
  v_policy record;
  v_lb public.leave_balances;
  v_effective_credit numeric;
begin
  if p_employee_id is null then
    return 0;
  end if;

  -- Ensure balance is synced
  perform public.sync_employee_leave_credits(p_employee_id, v_target_date);

  select * into v_lb
  from public.leave_balances
  where employee_id = p_employee_id;

  if v_lb.id is null then
    return 0;
  end if;

  select * into v_policy
  from public.calculate_policy_leave_credits(p_employee_id, v_target_date)
  limit 1;

  -- Excluded roles have NO monthly usable cap constraint (their full annual balance is usable)
  if coalesce(v_policy.role_tier, '') = 'excluded' then
    v_effective_credit := coalesce(v_lb.annual_credit_days, v_policy.allocated_days);
  elsif coalesce(v_policy.is_eligible, false) then
    v_effective_credit := least(coalesce(v_lb.annual_credit_days, 0), coalesce(v_policy.usable_days, 0));
  else
    v_effective_credit := coalesce(v_lb.annual_credit_days, 0);
  end if;

  return greatest(0, v_effective_credit - coalesce(v_lb.used_days, 0));
end;
$$;

grant execute on function public.get_available_leave_days(uuid, date) to anon, authenticated, service_role;

-- Overload for single parameter (uuid)
create or replace function public.get_available_leave_days(p_employee_id uuid)
returns numeric
language sql
security definer
set search_path = public
as $$
  select public.get_available_leave_days(p_employee_id, current_date);
$$;

grant execute on function public.get_available_leave_days(uuid) to anon, authenticated, service_role;

-- 5. Update admin_reimburse_employee_leave_credits to ensure excluded roles can be reimbursed without quota error
create or replace function public.admin_reimburse_employee_leave_credits(
  p_user_profile_id uuid,
  p_reimburse_days numeric,
  p_reason text default 'Admin reimbursement'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_profile public.user_profiles;
  v_used_days numeric;
  v_current_annual numeric;
  v_new_used numeric;
  v_new_annual numeric;
  v_policy record;
  v_max_quota numeric;
begin
  select *
  into v_actor
  from public.user_profiles up
  where up.auth_user_id = auth.uid()
    and up.app_role in ('admin', 'super_admin', 'hr')
    and up.is_active = true;

  if v_actor.id is null and current_user not in ('postgres', 'service_role', 'supabase_admin') then
    raise exception 'Admin or HR access is required.';
  end if;

  if p_reimburse_days is null or p_reimburse_days <= 0 then
    raise exception 'Reimbursement days must be greater than zero.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null then
    raise exception 'User was not found.';
  end if;

  if v_profile.employee_id is null then
    raise exception 'Leave credits can only be reimbursed for linked employees.';
  end if;

  -- Check leave credit policy for this employee
  select * into v_policy
  from public.calculate_policy_leave_credits(v_profile.employee_id, current_date)
  limit 1;

  -- Ensure leave_balances row exists
  insert into public.leave_balances (employee_id, annual_credit_days, used_days, usable_credit_days)
  values (v_profile.employee_id, coalesce(v_policy.allocated_days, 7), 0, coalesce(v_policy.usable_days, 7))
  on conflict (employee_id) do nothing;

  select coalesce(lb.annual_credit_days, 0), coalesce(lb.used_days, 0)
  into v_current_annual, v_used_days
  from public.leave_balances lb
  where lb.employee_id = v_profile.employee_id
  for update;

  -- If NOT excluded, enforce policy tenure
  if v_policy.role_tier <> 'excluded' then
    if not coalesce(v_policy.is_eligible, false) then
      raise exception 'Cannot reimburse: Employee has not reached 1-year tenure under the leave credit allocation policy.';
    end if;
  end if;

  -- Calculate new used and annual credits
  if v_used_days >= p_reimburse_days then
    v_new_used := round(v_used_days - p_reimburse_days, 2);
    v_new_annual := v_current_annual;
  else
    v_new_used := 0;
    v_new_annual := round(v_current_annual + (p_reimburse_days - v_used_days), 2);
  end if;

  -- If NOT excluded, ensure new annual credits do not exceed role annual quota
  if v_policy.role_tier <> 'excluded' then
    v_max_quota := coalesce(v_policy.annual_quota, case when v_policy.role_tier = 'manager' then 7 else 5 end);
    if v_new_annual > v_max_quota then
      raise exception 'Reimbursement would increase annual credits to % day(s), exceeding the policy quota of % day(s) for %.',
        v_new_annual, v_max_quota, case when v_policy.role_tier = 'manager' then 'managers' else 'regular employees' end;
    end if;
  end if;

  update public.leave_balances
  set annual_credit_days = v_new_annual,
      used_days = v_new_used,
      usable_credit_days = case
        when v_policy.role_tier = 'excluded' then v_new_annual
        else least(v_new_annual, coalesce(v_policy.usable_days, 0))
      end,
      updated_at = now()
  where employee_id = v_profile.employee_id;

  insert into public.audit_logs (
    actor_user_profile_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    coalesce(v_actor.id, v_profile.id),
    'admin_reimburse_employee_leave_credits',
    'leave_balance',
    v_profile.employee_id,
    jsonb_build_object(
      'user_profile_id', p_user_profile_id,
      'reimburse_days', p_reimburse_days,
      'reason', coalesce(nullif(trim(p_reason), ''), 'Admin reimbursement'),
      'previous_annual_credit_days', v_current_annual,
      'new_annual_credit_days', v_new_annual,
      'previous_used_days', v_used_days,
      'new_used_days', v_new_used,
      'role_tier', v_policy.role_tier
    )
  );

  return v_profile.id;
end;
$$;

grant execute on function public.admin_reimburse_employee_leave_credits(uuid, numeric, text) to authenticated, anon, service_role;

-- 6. Immediate synchronization for all existing employees to apply the new quotas and exemption immediately
do $$
declare
  r record;
begin
  for r in select id from public.employees loop
    perform public.sync_employee_leave_credits(r.id, current_date);
  end loop;
end;
$$;

notify pgrst, 'reload schema';
