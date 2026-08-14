-- Allow approvers to update time_request_details table
drop policy if exists "Approvers can update time request details" on public.time_request_details;

create policy "Approvers can update time request details"
on public.time_request_details for update
to authenticated
using (
  exists (
    select 1
    from public.request_approval_steps ras
    join public.user_profiles up on up.employee_id = ras.assigned_approver_employee_id
    where ras.request_id = time_request_details.request_id
      and up.auth_user_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.request_approval_steps ras
    join public.user_profiles up on up.employee_id = ras.assigned_approver_employee_id
    where ras.request_id = time_request_details.request_id
      and up.auth_user_id = auth.uid()
  )
);

-- RPC security definer helper to tag rejected entries in reason text
create or replace function public.update_time_request_entry_rejections(
  p_request_id uuid,
  p_rejected_entry_indices int[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason text;
  v_idx int;
begin
  select reason into v_reason
  from public.time_request_details
  where request_id = p_request_id;

  if v_reason is null or array_length(p_rejected_entry_indices, 1) is null then
    return;
  end if;

  foreach v_idx in array p_rejected_entry_indices
  loop
    -- Only tag if not already tagged as [REJECTED]
    if v_reason ~* ('\[Entry\s+' || v_idx || '\](?!.*\[REJECTED\])') then
      v_reason := regexp_replace(
        v_reason,
        '(\[Entry\s+' || v_idx || '\][^\n]*)',
        '\1 [REJECTED]',
        'gi'
      );
    elsif not (v_reason ~* ('\[Entry\s+' || v_idx || '\]')) then
      v_reason := v_reason || E'\n[Entry ' || v_idx || '] [REJECTED]';
    end if;
  end loop;

  update public.time_request_details
  set reason = v_reason
  where request_id = p_request_id;
end;
$$;

grant execute on function public.update_time_request_entry_rejections(uuid, int[]) to authenticated;

notify pgrst, 'reload schema';
