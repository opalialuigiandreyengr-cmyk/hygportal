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
  requester_photo_url text,
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
    e.photo_url as requester_photo_url,
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

grant execute on function public.get_my_pending_approvals() to authenticated;
