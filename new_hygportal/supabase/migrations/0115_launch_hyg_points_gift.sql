-- Launch Phase 1 HYG Points gift for employee profile creation participants.

create table if not exists public.user_hyg_point_accounts (
  id uuid primary key default gen_random_uuid(),
  user_profile_id uuid not null unique references public.user_profiles(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  employee_id uuid references public.employees(id) on delete set null,
  balance numeric(12, 2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_hyg_point_accounts_balance_check check (balance >= 0)
);

create table if not exists public.user_hyg_point_transactions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.user_hyg_point_accounts(id) on delete cascade,
  user_profile_id uuid not null references public.user_profiles(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  employee_id uuid references public.employees(id) on delete set null,
  source text not null,
  points numeric(12, 2) not null,
  status text not null default 'released',
  release_at timestamptz not null default now(),
  received_at timestamptz,
  notification_id uuid references public.notifications(id) on delete set null,
  note text,
  created_at timestamptz not null default now(),
  constraint user_hyg_point_transactions_points_check check (points > 0),
  constraint user_hyg_point_transactions_status_check check (status in ('released', 'claimed', 'cancelled')),
  constraint user_hyg_point_transactions_received_check check (
    (status = 'claimed' and received_at is not null)
    or (status <> 'claimed')
  )
);

create unique index if not exists idx_user_hyg_point_transactions_profile_source
  on public.user_hyg_point_transactions(user_profile_id, source);

create index if not exists idx_user_hyg_point_transactions_auth_user
  on public.user_hyg_point_transactions(auth_user_id, created_at desc);

alter table public.user_hyg_point_accounts enable row level security;
alter table public.user_hyg_point_transactions enable row level security;

drop policy if exists "Users can read own HYG point account" on public.user_hyg_point_accounts;
create policy "Users can read own HYG point account"
on public.user_hyg_point_accounts for select
to authenticated
using (auth_user_id = auth.uid());

drop policy if exists "Users can read own HYG point transactions" on public.user_hyg_point_transactions;
create policy "Users can read own HYG point transactions"
on public.user_hyg_point_transactions for select
to authenticated
using (auth_user_id = auth.uid());

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
  returning id, notification_id into v_transaction_id, v_notification_id;

  if v_notification_id is null then
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
  end if;

  return v_transaction_id;
end;
$$;

create or replace function public.award_launch_hyg_points_after_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.ensure_launch_hyg_points_gift(new.id);
  return new;
end;
$$;

drop trigger if exists trg_award_launch_hyg_points_after_user_profile on public.user_profiles;
create trigger trg_award_launch_hyg_points_after_user_profile
after insert on public.user_profiles
for each row
execute function public.award_launch_hyg_points_after_user_profile();

create or replace function public.claim_my_hyg_points(p_transaction_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_transaction public.user_hyg_point_transactions;
  v_balance numeric(12, 2);
  v_received_at timestamptz := now();
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  select *
  into v_transaction
  from public.user_hyg_point_transactions t
  where t.id = p_transaction_id
    and t.auth_user_id = auth.uid()
  for update;

  if v_transaction.id is null then
    raise exception 'HYG Points gift was not found.';
  end if;

  if v_transaction.status = 'claimed' then
    select a.balance
    into v_balance
    from public.user_hyg_point_accounts a
    where a.id = v_transaction.account_id;

    return jsonb_build_object(
      'points', v_transaction.points,
      'balance', v_balance,
      'received_at', v_transaction.received_at,
      'status', v_transaction.status
    );
  end if;

  if v_transaction.status <> 'released' then
    raise exception 'This HYG Points gift can no longer be claimed.';
  end if;

  update public.user_hyg_point_accounts
  set balance = balance + v_transaction.points,
      updated_at = v_received_at
  where id = v_transaction.account_id
  returning balance into v_balance;

  update public.user_hyg_point_transactions
  set status = 'claimed',
      received_at = v_received_at
  where id = v_transaction.id;

  update public.notifications
  set is_read = true
  where id = v_transaction.notification_id;

  return jsonb_build_object(
    'points', v_transaction.points,
    'balance', v_balance,
    'received_at', v_received_at,
    'status', 'claimed'
  );
end;
$$;

create or replace function public.delete_my_notification(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_unclaimed_hyg_points boolean;
begin
  select exists (
    select 1
    from public.notifications n
    join public.user_profiles up
      on up.auth_user_id = auth.uid()
     and (up.id = n.user_profile_id or up.employee_id = n.employee_id)
    join public.user_hyg_point_transactions hpt
      on hpt.id = n.link_id
     and hpt.auth_user_id = auth.uid()
     and hpt.status = 'released'
    where n.id = p_notification_id
      and n.link_type = 'hyg_points_claim'
  )
  into v_is_unclaimed_hyg_points;

  if v_is_unclaimed_hyg_points then
    raise exception 'Claim your HYG Points gift before deleting this notification.';
  end if;

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

drop function if exists public.get_my_notifications();

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
    case when n.link_type = 'hyg_points_claim' then 'hyg_points_claim' else null end as action_type,
    case
      when n.link_type = 'hyg_points_claim' and hpt.status = 'released' then 'Claim'
      when n.link_type = 'hyg_points_claim' and hpt.status = 'claimed' then 'Claimed'
      else null
    end as action_label,
    hpt.status as action_status,
    hpt.id as action_id,
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
   and hpt.auth_user_id = auth.uid()
  order by n.created_at desc
  limit 100;
$$;

select public.ensure_launch_hyg_points_gift(up.id)
from public.user_profiles up
where up.auth_user_id is not null
  and up.employee_id is not null
  and up.is_active = true;

revoke all on public.user_hyg_point_accounts from anon, authenticated;
revoke all on public.user_hyg_point_transactions from anon, authenticated;
grant select on public.user_hyg_point_accounts to authenticated;
grant select on public.user_hyg_point_transactions to authenticated;
grant execute on function public.claim_my_hyg_points(uuid) to authenticated;
grant execute on function public.get_my_notifications() to authenticated;
grant execute on function public.delete_my_notification(uuid) to authenticated;

notify pgrst, 'reload schema';
