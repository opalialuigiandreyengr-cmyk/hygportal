-- Migration 0192: Automatic Allocation and Usable Schedule of Leave Credits based on 1-Year Tenure Anniversary
--
-- Business Rules:
-- 1. Eligible roles:
--    - Regular employees (employee_type = 'Regular')
--    - Managers (positions containing 'Manager' in title)
--    - EXCLUDING: Operations Director, Finance Director, General Manager
-- 2. Under 1 year of service:
--    - Automatically receives 0 leave credits.
-- 3. Upon completing 1 year of service (1-Year Tenure Anniversary Year):
--    - Total Allocated Leave Credits are based on Anniversary Month (Month of completion):
--      * Regular Employees:
--          Jan, Feb:      5 DAYS
--          Mar, Apr:      4 DAYS
--          May, Jun, Jul: 3 DAYS
--          Aug, Sep:      2 DAYS
--          Oct, Nov:      1 DAY
--          Dec:           0 DAY
--      * Managers:
--          Jan, Feb: 7 DAYS
--          Mar, Apr: 6 DAYS
--          May, Jun: 5 DAYS
--          Jul, Aug: 4 DAYS
--          Sep, Oct: 2 DAYS
--          Nov:      1 DAY
--          Dec:      0 DAY
-- 4. Subsequent Years (Year 2 and beyond):
--    - Resets and refreshes in full every year:
--      * Regular Employees: 5 DAYS
--      * Managers: 7 DAYS
-- 5. Monthly Usable Leave Credits Cap:
--    - Applied to both 1-year tenure and subsequent full years based on current/target calendar month:
--      * Regular Employees:
--          Jan, Feb:       1 DAY
--          Mar, Apr, May:  2 DAYS
--          Jun, Jul, Aug:  3 DAYS
--          Sep, Oct:       4 DAYS
--          Nov, Dec:       5 DAYS
--      * Managers:
--          Jan, Feb:       1 DAY
--          Mar, Apr:       2 DAYS
--          May, Jun:       3 DAYS
--          Jul, Aug:       4 DAYS
--          Sep, Oct:       5 DAYS
--          Nov:            6 DAYS
--          Dec:            7 DAYS
--    - Available usable paid leave = GREATEST(0, LEAST(allocated_days, monthly_usable_cap) - used_days).

-- Step 1: Ensure columns exist on public.leave_balances
alter table if exists public.leave_balances
  add column if not exists allocated_year integer default extract(year from current_date)::int,
  add column if not exists usable_credit_days numeric(8, 2) default 0,
  add column if not exists last_allocated_at timestamptz default now();

-- Step 2: Policy calculation function
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

  -- Get primary position and employee_type
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
      and current_ea.is_primary = true
    order by
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

  -- 1. Exclude: Operations Director, Finance Director, General Manager
  v_is_excluded := coalesce(lower(trim(v_position_name)), '') in (
                     'operations director',
                     'finance director',
                     'general manager'
                   )
                   or coalesce(lower(trim(v_position_name)), '') like '%operations director%'
                   or coalesce(lower(trim(v_position_name)), '') like '%finance director%'
                   or coalesce(lower(trim(v_position_name)), '') like '%general manager%';

  if v_is_excluded then
    return query select 0::numeric, 0::numeric, 0::numeric, false, null::int, null::int, 'excluded'::text;
    return;
  end if;

  -- 2. Determine Role Tier: Manager or Regular Employee
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

  -- 4. Calculate Total Allocated Leave Credits
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

-- Step 3: Update calculate_initial_leave_credits to route to calculate_policy_leave_credits
create or replace function public.calculate_initial_leave_credits(p_employee_id uuid)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_policy record;
begin
  if p_employee_id is null then
    return 0;
  end if;

  select * into v_policy
  from public.calculate_policy_leave_credits(p_employee_id, current_date)
  limit 1;

  return coalesce(v_policy.allocated_days, 0);
end;
$$;

