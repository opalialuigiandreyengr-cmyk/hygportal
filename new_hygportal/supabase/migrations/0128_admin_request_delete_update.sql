-- Admin: delete a request (ESARF/leave from public.requests, or perk from public.employee_perk_requests)

create or replace function public.admin_delete_request(
  p_request_id uuid,
  p_is_perk boolean default false
)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_is_perk then
    -- Perk request: single table
    delete from public.employee_perk_requests where id = p_request_id;
  else
    -- ESARF / Leave: delete child detail rows first, then the request
    delete from public.time_request_details where request_id = p_request_id;
    delete from public.leave_request_details where request_id = p_request_id;
    delete from public.request_approval_steps where request_id = p_request_id;
    delete from public.requests where id = p_request_id;
  end if;

  return 'Request deleted successfully.';
end;
$$;

grant execute on function public.admin_delete_request(uuid, boolean) to authenticated;
grant execute on function public.admin_delete_request(uuid, boolean) to service_role;

-- Admin: update request status (ESARF/leave or perk)

create or replace function public.admin_update_request_status(
  p_request_id uuid,
  p_is_perk boolean default false,
  p_new_status text default ''
)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_is_perk then
    update public.employee_perk_requests
    set status = p_new_status,
        approved_at = case when p_new_status = 'approved' then now() else approved_at end
    where id = p_request_id;
  else
    update public.requests
    set status = p_new_status,
        final_approved_at = case when p_new_status = 'approved' then now() else final_approved_at end,
        rejected_at      = case when p_new_status = 'rejected' then now() else rejected_at end
    where id = p_request_id;

    -- Also update any pending approval steps to match the new status
    if p_new_status in ('approved', 'rejected') then
      update public.request_approval_steps
      set status = p_new_status,
          acted_at = now()
      where request_id = p_request_id
        and status not in ('approved', 'rejected', 'skipped');
    end if;
  end if;

  return 'Request updated successfully.';
end;
$$;

grant execute on function public.admin_update_request_status(uuid, boolean, text) to authenticated;
grant execute on function public.admin_update_request_status(uuid, boolean, text) to service_role;

notify pgrst, 'reload schema';
