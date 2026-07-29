-- Admin delete a registered user. Unlinks employee profile but keeps the employee record.

create or replace function public.admin_delete_user(
  p_user_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_actor public.user_profiles;
  v_profile public.user_profiles;
  v_auth_user_id uuid;
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

  select *
  into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null then
    raise exception 'User was not found.';
  end if;

  if v_profile.auth_user_id = auth.uid() then
    raise exception 'You cannot delete your own account.';
  end if;

  v_auth_user_id := v_profile.auth_user_id;

  delete from public.notifications where user_profile_id = p_user_profile_id;
  delete from public.approval_push_outbox where recipient_user_profile_id = p_user_profile_id;

  update public.requests set submitted_by_user_id = null where submitted_by_user_id = p_user_profile_id;
  update public.request_approval_steps set assigned_approver_user_id = null where assigned_approver_user_id = p_user_profile_id;
  update public.employee_perk_requests set submitted_by_user_id = null where submitted_by_user_id = p_user_profile_id;

  delete from public.user_profiles where id = p_user_profile_id;

  delete from auth.identities where user_id = v_auth_user_id;
  delete from auth.users where id = v_auth_user_id;

  insert into public.audit_logs (
    actor_user_profile_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    v_actor.id,
    'admin_delete_user',
    'user_profile',
    p_user_profile_id,
    jsonb_build_object(
      'deleted_auth_user_id', v_auth_user_id,
      'employee_id', v_profile.employee_id,
      'username', v_profile.username
    )
  );
end;
$$;

grant execute on function public.admin_delete_user(uuid) to authenticated;

notify pgrst, 'reload schema';