grant execute on function public.calculate_initial_leave_credits(uuid) to anon, authenticated, service_role;

-- Step 4: Synchronization function to update leave_balances and handle annual refresh
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

  -- If not eligible or excluded: keep record aligned with target year
  if not coalesce(v_policy.is_eligible, false) then
    if v_lb.allocated_year is null or v_lb.allocated_year < v_target_year then
      update public.leave_balances
      set allocated_year = v_target_year,
          usable_credit_days = 0,
          updated_at = now()
      where employee_id = p_employee_id;
    end if;
    return;
  end if;

  -- 1. Year rollover: Annual reset / refresh in full!
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

  -- 2. Within the same year:
  -- If currently 0 and now completed 1-year tenure, auto-allocate credits
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

-- Step 5: Update get_available_leave_days to support target date and usable schedule
drop function if exists public.get_available_leave_days(uuid);
drop function if exists public.get_available_leave_days(uuid, date);

create or replace function public.get_available_leave_days(
  p_employee_id uuid,
  p_target_date date
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

  if coalesce(v_policy.is_eligible, false) then
    v_effective_credit := least(coalesce(v_lb.annual_credit_days, 0), coalesce(v_policy.usable_days, 0));
  else
    v_effective_credit := coalesce(v_lb.annual_credit_days, 0);
  end if;

  return greatest(0, v_effective_credit - coalesce(v_lb.used_days, 0));
end;
$$;

grant execute on function public.get_available_leave_days(uuid, date) to anon, authenticated, service_role;

-- Overload for single parameter (uuid) to maintain backward compatibility
create or replace function public.get_available_leave_days(p_employee_id uuid)
returns numeric
language sql
security definer
set search_path = public
as $$
  select public.get_available_leave_days(p_employee_id, current_date);
$$;

grant execute on function public.get_available_leave_days(uuid) to anon, authenticated, service_role;

-- Step 6: Triggers to auto-allocate on employee assignment and profile changes
create or replace function public.trg_auto_allocate_leave_credits_on_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.employee_id is not null then
    perform public.sync_employee_leave_credits(new.employee_id, current_date);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_auto_allocate_leave_credits_on_assignment on public.employee_assignments;
create trigger trg_auto_allocate_leave_credits_on_assignment
after insert or update of effective_from, position_id, is_primary on public.employee_assignments
for each row
execute function public.trg_auto_allocate_leave_credits_on_assignment();

create or replace function public.trg_auto_allocate_leave_credits_on_details()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.employee_id is not null then
    perform public.sync_employee_leave_credits(new.employee_id, current_date);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_auto_allocate_leave_credits_on_details on public.employee_profile_details;
create trigger trg_auto_allocate_leave_credits_on_details
after insert or update of employee_type on public.employee_profile_details
for each row
execute function public.trg_auto_allocate_leave_credits_on_details();

-- Step 7: Update submit_leave_request to validate against usable leave credits for leave start date
create or replace function public.submit_leave_request(
  p_leave_type text,
  p_leave_category text,
  p_start_date date,
  p_end_date date,
  p_paid_days numeric,
  p_unpaid_days numeric,
  p_reason text
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
  v_approver record;
  v_total_days numeric;
  v_leave_type text;
  v_paid_days numeric;
  v_unpaid_days numeric;
  v_available_days numeric;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  if p_end_date < p_start_date then
    raise exception 'End date cannot be earlier than start date.';
  end if;

  v_leave_type := trim(coalesce(p_leave_type, ''));
  if v_leave_type not in ('With Pay', 'Without Pay', 'Both') then
    raise exception 'Leave type must be With Pay, Without Pay, or Both.';
  end if;

  if nullif(trim(p_leave_category), '') is null then
    raise exception 'Leave category is required.';
  end if;

  if nullif(trim(p_reason), '') is null then
    raise exception 'Reason is required.';
  end if;

  v_total_days := (p_end_date - p_start_date) + 1;

  if v_leave_type = 'With Pay' then
    v_paid_days := v_total_days;
    v_unpaid_days := 0;
  elsif v_leave_type = 'Without Pay' then
    v_paid_days := 0;
    v_unpaid_days := v_total_days;
  else
    v_paid_days := coalesce(p_paid_days, 0);
    v_unpaid_days := coalesce(p_unpaid_days, 0);
  end if;

  if v_paid_days < 0 or v_unpaid_days < 0 then
    raise exception 'Leave days cannot be negative.';
  end if;

  if round((v_paid_days + v_unpaid_days)::numeric, 2) <> round(v_total_days::numeric, 2) then
    raise exception 'Paid and unpaid leave days must equal total leave days.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  if v_profile.id is null or v_profile.employee_id is null then
    raise exception 'Your login is not linked to an employee profile.';
  end if;

  -- Synchronize and validate against available usable leave days for requested start date
  v_available_days := public.get_available_leave_days(v_profile.employee_id, coalesce(p_start_date, current_date));
  if v_paid_days > v_available_days then
    raise exception 'Insufficient paid leave credits. Available usable paid leave: % day(s).', v_available_days;
  end if;

  select *
  into v_assignment
  from public.employee_assignments
  where employee_id = v_profile.employee_id
    and is_primary = true
    and effective_from <= current_date
    and (effective_to is null or effective_to >= current_date)
  order by created_at desc
  limit 1;

  if v_assignment.id is null then
    raise exception 'No active employee assignment found.';
  end if;

  select *
  into v_position
  from public.positions
  where id = v_assignment.position_id;

  if v_position.id is null then
    raise exception 'No position found for active assignment.';
  end if;

  select *
  into v_request_type
  from public.request_types
  where code = 'leave'
    and is_active = true;

  if v_request_type.id is null then
    raise exception 'Leave request type is not configured.';
  end if;

  insert into public.requests (
    request_type_id,
    submitted_by_employee_id,
    submitted_by_user_id,
    company_id,
    department_id,
    store_id,
    status
  )
  values (
    v_request_type.id,
    v_profile.employee_id,
    v_profile.id,
    v_assignment.company_id,
    v_assignment.department_id,
    v_assignment.store_id,
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
    v_leave_type,
    trim(p_leave_category),
    p_start_date,
    p_end_date,
    v_total_days,
    v_paid_days,
    v_unpaid_days,
    trim(p_reason)
  );

  -- Ladder routing setup
  for v_route in
    select
      level,
      approver_role,
      approval_condition,
      is_active,
      step_order,
      cross_department_scope,
      specific_position_id,
      selected_cluster_area_only
    from public.department_approval_ladders
    where department_id = v_assignment.department_id
      and request_type_id = v_request_type.id
      and is_active = true
      and level > coalesce(v_position.authority_level, 0)
    order by step_order asc
  loop
    select *
    into v_approver
    from public.resolve_department_route_approver(
      v_assignment.department_id,
      v_route.level,
      v_assignment.company_id,
      v_assignment.store_id,
      v_route.cross_department_scope,
      v_route.approver_role,
      v_route.specific_position_id,
      v_route.selected_cluster_area_only
    )
    limit 1;

    insert into public.request_approval_steps (
      request_id,
      step_order,
      assigned_role,
      assigned_approver_employee_id,
      status
    )
    values (
      v_request_id,
      v_route.step_order,
      v_route.approver_role,
      v_approver.employee_id,
      'pending'
    );
  end loop;

  if not exists (
    select 1
    from public.request_approval_steps
    where request_id = v_request_id
  ) then
    update public.requests
    set status = 'needs_admin_review',
        updated_at = now()
    where id = v_request_id;
  end if;

  return v_request_id;
end;
$$;

grant execute on function public.submit_leave_request(text, text, date, date, numeric, numeric, text) to authenticated;

-- Step 8: Update admin_registered_users to sync leave credits for all registered employees
drop function if exists public.admin_registered_users();

create or replace function public.admin_registered_users()
returns table (
  user_profile_id uuid,
  auth_user_id uuid,
  username text,
  email text,
  app_role text,
  is_active boolean,
  is_banned boolean,
  employee_id uuid,
  employee_no text,
  full_name text,
  photo_url text,
  employment_status text,
  leave_credit_days numeric,
  leave_used_days numeric,
  leave_remaining_days numeric,
  offset_balance_hours numeric,
  registered_at timestamptz,
  email_confirmed_at timestamptz,
  last_sign_in_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  r record;
begin
  select *
  into v_profile
  from public.user_profiles up
  where up.auth_user_id = auth.uid()
    and up.app_role in ('admin', 'super_admin')
    and up.is_active = true;

  if v_profile.id is null then
    raise exception 'Admin access is required.';
  end if;

  -- Ensure leave balances are synced for all registered users linked to employees
  for r in
    select up_item.employee_id
    from public.user_profiles up_item
    where up_item.employee_id is not null
  loop
    perform public.sync_employee_leave_credits(r.employee_id, current_date);
  end loop;

  return query
  select
    up.id as user_profile_id,
    au.id as auth_user_id,
    up.username,
    au.email::text as email,
    up.app_role,
    up.is_active,
    coalesce(au.banned_until > now(), false) as is_banned,
    e.id as employee_id,
    e.employee_no,
    nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), '') as full_name,
    e.photo_url,
    e.employment_status,
    coalesce(lb.annual_credit_days, case when e.id is null then null else 0 end) as leave_credit_days,
    coalesce(lb.used_days, case when e.id is null then null else 0 end) as leave_used_days,
    case
      when e.id is null then null
      else public.get_available_leave_days(e.id, current_date)
    end as leave_remaining_days,
    coalesce(ob.balance_hours, case when e.id is null then null else 0 end) as offset_balance_hours,
    up.created_at as registered_at,
    au.email_confirmed_at,
    au.last_sign_in_at
  from public.user_profiles up
  join auth.users au on au.id = up.auth_user_id
  left join public.employees e on e.id = up.employee_id
  left join public.leave_balances lb on lb.employee_id = e.id
  left join public.offset_balances ob on ob.employee_id = e.id
  order by up.created_at desc, up.username nulls last;
end;
$$;

grant execute on function public.admin_registered_users() to authenticated;

create or replace function public.admin_get_registered_users()
returns table (
  user_profile_id uuid,
  auth_user_id uuid,
  username text,
  email text,
  app_role text,
  is_active boolean,
  is_banned boolean,
  employee_id uuid,
  employee_no text,
  full_name text,
  photo_url text,
  employment_status text,
  leave_credit_days numeric,
  leave_used_days numeric,
  leave_remaining_days numeric,
  offset_balance_hours numeric,
  registered_at timestamptz,
  email_confirmed_at timestamptz,
  last_sign_in_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query select * from public.admin_registered_users();
end;
$$;

grant execute on function public.admin_get_registered_users() to authenticated;

-- Step 9: Update hr_employee_profile_detail to sync leave credits on view
drop function if exists public.hr_employee_profile_detail(text, text, uuid);

create or replace function public.hr_employee_profile_detail(
  p_username text default null,
  p_password text default null,
  p_employee_id uuid default null
)
returns table (
  employee_id uuid,
  employee_no text,
  first_name text,
  middle_name text,
  last_name text,
  suffix text,
  birth_date date,
  gender text,
  civil_status text,
  email text,
  phone text,
  company_name text,
  department_name text,
  position_name text,
  hired_date date,
  employee_type text,
  employment_status text,
  time_schedule text,
  day_off_day text,
  payroll_class text,
  religion text,
  height text,
  weight text,
  other_phone text,
  social_media_type text,
  social_media_detail text,
  zip_code text,
  present_address text,
  permanent_address text,
  tin text,
  sss text,
  pagibig text,
  philhealth text,
  bank_type text,
  account_no text,
  emergency_contact text,
  emergency_contact_no text,
  reason_of_inactivity text,
  date_inactive text,
  elementary_school text,
  elementary_year text,
  secondary_school text,
  secondary_year text,
  college_school text,
  college_year text,
  college_course text,
  year_graduated text,
  father_name text,
  father_occupation text,
  mother_maiden_name text,
  mother_occupation text,
  number_of_siblings text,
  birth_order text,
  spouse_name text,
  spouse_occupation text,
  spouse_contact text,
  children_names text,
  children_count text
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
    raise exception 'Employee id is required.';
  end if;

  -- Auto-update employee_profile_details if reached 6 months (Regular) or 1 month (Probationary)
  update public.employee_profile_details epd_up
  set employee_type = case
        when current_date >= (ea_up.effective_from + interval '6 months') then 'Regular'
        when lower(trim(coalesce(epd_up.employee_type, ''))) = 'trainee'
         and current_date >= (ea_up.effective_from + interval '1 month') then 'Probationary'
        else epd_up.employee_type
      end,
      updated_at = now()
  from (
    select employee_id, min(effective_from) as effective_from
    from public.employee_assignments
    where employee_id = p_employee_id
    group by employee_id
  ) ea_up
  where epd_up.employee_id = ea_up.employee_id
    and (
      (current_date >= (ea_up.effective_from + interval '6 months') and lower(trim(coalesce(epd_up.employee_type, ''))) <> 'regular')
      or
      (lower(trim(coalesce(epd_up.employee_type, ''))) = 'trainee' and current_date >= (ea_up.effective_from + interval '1 month'))
    );

  -- Synchronize leave credits for this employee
  perform public.sync_employee_leave_credits(p_employee_id, current_date);

  return query
  select
    e.id as employee_id,
    e.employee_no,
    e.first_name,
    e.middle_name,
    e.last_name,
    e.suffix,
    e.birth_date,
    e.gender,
    e.civil_status,
    e.email,
    e.phone,
    c.name as company_name,
    d.name as department_name,
    p.name as position_name,
    ea.effective_from as hired_date,
    epd.employee_type,
    e.employment_status,
    epd.time_schedule,
    epd.day_off as day_off_day,
    epd.payroll_class,
    epd.religion,
    epd.height,
    epd.weight,
    epd.other_phone,
    epd.social_media_type,
    epd.social_media_detail,
    epd.zip_code,
    epd.present_address,
    epd.permanent_address,
    epd.tin,
    epd.sss,
    epd.pagibig,
    epd.philhealth,
    epd.bank_type,
    epd.account_no,
    epd.emergency_contact,
    epd.emergency_contact_no,
    epd.reason_of_inactivity,
    epd.date_inactive,
    epd.elementary_school,
    epd.elementary_year,
    epd.secondary_school,
    epd.secondary_year,
    epd.college_school,
    epd.college_year,
    epd.college_course,
    epd.year_graduated,
    epd.father_name,
    epd.father_occupation,
    epd.mother_maiden_name,
    epd.mother_occupation,
    epd.number_of_siblings,
    epd.birth_order,
    epd.spouse_name,
    epd.spouse_occupation,
    epd.spouse_contact,
    epd.children_names,
    epd.children_count
  from public.employees e
  left join public.employee_profile_details epd on epd.employee_id = e.id
  left join lateral (
    select *
    from public.employee_assignments current_ea
    where current_ea.employee_id = e.id
      and current_ea.is_primary = true
    order by
      case
        when current_ea.effective_to is null or current_ea.effective_to >= current_date then 0
        else 1
      end,
      current_ea.effective_from desc,
      current_ea.created_at desc
    limit 1
  ) ea on true
  left join public.companies c on c.id = ea.company_id
  left join public.departments d on d.id = ea.department_id
  left join public.positions p on p.id = ea.position_id
  where e.id = p_employee_id
  limit 1;
end;
$$;

grant execute on function public.hr_employee_profile_detail(text, text, uuid) to anon, authenticated;

-- Step 10: One-time immediate synchronization for all existing employees
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
