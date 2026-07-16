-- Keep request submission and approval actions working if push enqueue fails.
-- Stored in-app notifications still succeed; push delivery can be retried after
-- any webhook or credential configuration issue is corrected.

create or replace function public.enqueue_pending_approval_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text := 'New Approval Request';
  v_message text;
  v_request_label text;
  v_requester_name text;
  v_request_type_code text;
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
    rt.code,
    case when rt.code = 'leave' then 'Leave Request' else 'ESARF Request' end,
    nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), '')
  into v_request_type_code, v_request_label, v_requester_name
  from public.requests r
  join public.request_types rt on rt.id = r.request_type_id
  join public.employees e on e.id = r.submitted_by_employee_id
  where r.id = new.request_id;

  if v_request_type_code not in ('leave', 'overtime', 'offset_earn', 'use_offset') then
    return new;
  end if;

  v_message := coalesce(v_requester_name, 'An employee')
    || case when v_request_type_code = 'leave' then ' submitted a ' else ' submitted an ' end
    || v_request_label
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

  begin
    insert into public.approval_push_outbox (
      approval_step_id,
      request_id,
      recipient_employee_id,
      recipient_user_profile_id,
      title,
      message,
      payload,
      notification_key
    )
    values (
      new.id,
      new.request_id,
      new.assigned_approver_employee_id,
      new.assigned_approver_user_id,
      v_title,
      v_message,
      jsonb_build_object('kind', 'approval', 'requestId', new.request_id, 'stepId', new.id),
      'approval:' || new.id::text
    )
    on conflict (notification_key) do nothing;
  exception when others then
    raise warning 'Unable to queue approval push alert for step %: %', new.id, sqlerrm;
  end;

  return new;
end;
$$;

create or replace function public.enqueue_request_outcome_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_recipient_profile_id uuid;
  v_request_type_code text;
  v_request_label text;
  v_title text;
  v_message text;
begin
  if new.status not in ('approved', 'rejected')
    or old.status is not distinct from new.status then
    return new;
  end if;

  select
    coalesce(new.submitted_by_user_id, up.id),
    rt.code,
    case when rt.code = 'leave' then 'Leave Request' else 'ESARF Request' end
  into v_recipient_profile_id, v_request_type_code, v_request_label
  from public.request_types rt
  left join public.user_profiles up on up.employee_id = new.submitted_by_employee_id
  where rt.id = new.request_type_id
  limit 1;

  if v_recipient_profile_id is null
    or v_request_type_code not in ('leave', 'overtime', 'offset_earn', 'use_offset') then
    return new;
  end if;

  if new.status = 'approved' then
    v_title := 'Request Approved';
    v_message := 'Your ' || v_request_label || ' has been approved.';
  else
    v_title := 'Request Rejected';
    v_message := 'Your ' || v_request_label || ' has been rejected.';
  end if;

  insert into public.notifications (
    employee_id,
    user_profile_id,
    title,
    message,
    link_type,
    link_id
  )
  values (
    new.submitted_by_employee_id,
    v_recipient_profile_id,
    v_title,
    v_message,
    'request',
    new.id
  );

  begin
    insert into public.approval_push_outbox (
      approval_step_id,
      request_id,
      recipient_employee_id,
      recipient_user_profile_id,
      title,
      message,
      payload,
      notification_key
    )
    values (
      null,
      new.id,
      new.submitted_by_employee_id,
      v_recipient_profile_id,
      v_title,
      v_message,
      jsonb_build_object('kind', 'request_status', 'requestId', new.id, 'status', new.status),
      'request:' || new.id::text || ':' || new.status
    )
    on conflict (notification_key) do nothing;
  exception when others then
    raise warning 'Unable to queue request outcome push alert for request %: %', new.id, sqlerrm;
  end;

  return new;
end;
$$;

notify pgrst, 'reload schema';
