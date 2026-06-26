-- Leave credits and paid/unpaid leave split.

alter table public.leave_request_details
  add column if not exists paid_days numeric(8, 2) not null default 0,
  add column if not exists unpaid_days numeric(8, 2) not null default 0;

update public.leave_request_details
set paid_days = coalesce(total_days, 0),
    unpaid_days = 0
where paid_days = 0
  and unpaid_days = 0
  and coalesce(lower(leave_type), '') in ('with pay', 'withpay');

create table if not exists public.leave_balances (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null unique references public.employees(id),
  annual_credit_days numeric(8, 2) not null default 7,
  used_days numeric(8, 2) not null default 0,
  updated_at timestamptz not null default now(),
  constraint leave_balances_days_check check (annual_credit_days >= 0 and used_days >= 0)
);

create table if not exists public.leave_transactions (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id),
  request_id uuid references public.requests(id),
  transaction_type text not null,
  days numeric(8, 2) not null,
  balance_after numeric(8, 2) not null,
  created_at timestamptz not null default now(),
  constraint leave_transactions_type_check check (
    transaction_type in ('use_paid', 'adjustment')
  ),
  constraint leave_transactions_request_type_unique unique (request_id, transaction_type)
);

insert into public.leave_balances (employee_id, annual_credit_days, used_days)
select id, 7, 0
from public.employees
on conflict (employee_id) do nothing;

alter table public.leave_balances enable row level security;
alter table public.leave_transactions enable row level security;

drop policy if exists "Users can read own leave balance" on public.leave_balances;
create policy "Users can read own leave balance"
on public.leave_balances for select
to authenticated
using (
  exists (
    select 1
    from public.user_profiles up
    where up.auth_user_id = auth.uid()
      and up.employee_id = leave_balances.employee_id
  )
);

drop policy if exists "Users can read own leave transactions" on public.leave_transactions;
create policy "Users can read own leave transactions"
on public.leave_transactions for select
to authenticated
using (
  exists (
    select 1
    from public.user_profiles up
    where up.auth_user_id = auth.uid()
      and up.employee_id = leave_transactions.employee_id
  )
);

create or replace function public.get_available_leave_days(p_employee_id uuid)
returns numeric
language sql
security definer
set search_path = public
as $$
  select greatest(
    0,
    coalesce((
      select annual_credit_days - used_days
      from public.leave_balances
      where employee_id = p_employee_id
    ), 7)
  );
$$;

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

  insert into public.leave_balances (employee_id, annual_credit_days, used_days)
  values (v_profile.employee_id, 7, 0)
  on conflict (employee_id) do nothing;

  v_available_days := public.get_available_leave_days(v_profile.employee_id);
  if v_paid_days > v_available_days then
    raise exception 'Insufficient paid leave credits. Available paid leave: % day(s).', v_available_days;
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
    v_assignment.area_id,
    v_assignment.cluster_id,
    v_assignment.store_id,
    v_assignment.position_id,
    v_position.authority_level,
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

  select *
  into v_route
  from public.approval_level_routes
  where requester_level = v_position.authority_level
    and (department_id = v_assignment.department_id or department_id is null)
  order by
    case when department_id = v_assignment.department_id then 0 else 1 end,
    step_order asc
  limit 1;

  if v_route.approver_level is null then
    insert into public.request_approval_steps (
      request_id,
      step_order,
      required_function_id,
      required_level,
      status,
      skipped_reason
    )
    values (
      v_request_id,
      1,
      v_request_type.required_function_id,
      v_position.authority_level,
      'admin_fallback',
      'No approval route configured.'
    );

    update public.requests
    set status = 'needs_admin_review'
    where id = v_request_id;
  else
    select *
    into v_approver
    from public.find_request_approver(
      v_assignment.id,
      v_assignment.function_id,
      v_route.approver_level,
      v_profile.employee_id,
      '{}'
    )
    limit 1;

    if v_approver.approver_employee_id is null then
      insert into public.request_approval_steps (
        request_id,
        step_order,
        required_function_id,
        required_level,
        status,
        skipped_reason
      )
      values (
        v_request_id,
        1,
        v_assignment.function_id,
        v_route.approver_level,
        'admin_fallback',
        'No matching approver found.'
      );

      update public.requests
      set status = 'needs_admin_review'
      where id = v_request_id;
    else
      insert into public.request_approval_steps (
        request_id,
        step_order,
        required_function_id,
        required_level,
        assigned_approver_employee_id,
        assigned_approver_user_id,
        status
      )
      values (
        v_request_id,
        1,
        v_assignment.function_id,
        v_approver.resolved_level,
        v_approver.approver_employee_id,
        v_approver.approver_user_profile_id,
        'pending'
      );
    end if;
  end if;

  insert into public.notifications (
    employee_id,
    user_profile_id,
    title,
    message,
    link_type,
    link_id
  )
  values (
    v_profile.employee_id,
    v_profile.id,
    'Leave submitted',
    'Your leave request was submitted.',
    'request',
    v_request_id
  );

  return v_request_id;
