-- Allow admins to correct an individual approval step from the request detail modal.
-- The step order is unique within a request, so the client does not need to expose
-- the internal approval-step UUID in the request list response.

create or replace function public.admin_update_approval_step_status(
  p_request_id uuid,
  p_step_order int,
  p_status text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text := lower(trim(coalesce(p_status, '')));
  v_step_id uuid;
  v_has_rejected boolean;
  v_has_unfinished boolean;
begin
  if v_status not in ('pending', 'approved', 'rejected', 'cancelled', 'waiting') then
    raise exception 'Unsupported approval status: %', p_status;
  end if;

  update public.request_approval_steps
  set status = v_status,
      acted_at = case
        when v_status in ('approved', 'rejected', 'cancelled') then now()
        else null
      end,
      skipped_reason = case when v_status = 'cancelled' then skipped_reason else null end
  where request_id = p_request_id
    and step_order = p_step_order
  returning id into v_step_id;

  if v_step_id is null then
    raise exception 'Approval step % was not found for request %', p_step_order, p_request_id;
  end if;

  -- Keep the request-level badge consistent with the approval workflow.
  select exists (
    select 1
    from public.request_approval_steps
    where request_id = p_request_id
      and status = 'rejected'
  ) into v_has_rejected;

  select exists (
    select 1
    from public.request_approval_steps
    where request_id = p_request_id
      and status in ('waiting', 'pending', 'admin_fallback', 'needs_admin_review')
  ) into v_has_unfinished;

  update public.requests
  set status = case
        when v_has_rejected then 'rejected'
        when v_has_unfinished then 'pending'
        else 'approved'
      end,
      final_approved_at = case
        when v_has_rejected or v_has_unfinished then null
        else coalesce(final_approved_at, now())
      end,
      rejected_at = case when v_has_rejected then coalesce(rejected_at, now()) else null end,
      updated_at = now()
  where id = p_request_id;

  return 'Approval status updated successfully.';
end;
$$;

grant execute on function public.admin_update_approval_step_status(uuid, int, text) to authenticated;
grant execute on function public.admin_update_approval_step_status(uuid, int, text) to service_role;

notify pgrst, 'reload schema';
