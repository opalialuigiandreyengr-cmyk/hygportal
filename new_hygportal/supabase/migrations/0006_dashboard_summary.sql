-- Employee dashboard counters.

create or replace function public.get_my_dashboard_summary()
returns table (
  pending_requests bigint,
  pending_approvals bigint,
  offset_balance numeric
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
    ) as offset_balance;
$$;

grant execute on function public.get_my_dashboard_summary() to authenticated;

