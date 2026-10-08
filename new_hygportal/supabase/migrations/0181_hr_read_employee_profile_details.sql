-- Migration 0181: Allow HR/Admin desktop to read the current employee profile details.
-- The employee app reads this table directly. Without this policy, the desktop
-- silently falls back to cached/RPC data and can show stale government or bank values.

drop policy if exists "HR can read employee profile details" on public.employee_profile_details;

create policy "HR can read employee profile details"
on public.employee_profile_details for select
to authenticated
using (public.is_hr_staff());
