-- Let admins reimburse leave credits to an employee by reducing used_days or increasing annual_credit_days.

create or replace function public.admin_reimburse_employee_leave_credits(
  p_user_profile_id uuid,
  p_reimburse_days numeric
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor public.user_profiles;
  v_profile public.user_profiles;
  v_current_annual numeric;
  v_used_days numeric;
  v_new_annual numeric;
  v_new_used numeric;
begin
  select *
  into v_actor
  from public.user_profiles up
  where up.auth_user_id = auth.uid()
    and up.app_role in ('admin', 'super_admin')
    and up.is_active = true;

  if v_actor.id is null then
    raise exception 'Admin access is required.';
  end if;

  if p_reimburse_days is null or p_reimburse_days <= 0 then
    raise exception 'Reimbursement amount must be greater than zero.';
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

  insert into public.leave_balances (employee_id, annual_credit_days, used_days)
  values (v_profile.employee_id, 7, 0)
  on conflict (employee_id) do nothing;

  select coalesce(lb.annual_credit_days, 7), coalesce(lb.used_days, 0)
  into v_current_annual, v_used_days
  from public.leave_balances lb
  where lb.employee_id = v_profile.employee_id;

  if v_used_days >= p_reimburse_days then
    v_new_used := round(v_used_days - p_reimburse_days, 2);
    v_new_annual := v_current_annual;
  else
    v_new_used := 0;
    v_new_annual := round(v_current_annual + (p_reimburse_days - v_used_days), 2);
  end if;

  update public.leave_balances
  set annual_credit_days = v_new_annual,
      used_days = v_new_used,
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
    v_actor.id,
    'admin_reimburse_employee_leave_credits',
    'leave_balance',
    v_profile.employee_id,
    jsonb_build_object(
      'user_profile_id', p_user_profile_id,
      'reimburse_days', p_reimburse_days,
      'previous_annual_credit_days', v_current_annual,
      'new_annual_credit_days', v_new_annual,
      'previous_used_days', v_used_days,
      'new_used_days', v_new_used
    )
  );

  return p_user_profile_id;
end;
$$;

grant execute on function public.admin_reimburse_employee_leave_credits(uuid, numeric) to authenticated;

notify pgrst, 'reload schema';
