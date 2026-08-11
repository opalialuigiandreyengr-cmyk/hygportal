-- Admin validate leave request: updates paid/unpaid days, leave_type, status, and adjusts leave balances
create or replace function public.admin_validate_leave_request(
  p_request_id uuid,
  p_paid_days numeric,
  p_unpaid_days numeric
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_emp_id uuid;
  v_old_paid numeric;
  v_diff numeric;
  v_new_type text;
begin
  -- Get employee_id and old paid_days
  select r.submitted_by_employee_id, coalesce(lrd.paid_days, 0)
  into v_emp_id, v_old_paid
  from public.requests r
  join public.leave_request_details lrd on lrd.request_id = r.id
  where r.id = p_request_id;

  if v_emp_id is null then
    raise exception 'Leave request not found.';
  end if;

  -- Determine new leave_type
  if p_paid_days > 0 and p_unpaid_days > 0 then
    v_new_type := 'With and Without Pay';
  elsif p_paid_days > 0 then
    v_new_type := 'With Pay';
  else
    v_new_type := 'Without Pay';
  end if;

  -- Update leave_request_details
  update public.leave_request_details
  set paid_days = p_paid_days,
      unpaid_days = p_unpaid_days,
      leave_type = v_new_type,
      total_days = (p_paid_days + p_unpaid_days)
  where request_id = p_request_id;

  -- Update requests status to 'validated'
  update public.requests
  set status = 'validated',
      updated_at = now()
  where id = p_request_id;

  -- Adjust leave_balances (v_diff = new_paid - old_paid)
  -- If diff is negative (e.g. 0 - 1 = -1), used_days decreases by 1 (reimbursed)
  v_diff := p_paid_days - v_old_paid;
  if v_diff <> 0 then
    insert into public.leave_balances (employee_id, annual_credit_days, used_days)
    values (v_emp_id, 7, 0)
    on conflict (employee_id) do nothing;

    update public.leave_balances
    set used_days = greatest(0, used_days + v_diff),
        updated_at = now()
    where employee_id = v_emp_id;
  end if;

  return 'Leave request validated successfully.';
end;
$$;

grant execute on function public.admin_validate_leave_request(uuid, numeric, numeric) to authenticated;
grant execute on function public.admin_validate_leave_request(uuid, numeric, numeric) to anon;
grant execute on function public.admin_validate_leave_request(uuid, numeric, numeric) to service_role;

notify pgrst, 'reload schema';