end;
$$;

create or replace function public.apply_leave_side_effects(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.requests;
  v_request_type public.request_types;
  v_leave public.leave_request_details;
  v_current_available numeric;
  v_new_used numeric;
  v_balance_after numeric;
begin
  select * into v_request
  from public.requests
  where id = p_request_id;

  select * into v_request_type
  from public.request_types
  where id = v_request.request_type_id;

  if v_request_type.code <> 'leave' then
    return;
  end if;

  select * into v_leave
  from public.leave_request_details
  where request_id = p_request_id;

  if coalesce(v_leave.paid_days, 0) <= 0 then
    return;
  end if;

  if exists (
    select 1
    from public.leave_transactions
    where request_id = p_request_id
      and transaction_type = 'use_paid'
  ) then
    return;
  end if;

  insert into public.leave_balances (employee_id, annual_credit_days, used_days)
  values (v_request.submitted_by_employee_id, 7, 0)
  on conflict (employee_id) do nothing;

  select coalesce(annual_credit_days - used_days, 7)
  into v_current_available
  from public.leave_balances
  where employee_id = v_request.submitted_by_employee_id
  for update;

  if v_current_available < v_leave.paid_days then
    raise exception 'Insufficient paid leave credits at approval time.';
  end if;

  update public.leave_balances
  set used_days = used_days + v_leave.paid_days,
      updated_at = now()
  where employee_id = v_request.submitted_by_employee_id
  returning used_days, annual_credit_days - used_days
  into v_new_used, v_balance_after;

  insert into public.leave_transactions (
    employee_id,
    request_id,
    transaction_type,
    days,
    balance_after
  )
  values (
    v_request.submitted_by_employee_id,
    p_request_id,
    'use_paid',
    v_leave.paid_days,
    v_balance_after
  );
end;
$$;

create or replace function public.decide_approval_step(
  p_step_id uuid,
  p_decision text,
  p_remarks text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_step public.request_approval_steps;
  v_next_step_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  if p_decision not in ('approved', 'rejected') then
    raise exception 'Decision must be approved or rejected.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  if v_profile.id is null or v_profile.employee_id is null then
    raise exception 'Your login is not linked to an employee profile.';
  end if;

  select *
  into v_step
  from public.request_approval_steps
  where id = p_step_id
  for update;

  if v_step.id is null then
    raise exception 'Approval step was not found.';
  end if;

  if v_step.assigned_approver_employee_id <> v_profile.employee_id then
    raise exception 'This approval is not assigned to your employee profile.';
  end if;

  if v_step.status <> 'pending' then
    raise exception 'This approval step is not pending.';
  end if;

  update public.request_approval_steps
  set status = p_decision,
      remarks = nullif(trim(coalesce(p_remarks, '')), ''),
      acted_at = now()
  where id = p_step_id;

  if p_decision = 'rejected' then
    update public.requests
    set status = 'rejected',
        rejected_at = now(),
        rejected_reason = nullif(trim(coalesce(p_remarks, '')), ''),
        updated_at = now()
    where id = v_step.request_id;

    update public.request_approval_steps
    set status = 'cancelled'
    where request_id = v_step.request_id
      and status = 'waiting';

    return v_step.request_id;
  end if;

  select id
  into v_next_step_id
  from public.request_approval_steps
  where request_id = v_step.request_id
    and status = 'waiting'
  order by step_order asc
  limit 1;

  if v_next_step_id is not null then
    update public.request_approval_steps
    set status = 'pending'
    where id = v_next_step_id;
  else
    update public.requests
    set status = 'approved',
        final_approved_at = now(),
        updated_at = now()
    where id = v_step.request_id;

    perform public.apply_offset_side_effects(v_step.request_id);
    perform public.apply_leave_side_effects(v_step.request_id);
  end if;

  return v_step.request_id;
end;
$$;

drop function if exists public.get_my_requests();
create function public.get_my_requests()
returns table (
  request_id uuid,
  request_type_code text,
  request_type_name text,
  status text,
  submitted_at timestamptz,
  final_approved_at timestamptz,
  rejected_at timestamptz,
  rejected_reason text,
  date_from date,
  date_to date,
  time_from time,
  time_to time,
  total_hours numeric,
  leave_type text,
  leave_category text,
  start_date date,
  end_date date,
  total_days numeric,
  paid_days numeric,
  unpaid_days numeric,
  reason text,
  approval_summary jsonb
)
language sql
security definer
set search_path = public
as $$
  select
    r.id as request_id,
    rt.code as request_type_code,
    rt.name as request_type_name,
    r.status,
    r.submitted_at,
    r.final_approved_at,
    r.rejected_at,
    r.rejected_reason,
    trd.date_from,
    trd.date_to,
    trd.time_from,
    trd.time_to,
    trd.total_hours,
    lrd.leave_type,
    lrd.leave_category,
    lrd.start_date,
    lrd.end_date,
    lrd.total_days,
    lrd.paid_days,
    lrd.unpaid_days,
    coalesce(trd.reason, lrd.reason) as reason,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'step_order', ras.step_order,
            'required_level', ras.required_level,
            'status', ras.status,
            'acted_at', ras.acted_at,
            'remarks', ras.remarks,
            'skipped_reason', ras.skipped_reason,
            'approver_name', trim(concat_ws(' ', ae.first_name, ae.middle_name, ae.last_name, ae.suffix)),
            'approver_employee_no', ae.employee_no
          )
          order by ras.step_order asc
        )
        from public.request_approval_steps ras
        left join public.employees ae on ae.id = ras.assigned_approver_employee_id
        where ras.request_id = r.id
      ),
      '[]'::jsonb
    ) as approval_summary
  from public.requests r
  join public.request_types rt on rt.id = r.request_type_id
  left join public.time_request_details trd on trd.request_id = r.id
  left join public.leave_request_details lrd on lrd.request_id = r.id
  join public.user_profiles up on up.employee_id = r.submitted_by_employee_id
  where up.auth_user_id = auth.uid()
  order by r.submitted_at desc;
