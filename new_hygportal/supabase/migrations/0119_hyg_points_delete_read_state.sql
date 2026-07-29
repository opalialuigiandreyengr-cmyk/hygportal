-- Preserve read/deleted state for the launch HYG Points notification.

alter table public.user_hyg_point_transactions
add column if not exists notification_deleted_at timestamptz;

update public.notifications n
set is_read = true
from public.user_hyg_point_transactions t
where n.id = t.notification_id
  and t.source = 'launch_phase_1_profile_creation'
  and t.status = 'claimed'
  and n.is_read = false;

create or replace function public.ensure_launch_hyg_points_gift(p_user_profile_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_account_id uuid;
  v_transaction_id uuid;
  v_notification_id uuid;
begin
  select *
  into v_profile
  from public.user_profiles up
  where up.id = p_user_profile_id
    and up.auth_user_id is not null
    and up.employee_id is not null
    and up.is_active = true;

  if v_profile.id is null then
    return null;
  end if;

  insert into public.user_hyg_point_accounts (
    user_profile_id,
    auth_user_id,
    employee_id
  )
  values (
    v_profile.id,
    v_profile.auth_user_id,
    v_profile.employee_id
  )
  on conflict (user_profile_id) do update
  set auth_user_id = excluded.auth_user_id,
      employee_id = excluded.employee_id,
      updated_at = now()
  returning id into v_account_id;

  select t.id, t.notification_id
  into v_transaction_id, v_notification_id
  from public.user_hyg_point_transactions t
  where t.user_profile_id = v_profile.id
    and t.source = 'launch_phase_1_profile_creation';

  if v_transaction_id is not null then
    update public.user_hyg_point_transactions
    set account_id = v_account_id,
        auth_user_id = v_profile.auth_user_id,
        employee_id = v_profile.employee_id
    where id = v_transaction_id;

    return v_transaction_id;
  end if;

  insert into public.user_hyg_point_transactions (
    account_id,
    user_profile_id,
    auth_user_id,
    employee_id,
    source,
    points,
    status,
    release_at,
    note
  )
  values (
    v_account_id,
    v_profile.id,
    v_profile.auth_user_id,
    v_profile.employee_id,
    'launch_phase_1_profile_creation',
    100,
    'released',
    now(),
    'Phase 1 launch appreciation gift for employee profile creation.'
  )
  returning id into v_transaction_id;

  insert into public.notifications (
    employee_id,
    user_profile_id,
    title,
    message,
    link_type,
    link_id
  )
  values (
    v_profile.employee_id,
    v_profile.id,
    '100 HYG Points Gift',
    'You received 100 HYG Points as a token of appreciation for your active participation in the Phase 1 launch: Employee Profile Creation. Claim your gift to add it to your HYG Points balance.',
    'hyg_points_claim',
    v_transaction_id
  )
  returning id into v_notification_id;

  update public.user_hyg_point_transactions
  set notification_id = v_notification_id
  where id = v_transaction_id;

  return v_transaction_id;
end;
$$;

create or replace function public.delete_my_notification(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.user_hyg_point_transactions t
  set notification_deleted_at = now(),
      notification_id = null
  from public.notifications n
  where n.id = p_notification_id
    and t.notification_id = n.id
    and t.auth_user_id = auth.uid()
    and t.source = 'launch_phase_1_profile_creation';

  delete from public.notifications n
  where n.id = p_notification_id
    and exists (
      select 1
      from public.user_profiles up
      where up.auth_user_id = auth.uid()
        and (up.id = n.user_profile_id or up.employee_id = n.employee_id)
    );
end;
$$;

grant execute on function public.delete_my_notification(uuid) to authenticated;
