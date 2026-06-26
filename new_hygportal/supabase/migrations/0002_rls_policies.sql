-- MVP Row Level Security policies.
-- These policies let an authenticated employee read their own portal profile,
-- employee record, assignment, request summaries, and reference data.

alter table public.functions enable row level security;
alter table public.positions enable row level security;
alter table public.companies enable row level security;
alter table public.areas enable row level security;
alter table public.clusters enable row level security;
alter table public.stores enable row level security;
alter table public.departments enable row level security;
alter table public.user_profiles enable row level security;
alter table public.employees enable row level security;
alter table public.employee_assignments enable row level security;
alter table public.authority_assignments enable row level security;
alter table public.request_types enable row level security;
alter table public.approval_level_routes enable row level security;
alter table public.requests enable row level security;
alter table public.request_approval_steps enable row level security;
alter table public.time_request_details enable row level security;
alter table public.leave_request_details enable row level security;
alter table public.offset_balances enable row level security;
alter table public.offset_transactions enable row level security;
alter table public.notifications enable row level security;

create policy "Authenticated users can read functions"
on public.functions for select
to authenticated
using (true);

create policy "Authenticated users can read positions"
on public.positions for select
to authenticated
using (true);

create policy "Authenticated users can read companies"
on public.companies for select
to authenticated
using (true);

create policy "Authenticated users can read areas"
on public.areas for select
to authenticated
using (true);

create policy "Authenticated users can read clusters"
on public.clusters for select
to authenticated
using (true);

create policy "Authenticated users can read stores"
on public.stores for select
to authenticated
using (true);

create policy "Authenticated users can read departments"
on public.departments for select
to authenticated
using (true);

create policy "Users can read own profile"
on public.user_profiles for select
to authenticated
using (auth_user_id = auth.uid());

create policy "Users can read own employee record"
on public.employees for select
to authenticated
using (
  exists (
    select 1
    from public.user_profiles up
    where up.auth_user_id = auth.uid()
      and up.employee_id = employees.id
  )
);

create policy "Users can read own employee assignments"
on public.employee_assignments for select
to authenticated
using (
  exists (
    select 1
    from public.user_profiles up
    where up.auth_user_id = auth.uid()
      and up.employee_id = employee_assignments.employee_id
  )
);

create policy "Users can read authority assignments"
on public.authority_assignments for select
to authenticated
using (true);

create policy "Authenticated users can read request types"
on public.request_types for select
to authenticated
using (true);

create policy "Authenticated users can read approval routes"
on public.approval_level_routes for select
to authenticated
using (true);

create policy "Users can read own submitted requests"
on public.requests for select
to authenticated
using (
  exists (
    select 1
    from public.user_profiles up
    where up.auth_user_id = auth.uid()
      and up.employee_id = requests.submitted_by_employee_id
  )
);

create policy "Users can read approval steps assigned to them or their requests"
on public.request_approval_steps for select
to authenticated
using (
  exists (
    select 1
    from public.user_profiles up
    where up.auth_user_id = auth.uid()
      and (
        up.employee_id = request_approval_steps.assigned_approver_employee_id
        or exists (
          select 1
          from public.requests r
          where r.id = request_approval_steps.request_id
            and r.submitted_by_employee_id = up.employee_id
        )
      )
  )
);

create policy "Users can read own time request details"
on public.time_request_details for select
to authenticated
using (
  exists (
    select 1
    from public.requests r
    join public.user_profiles up on up.employee_id = r.submitted_by_employee_id
    where r.id = time_request_details.request_id
      and up.auth_user_id = auth.uid()
  )
);

create policy "Users can read own leave request details"
on public.leave_request_details for select
to authenticated
using (
  exists (
    select 1
    from public.requests r
    join public.user_profiles up on up.employee_id = r.submitted_by_employee_id
    where r.id = leave_request_details.request_id
      and up.auth_user_id = auth.uid()
  )
);

create policy "Users can read own offset balance"
on public.offset_balances for select
to authenticated
using (
  exists (
    select 1
    from public.user_profiles up
    where up.auth_user_id = auth.uid()
      and up.employee_id = offset_balances.employee_id
  )
);

create policy "Users can read own offset transactions"
on public.offset_transactions for select
to authenticated
using (
  exists (
    select 1
    from public.user_profiles up
    where up.auth_user_id = auth.uid()
      and up.employee_id = offset_transactions.employee_id
  )
);

create policy "Users can read own notifications"
on public.notifications for select
to authenticated
using (
  exists (
    select 1
    from public.user_profiles up
    where up.auth_user_id = auth.uid()
      and (
        up.id = notifications.user_profile_id
        or up.employee_id = notifications.employee_id
      )
  )
);

