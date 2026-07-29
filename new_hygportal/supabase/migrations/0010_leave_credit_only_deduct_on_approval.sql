-- Keep leave credits unchanged while leave requests are pending.
-- Paid leave is deducted only by apply_leave_side_effects after final approval.

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

grant execute on function public.get_available_leave_days(uuid) to authenticated;
