-- ============================================================================
-- Migration 0225: Auto-delete notifications older than 6 months
--
-- Objective:
-- Implement an automatic purge mechanism for notifications that reach 6 months of age
-- to prevent unbounded table growth, optimize index usage, and conserve Supabase Disk I/O.
--
-- Components:
-- 1. public.purge_old_notifications():
--    - Unlinks any linked user_hyg_point_transactions
--    - Deletes from public.notifications where created_at < now() - interval '6 months'
--    - Deletes from public.approval_push_outbox where created_at < now() - interval '6 months'
--    - Returns deleted notifications count
-- 2. pg_cron schedule:
--    - Automatically runs daily at 19:00 UTC (03:00 AM Asia/Manila)
--    - Guarded with exception handling if pg_cron is not enabled in environment
-- 3. Update public.admin_get_notifications & public.get_my_notifications:
--    - Enforces a 6-month cutoff so old notifications are never delivered
-- 4. Immediate execution of public.purge_old_notifications() to clean existing old records
-- ============================================================================

-- 1. Create purge_old_notifications function
create or replace function public.purge_old_notifications()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted_count int := 0;
  v_role text;
begin
  -- Verification when called from an authenticated user context
  if auth.uid() is not null then
    select app_role into v_role
    from public.user_profiles
    where auth_user_id = auth.uid() and is_active = true;

    if v_role is not null and v_role not in ('hr', 'admin', 'super_admin') then
      return 0;
    end if;
  end if;

  -- 1. Unlink any hyg points transactions linked to notifications being purged
  update public.user_hyg_point_transactions t
  set notification_deleted_at = coalesce(t.notification_deleted_at, now()),
      notification_id = null
  from public.notifications n
  where n.id = t.notification_id
    and n.created_at < now() - interval '6 months';

  -- 2. Delete notifications older than 6 months
  delete from public.notifications
  where created_at < now() - interval '6 months';

  get diagnostics v_deleted_count = row_count;

  -- 3. Also purge any approval push outbox records older than 6 months
  delete from public.approval_push_outbox
  where created_at < now() - interval '6 months';

  return v_deleted_count;
end;
$$;

grant execute on function public.purge_old_notifications() to authenticated;
grant execute on function public.purge_old_notifications() to service_role;

-- 2. Schedule automatic daily purge via pg_cron (if available)
do $$
begin
  -- Try to enable pg_cron extension if available
  if exists (
    select 1 from pg_available_extensions where name = 'pg_cron'
  ) then
    begin
      create extension if not exists pg_cron;
    exception when others then
      raise notice 'pg_cron extension could not be created automatically: %', sqlerrm;
    end;
  end if;

  -- Register cron schedule if pg_cron is enabled
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'cron' and p.proname = 'schedule'
  ) then
    begin
      -- Remove previous schedule if it exists to prevent duplicate jobs
      perform cron.unschedule('auto_purge_old_notifications')
      where exists (
        select 1 from cron.job where jobname = 'auto_purge_old_notifications'
      );

      -- Run daily at 19:00 UTC (03:00 AM Asia/Manila)
      perform cron.schedule(
        'auto_purge_old_notifications',
        '0 19 * * *',
        'select public.purge_old_notifications();'
      );
    exception when others then
      raise notice 'Could not schedule cron job with pg_cron: %', sqlerrm;
    end;
  end if;
end;
$$;

-- 3. Index for approval_push_outbox created_at to speed up cleanup
create index if not exists idx_approval_push_outbox_created_at
  on public.approval_push_outbox (created_at);

-- 4. Update admin_get_notifications to filter out anything past 6 months
create or replace function public.admin_get_notifications(p_limit int default 100)
returns table (
  id uuid,
  employee_id uuid,
  user_profile_id uuid,
  title text,
  message text,
  link_type text,
  link_id uuid,
  is_read boolean,
  created_at timestamptz,
  employee_name text,
  employee_no text,
  employee_photo text,
  department_name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  select app_role into v_role
  from public.user_profiles
  where auth_user_id = auth.uid() and is_active = true;

  if v_role is null or v_role not in ('hr', 'admin', 'super_admin') then
    raise exception 'Admin access required';
  end if;

  return query
  select
    n.id,
    n.employee_id,
    n.user_profile_id,
    n.title,
    n.message,
    n.link_type,
    n.link_id,
    n.is_read,
    n.created_at,
    nullif(trim(concat_ws(' ', e.first_name, e.last_name)), '') as employee_name,
    e.employee_no,
    e.photo_url as employee_photo,
    d.name as department_name
  from public.notifications n
  left join public.employees e on e.id = n.employee_id
  left join lateral (
    select ea.department_id
    from public.employee_assignments ea
    where ea.employee_id = e.id and ea.is_primary = true
    limit 1
  ) ea on true
  left join public.departments d on d.id = ea.department_id
  where n.created_at >= now() - interval '6 months'
  order by n.created_at desc
  limit coalesce(p_limit, 100);
end;
$$;

grant execute on function public.admin_get_notifications(int) to authenticated;
grant execute on function public.admin_get_notifications(int) to service_role;

-- 5. Update get_my_notifications to filter out anything past 6 months
create or replace function public.get_my_notifications()
returns table (
  id uuid,
  title text,
  body text,
  created_at timestamptz,
  read_at timestamptz,
  action_type text,
  action_label text,
  action_status text,
  action_id uuid,
  points numeric,
  release_at timestamptz,
  received_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    n.id,
    n.title,
    n.message as body,
    n.created_at,
    case when n.is_read then n.created_at else null end as read_at,
    case
      when n.link_type = 'hyg_points_claim' then 'hyg_points_claim'
      when n.link_type = 'approval' then 'approval'
      else n.link_type
    end as action_type,
    case
      when n.link_type = 'hyg_points_claim' and hpt.status = 'released' then 'Claim'
      when n.link_type = 'hyg_points_claim' and hpt.status = 'claimed' then 'Claimed'
      else null
    end as action_label,
    hpt.status as action_status,
    coalesce(hpt.id, n.link_id) as action_id,
    hpt.points,
    hpt.release_at,
    hpt.received_at
  from public.notifications n
  join public.user_profiles up
    on up.auth_user_id = auth.uid()
   and (up.id = n.user_profile_id or up.employee_id = n.employee_id)
  left join public.user_hyg_point_transactions hpt
    on n.link_type = 'hyg_points_claim'
   and hpt.id = n.link_id
  where n.created_at >= now() - interval '6 months'
  order by n.created_at desc
  limit 100;
$$;

grant execute on function public.get_my_notifications() to authenticated;

-- 6. Execute initial purge to remove any notifications already exceeding 6 months
do $$
begin
  perform public.purge_old_notifications();
exception when others then
  raise notice 'Initial purge failed: %', sqlerrm;
end;
$$;

notify pgrst, 'reload schema';

