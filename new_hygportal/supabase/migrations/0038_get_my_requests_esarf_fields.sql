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
  time_schedule text,
  day_off text,
  payroll_class text,
  transaction_type text,
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
    trd.time_schedule,
    trd.day_off,
    trd.payroll_class,
    trd.transaction_type,
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

grant execute on function public.get_my_requests() to authenticated;