$$;

drop function if exists public.get_my_pending_approvals();
create function public.get_my_pending_approvals()
returns table (
  step_id uuid,
  request_id uuid,
  step_order int,
  request_type_code text,
  request_type_name text,
  requester_name text,
  requester_employee_no text,
  date_from date,
  date_to date,
  time_from time,
  time_to time,
  total_hours numeric,
  leave_type text,
  leave_category text,
  start_date date,
  end_date date,
  total_days numeric,
  paid_days numeric,
  unpaid_days numeric,
  reason text,
  submitted_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    ras.id as step_id,
    r.id as request_id,
    ras.step_order,
    rt.code as request_type_code,
    rt.name as request_type_name,
    trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)) as requester_name,
    e.employee_no as requester_employee_no,
    trd.date_from,
    trd.date_to,
    trd.time_from,
    trd.time_to,
    trd.total_hours,
    lrd.leave_type,
    lrd.leave_category,
    lrd.start_date,
    lrd.end_date,
    lrd.total_days,
    lrd.paid_days,
    lrd.unpaid_days,
    coalesce(trd.reason, lrd.reason) as reason,
    r.submitted_at
  from public.request_approval_steps ras
  join public.requests r on r.id = ras.request_id
  join public.request_types rt on rt.id = r.request_type_id
  join public.employees e on e.id = r.submitted_by_employee_id
  left join public.time_request_details trd on trd.request_id = r.id
  left join public.leave_request_details lrd on lrd.request_id = r.id
  join public.user_profiles up on up.employee_id = ras.assigned_approver_employee_id
  where up.auth_user_id = auth.uid()
    and ras.status = 'pending'
  order by r.submitted_at asc;
$$;

drop function if exists public.get_my_dashboard_summary();
create function public.get_my_dashboard_summary()
returns table (
  pending_requests bigint,
  pending_approvals bigint,
  offset_balance numeric,
  leave_credit_remaining numeric
)
language sql
security definer
set search_path = public
as $$
  with current_profile as (
    select id, employee_id
    from public.user_profiles
    where auth_user_id = auth.uid()
    limit 1
  )
  select
    (
      select count(*)
      from public.requests r
      join current_profile cp on cp.employee_id = r.submitted_by_employee_id
      where r.status in ('pending', 'needs_admin_review')
    ) as pending_requests,
    (
      select count(*)
      from public.request_approval_steps ras
      join current_profile cp on cp.employee_id = ras.assigned_approver_employee_id
      where ras.status = 'pending'
    ) as pending_approvals,
    (
      select coalesce(ob.balance_hours, 0)
      from current_profile cp
      left join public.offset_balances ob on ob.employee_id = cp.employee_id
      limit 1
    ) as offset_balance,
    (
      select public.get_available_leave_days(cp.employee_id)
      from current_profile cp
      limit 1
    ) as leave_credit_remaining;
$$;

grant execute on function public.get_available_leave_days(uuid) to authenticated;
grant execute on function public.submit_leave_request(text, text, date, date, numeric, numeric, text) to authenticated;
grant execute on function public.apply_leave_side_effects(uuid) to authenticated;
grant execute on function public.get_my_requests() to authenticated;
grant execute on function public.get_my_pending_approvals() to authenticated;
grant execute on function public.get_my_dashboard_summary() to authenticated;
grant execute on function public.decide_approval_step(uuid, text, text) to authenticated;
