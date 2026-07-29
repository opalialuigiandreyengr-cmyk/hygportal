-- Let admins manually deduct leave credits by increasing used days.

create or replace function public.admin_deduct_employee_leave_credits(
  p_user_profile_id uuid,
  p_deduct_days numeric
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

  if p_deduct_days is null or p_deduct_days <= 0 then
    raise exception 'Deduction amount must be greater than zero.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null then
    raise exception 'User was not found.';
  end if;

  if v_profile.employee_id is null then
    raise exception 'Leave credits can only be deducted from linked employees.';
  end if;

  insert into public.leave_balances (employee_id, annual_credit_days, used_days)
  values (v_profile.employee_id, 7, 0)
  on conflict (employee_id) do nothing;

  select coalesce(lb.annual_credit_days, 7), coalesce(lb.used_days, 0)
  into v_current_annual, v_used_days
  from public.leave_balances lb
  where lb.employee_id = v_profile.employee_id;

  v_new_used := round(v_used_days + p_deduct_days, 2);

  if v_new_used > v_current_annual then
    raise exception 'Deduction exceeds available credits. Remaining: % day(s).', v_current_annual - v_used_days;
  end if;

  update public.leave_balances
  set used_days = v_new_used,
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
    'admin_deduct_employee_leave_credits',
    'leave_balance',
    v_profile.employee_id,
    jsonb_build_object(
      'user_profile_id', p_user_profile_id,
      'deduct_days', p_deduct_days,
      'annual_credit_days', v_current_annual,
      'previous_used_days', v_used_days,
      'new_used_days', v_new_used
    )
  );

  return p_user_profile_id;
end;
$$;

grant execute on function public.admin_deduct_employee_leave_credits(uuid, numeric) to authenticated;

notify pgrst, 'reload schema';
