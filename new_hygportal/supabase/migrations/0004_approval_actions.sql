-- Approval inbox and approve/reject actions.

create or replace function public.get_my_pending_approvals()
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

create or replace function public.apply_offset_side_effects(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.requests;
  v_request_type public.request_types;
  v_time public.time_request_details;
  v_current_balance numeric;
  v_new_balance numeric;
begin
  select * into v_request
  from public.requests
  where id = p_request_id;

  select * into v_request_type
  from public.request_types
  where id = v_request.request_type_id;

  if v_request_type.affects_offset_balance = 'none' then
    return;
  end if;

  select * into v_time
  from public.time_request_details
  where request_id = p_request_id;

  select coalesce(balance_hours, 0)
  into v_current_balance
  from public.offset_balances
  where employee_id = v_request.submitted_by_employee_id;

  if v_request_type.affects_offset_balance = 'use' and coalesce(v_current_balance, 0) < v_time.total_hours then
    raise exception 'Insufficient offset balance at approval time.';
  end if;

  if v_request_type.affects_offset_balance = 'earn' then
    v_new_balance := coalesce(v_current_balance, 0) + v_time.total_hours;
  elsif v_request_type.affects_offset_balance = 'use' then
    v_new_balance := coalesce(v_current_balance, 0) - v_time.total_hours;
  else
    return;
  end if;

  insert into public.offset_balances (employee_id, balance_hours)
  values (v_request.submitted_by_employee_id, v_new_balance)
  on conflict (employee_id) do update
  set balance_hours = excluded.balance_hours,
      updated_at = now();

  insert into public.offset_transactions (
    employee_id,
    request_id,
    transaction_type,
    hours,
    balance_after
  )
  values (
    v_request.submitted_by_employee_id,
    p_request_id,
    v_request_type.affects_offset_balance,
    v_time.total_hours,
    v_new_balance
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
  end if;

  return v_step.request_id;
end;
$$;

grant execute on function public.get_my_pending_approvals() to authenticated;
grant execute on function public.decide_approval_step(uuid, text, text) to authenticated;
