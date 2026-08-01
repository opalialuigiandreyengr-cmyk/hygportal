drop function if exists public.admin_reassign_request_approver(uuid, uuid, uuid);
drop function if exists public.admin_reassign_request_approver(uuid, uuid);

create or replace function public.admin_reassign_request_approver(
  p_request_id uuid,
  p_new_approver_employee_id uuid,
  p_step_id uuid default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_step_id uuid;
  v_user_profile_id uuid;
begin
  -- Get user_profile_id of the new approver from user_profiles table
  select id
  into v_user_profile_id
  from public.user_profiles
  where employee_id = p_new_approver_employee_id
  limit 1;

  if p_step_id is not null then
    v_target_step_id := p_step_id;
  else
    -- Find step that needs approver assignment
    select id
    into v_target_step_id
    from public.request_approval_steps
    where request_id = p_request_id
      and (assigned_approver_employee_id is null or status in ('admin_fallback', 'needs_admin_review', 'pending', 'waiting'))
    order by
      case when status = 'admin_fallback' then 1
           when assigned_approver_employee_id is null then 2
           when status = 'needs_admin_review' then 3
           when status = 'pending' then 4
           else 5 end,
      step_order asc
    limit 1;
  end if;

  if v_target_step_id is null then
    raise exception 'No editable approval step found for this request';
  end if;

  -- Update approval step: ALWAYS set status to 'pending' once reassigned
  update public.request_approval_steps
  set assigned_approver_employee_id = p_new_approver_employee_id,
      assigned_approver_user_id = v_user_profile_id,
      status = 'pending',
      skipped_reason = null
  where id = v_target_step_id;

  -- Update requests status from admin_fallback / needs_admin_review to pending
  update public.requests
  set status = 'pending',
      updated_at = now()
  where id = p_request_id
    and status in ('admin_fallback', 'needs_admin_review');

  -- Update employee_perk_requests status from admin_fallback / needs_admin_review to pending
  update public.employee_perk_requests
  set status = 'pending'
  where id = p_request_id
    and status in ('admin_fallback', 'needs_admin_review');

  return 'Approver reassigned successfully.';
end;
$$;

-- Overload with 2 parameters (p_request_id, p_new_approver_employee_id)
create or replace function public.admin_reassign_request_approver(
  p_request_id uuid,
  p_new_approver_employee_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.admin_reassign_request_approver(
    p_request_id => p_request_id,
    p_new_approver_employee_id => p_new_approver_employee_id,
    p_step_id => null
  );
end;
$$;

grant execute on function public.admin_reassign_request_approver(uuid, uuid, uuid) to authenticated;
grant execute on function public.admin_reassign_request_approver(uuid, uuid, uuid) to service_role;
grant execute on function public.admin_reassign_request_approver(uuid, uuid) to authenticated;
grant execute on function public.admin_reassign_request_approver(uuid, uuid) to service_role;

-- Clean up any existing requests that have an assigned approver but are still stuck in needs_admin_review / admin_fallback
update public.requests r
set status = 'pending',
    updated_at = now()
where r.status in ('needs_admin_review', 'admin_fallback')
  and exists (
    select 1 from public.request_approval_steps ras
    where ras.request_id = r.id
      and ras.assigned_approver_employee_id is not null
  );

update public.employee_perk_requests pr
set status = 'pending'
where pr.status in ('needs_admin_review', 'admin_fallback')
  and exists (
    select 1 from public.request_approval_steps ras
    where ras.request_id = pr.id
      and ras.assigned_approver_employee_id is not null
  );

notify pgrst, 'reload schema';
