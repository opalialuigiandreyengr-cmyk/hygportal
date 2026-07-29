-- Register Expo push devices and queue alerts whenever an approval becomes actionable.

create table if not exists public.mobile_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_profile_id uuid not null references public.user_profiles(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  expo_push_token text not null unique,
  platform text not null,
  device_name text,
  is_enabled boolean not null default true,
  last_registered_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint mobile_push_tokens_platform_check check (platform in ('android', 'ios')),
  constraint mobile_push_tokens_expo_token_check check (expo_push_token like 'ExponentPushToken[%]' or expo_push_token like 'ExpoPushToken[%]')
);

alter table public.mobile_push_tokens enable row level security;

drop policy if exists "Users can read own push tokens" on public.mobile_push_tokens;
create policy "Users can read own push tokens"
on public.mobile_push_tokens for select
to authenticated
using (auth_user_id = auth.uid());

create or replace function public.register_my_push_token(
  p_expo_push_token text,
  p_platform text,
  p_device_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_id uuid;
  v_token text := trim(coalesce(p_expo_push_token, ''));
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  if v_token not like 'ExponentPushToken[%]' and v_token not like 'ExpoPushToken[%]' then
    raise exception 'Invalid Expo push token.';
  end if;

  if p_platform not in ('android', 'ios') then
    raise exception 'Push notifications are only supported on Android and iOS.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where auth_user_id = auth.uid()
    and is_active = true
  limit 1;

  if v_profile.id is null then
    raise exception 'Your login is not linked to an active employee profile.';
  end if;

  insert into public.mobile_push_tokens (
    user_profile_id,
    auth_user_id,
    expo_push_token,
    platform,
    device_name,
    is_enabled,
    last_registered_at
  )
  values (
    v_profile.id,
    auth.uid(),
    v_token,
    p_platform,
    nullif(trim(coalesce(p_device_name, '')), ''),
    true,
    now()
  )
  on conflict (expo_push_token) do update
  set user_profile_id = excluded.user_profile_id,
      auth_user_id = excluded.auth_user_id,
      platform = excluded.platform,
      device_name = excluded.device_name,
      is_enabled = true,
      last_registered_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.disable_my_push_tokens(p_expo_push_token text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  update public.mobile_push_tokens
  set is_enabled = false,
      last_registered_at = now()
  where auth_user_id = auth.uid()
    and (
      p_expo_push_token is null
      or expo_push_token = trim(p_expo_push_token)
    );
end;
$$;

create table if not exists public.approval_push_outbox (
  id uuid primary key default gen_random_uuid(),
  approval_step_id uuid not null unique references public.request_approval_steps(id) on delete cascade,
  request_id uuid not null references public.requests(id) on delete cascade,
  recipient_employee_id uuid not null references public.employees(id),
  recipient_user_profile_id uuid not null references public.user_profiles(id),
  title text not null,
  message text not null,
  payload jsonb not null default '{}'::jsonb,
  delivery_status text not null default 'queued',
  attempts int not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  constraint approval_push_outbox_status_check check (delivery_status in ('queued', 'sent', 'skipped', 'failed'))
);

alter table public.approval_push_outbox enable row level security;

create or replace function public.enqueue_pending_approval_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text := 'New Approval Request';
  v_message text;
  v_request_type_name text;
  v_requester_name text;
begin
  if new.status <> 'pending' or new.assigned_approver_employee_id is null or new.assigned_approver_user_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE'
    and old.status = 'pending'
    and old.assigned_approver_employee_id is not distinct from new.assigned_approver_employee_id then
    return new;
  end if;

  select
    rt.name,
    nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), '')
  into v_request_type_name, v_requester_name
  from public.requests r
  join public.request_types rt on rt.id = r.request_type_id
  join public.employees e on e.id = r.submitted_by_employee_id
  where r.id = new.request_id;

  v_message := coalesce(v_requester_name, 'An employee')
    || ' submitted '
    || coalesce(v_request_type_name, 'a request')
    || ' for your approval.';

  insert into public.notifications (
    employee_id,
    user_profile_id,
    title,
    message,
    link_type,
    link_id
  )
  values (
    new.assigned_approver_employee_id,
    new.assigned_approver_user_id,
    v_title,
    v_message,
    'approval',
    new.request_id
  );

  insert into public.approval_push_outbox (
    approval_step_id,
    request_id,
    recipient_employee_id,
    recipient_user_profile_id,
    title,
    message,
    payload
  )
  values (
    new.id,
    new.request_id,
    new.assigned_approver_employee_id,
    new.assigned_approver_user_id,
    v_title,
    v_message,
    jsonb_build_object('kind', 'approval', 'requestId', new.request_id, 'stepId', new.id)
  )
  on conflict (approval_step_id) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_enqueue_pending_approval_notification on public.request_approval_steps;
create trigger trg_enqueue_pending_approval_notification
after insert or update on public.request_approval_steps
for each row
execute function public.enqueue_pending_approval_notification();

create or replace function public.get_my_notifications()
returns table (
  id uuid,
  title text,
  body text,
  created_at timestamptz,
  read_at timestamptz
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
    case when n.is_read then n.created_at else null end as read_at
  from public.notifications n
  join public.user_profiles up
    on up.auth_user_id = auth.uid()
   and (up.id = n.user_profile_id or up.employee_id = n.employee_id)
  order by n.created_at desc
  limit 100;
$$;

create or replace function public.mark_my_notification_read(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.notifications n
  set is_read = true
  where n.id = p_notification_id
    and exists (
      select 1
      from public.user_profiles up
      where up.auth_user_id = auth.uid()
        and (up.id = n.user_profile_id or up.employee_id = n.employee_id)
    );
end;
$$;

create or replace function public.delete_my_notification(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
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

revoke all on public.mobile_push_tokens from anon, authenticated;
grant select on public.mobile_push_tokens to authenticated;
revoke all on public.approval_push_outbox from anon, authenticated;

grant execute on function public.register_my_push_token(text, text, text) to authenticated;
grant execute on function public.disable_my_push_tokens(text) to authenticated;
grant execute on function public.get_my_notifications() to authenticated;
grant execute on function public.mark_my_notification_read(uuid) to authenticated;
grant execute on function public.delete_my_notification(uuid) to authenticated;

notify pgrst, 'reload schema';
