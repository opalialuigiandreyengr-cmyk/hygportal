-- Allow assigned approvers to read time request details and leave request details
drop policy if exists "Approvers can read time request details" on public.time_request_details;
create policy "Approvers can read time request details"
on public.time_request_details for select
to authenticated
using (
  exists (
    select 1
    from public.request_approval_steps ras
    join public.user_profiles up on up.employee_id = ras.assigned_approver_employee_id
    where ras.request_id = time_request_details.request_id
      and up.auth_user_id = auth.uid()
  )
);

drop policy if exists "Approvers can read leave request details" on public.leave_request_details;
create policy "Approvers can read leave request details"
on public.leave_request_details for select
to authenticated
using (
  exists (
    select 1
    from public.request_approval_steps ras
    join public.user_profiles up on up.employee_id = ras.assigned_approver_employee_id
    where ras.request_id = leave_request_details.request_id
      and up.auth_user_id = auth.uid()
  )
);
