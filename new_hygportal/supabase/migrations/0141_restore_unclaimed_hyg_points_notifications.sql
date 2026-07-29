-- Restore accidentally deleted, unclaimed HYG Points gift notifications and
-- prevent reward notifications from being deleted before they are claimed.

alter table public.user_hyg_point_transactions
add column if not exists notification_deleted_at timestamptz;

create or replace function public.restore_unclaimed_hyg_points_notification(p_transaction_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transaction public.user_hyg_point_transactions;
  v_existing_notification_id uuid;
  v_notification_id uuid;
  v_title text;
  v_message text;
begin
  select *
  into v_transaction
  from public.user_hyg_point_transactions t
  where t.id = p_transaction_id
    and t.status = 'released'
    and t.source in ('launch_phase_1_profile_creation', 'profile_completion_100_percent');

  if v_transaction.id is null then
    return null;
  end if;

  select n.id
  into v_existing_notification_id
  from public.notifications n
  where n.id = v_transaction.notification_id
     or (
       n.link_type = 'hyg_points_claim'
       and n.link_id = v_transaction.id
     )
  order by n.created_at desc
  limit 1;

  if v_existing_notification_id is not null then
    update public.user_hyg_point_transactions
    set notification_id = v_existing_notification_id,
        notification_deleted_at = null
    where id = v_transaction.id;

    return v_existing_notification_id;
  end if;

  v_title := case
    when v_transaction.source = 'profile_completion_100_percent'
      then '100 HYG Points Profile Completion Gift'
    else '100 HYG Points Gift'
  end;

  v_message := case
    when v_transaction.source = 'profile_completion_100_percent'
      then 'You received 100 HYG Points for successfully completing 100% of your employee profile. Claim your gift to add it to your HYG Points balance.'
    else 'You received 100 HYG Points as a token of appreciation for your active participation in the Phase 1 launch: Employee Profile Creation. Claim your gift to add it to your HYG Points balance.'
  end;

  insert into public.notifications (
    employee_id,
    user_profile_id,
    title,
    message,
    link_type,
    link_id,
    is_read,
    created_at
  )
  values (
    v_transaction.employee_id,
    v_transaction.user_profile_id,
    v_title,
    v_message,
    'hyg_points_claim',
    v_transaction.id,
    false,
    coalesce(v_transaction.release_at, now())
  )
  returning id into v_notification_id;

  update public.user_hyg_point_transactions
  set notification_id = v_notification_id,
      notification_deleted_at = null
  where id = v_transaction.id;

  return v_notification_id;
end;
$$;

select public.restore_unclaimed_hyg_points_notification(t.id)
from public.user_hyg_point_transactions t
where t.status = 'released'
  and t.source in ('launch_phase_1_profile_creation', 'profile_completion_100_percent')
  and (
    t.notification_id is null
    or not exists (
      select 1
      from public.notifications n
      where n.id = t.notification_id
    )
  );

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
  on conflict (user_profile_id, source) do update
  set account_id = excluded.account_id,
      auth_user_id = excluded.auth_user_id,
      employee_id = excluded.employee_id
  returning id into v_transaction_id;

  perform public.restore_unclaimed_hyg_points_notification(v_transaction_id);

  return v_transaction_id;
end;
$$;

create or replace function public.ensure_profile_completion_hyg_points_gift(p_user_profile_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_account_id uuid;
  v_transaction_id uuid;
begin
  if not public.is_employee_profile_100_percent_complete(p_user_profile_id) then
    return null;
  end if;

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
    'profile_completion_100_percent',
    100,
    'released',
    now(),
    '100% employee profile completion reward.'
  )
  on conflict (user_profile_id, source) do update
  set account_id = excluded.account_id,
      auth_user_id = excluded.auth_user_id,
      employee_id = excluded.employee_id
  returning id into v_transaction_id;

  perform public.restore_unclaimed_hyg_points_notification(v_transaction_id);

  return v_transaction_id;
end;
$$;

create or replace function public.delete_my_notification(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hyg_points_status text;
  v_is_read boolean;
begin
  select hpt.status, n.is_read
  into v_hyg_points_status, v_is_read
  from public.notifications n
  join public.user_hyg_point_transactions hpt
    on n.link_type = 'hyg_points_claim'
   and hpt.id = n.link_id
   and hpt.auth_user_id = auth.uid()
  where n.id = p_notification_id;

  if v_hyg_points_status is not null and (v_hyg_points_status <> 'claimed' or not coalesce(v_is_read, false)) then
    raise exception 'Claim and read your HYG Points gift before deleting this notification.';
  end if;

  update public.user_hyg_point_transactions t
  set notification_deleted_at = now(),
      notification_id = null
  from public.notifications n
  where n.id = p_notification_id
    and t.id = n.link_id
    and t.auth_user_id = auth.uid()
    and n.link_type = 'hyg_points_claim'
    and t.status = 'claimed'
    and n.is_read = true;

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

revoke all on function public.restore_unclaimed_hyg_points_notification(uuid) from public, anon, authenticated;
grant execute on function public.delete_my_notification(uuid) to authenticated;

notify pgrst, 'reload schema';
