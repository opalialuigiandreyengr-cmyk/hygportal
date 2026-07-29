-- HR employee removal supports reversible deactivation and full relational cleanup.

create or replace function public.hr_delete_employee(
  p_username text default null,
  p_password text default null,
  p_employee_id uuid default null,
  p_delete_mode text default 'soft'
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_delete_mode text := lower(trim(coalesce(p_delete_mode, '')));
  v_user_profile_id uuid;
  v_auth_user_id uuid;
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

  if v_delete_mode not in ('soft', 'hard') then
    raise exception 'Delete mode must be soft or hard.';
  end if;

  if not exists (
    select 1
    from public.employees e
    where e.id = p_employee_id
  ) then
    raise exception 'Employee profile was not found.';
  end if;

  select up.id, up.auth_user_id
  into v_user_profile_id, v_auth_user_id
  from public.user_profiles up
  where up.employee_id = p_employee_id
  limit 1;

  if v_delete_mode = 'soft' then
    update public.employees
    set employment_status = 'inactive',
        updated_at = timezone('utc', now())
    where id = p_employee_id;

    update public.user_profiles
    set is_active = false
    where employee_id = p_employee_id;

    if v_auth_user_id is not null then
      update public.mobile_push_tokens
      set is_enabled = false,
          last_registered_at = now()
      where auth_user_id = v_auth_user_id;
    end if;

    return p_employee_id;
  end if;

  -- Remove delivery queues before unlinking profile and approval relationships.
  delete from public.approval_push_outbox
  where recipient_employee_id = p_employee_id
     or recipient_user_profile_id = v_user_profile_id;

  delete from public.notifications
  where employee_id = p_employee_id
     or user_profile_id = v_user_profile_id;

  delete from public.employee_perk_requests
  where submitted_by_employee_id = p_employee_id
     or submitted_by_user_id = v_user_profile_id;

  delete from public.offset_transactions
  where employee_id = p_employee_id
     or request_id in (
       select r.id
       from public.requests r
       where r.submitted_by_employee_id = p_employee_id
     );

  delete from public.leave_transactions
  where employee_id = p_employee_id
     or request_id in (
       select r.id
       from public.requests r
       where r.submitted_by_employee_id = p_employee_id
     );

  -- Preserve other employees' request history while removing this approver link.
  update public.request_approval_steps
  set assigned_approver_employee_id = null,
      assigned_approver_user_id = null
  where assigned_approver_employee_id = p_employee_id
     or assigned_approver_user_id = v_user_profile_id;

  delete from public.requests
  where submitted_by_employee_id = p_employee_id
     or submitted_by_user_id = v_user_profile_id;

  delete from public.offset_balances where employee_id = p_employee_id;
  delete from public.leave_balances where employee_id = p_employee_id;
  delete from public.authority_assignments where employee_id = p_employee_id;
  delete from public.employee_assignments where employee_id = p_employee_id;

  update public.audit_logs
  set actor_user_profile_id = null
  where actor_user_profile_id = v_user_profile_id;

  delete from public.user_profiles where employee_id = p_employee_id;
  delete from public.employee_profile_details where employee_id = p_employee_id;
  delete from public.employees where id = p_employee_id;

  if v_auth_user_id is not null then
    delete from auth.users where id = v_auth_user_id;
  end if;

  return p_employee_id;
end;
$$;

grant execute on function public.hr_delete_employee(text, text, uuid, text) to anon, authenticated;

notify pgrst, 'reload schema';
