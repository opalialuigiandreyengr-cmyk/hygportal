-- Migration 0189: Admin Validate & Re-validate ESARF Request and Record Offset Deduction
-- Allows super admin to edit total hours on validation of ESARF / offset requests (both on initial validation and upon re-validating).
-- When hours are reduced (e.g. from 5.0h to 3.0h, or adjusted further on re-validation), automatically deducts the difference
-- from the employee's offset balance and creates an offset_transactions record ('deduct')
-- so it appears clearly in the HYG Portal App Offset Balance Transaction History with:
--   Title: "Offset Deducted" or "Offset Added"
--   Subtitle: "Admin offset balance adjustment"

-- 0. Update check constraint on public.offset_transactions to allow 'deduct', 'deduction', 'credit', 'refund'
alter table public.offset_transactions drop constraint if exists offset_transactions_type_check;
alter table public.offset_transactions add constraint offset_transactions_type_check
  check (transaction_type in ('earn', 'credit', 'use', 'deduct', 'deduction', 'adjustment', 'refund'));

-- 1. Create public.admin_validate_esarf_request
drop function if exists public.admin_validate_esarf_request(uuid, numeric);
drop function if exists public.admin_validate_esarf_request(uuid, numeric, text);

create or replace function public.admin_validate_esarf_request(
  p_request_id uuid,
  p_total_hours numeric default null,
  p_reason text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.requests;
  v_request_type public.request_types;
  v_time public.time_request_details;
  v_emp_id uuid;
  v_actor_profile_id uuid;
  v_current_bal numeric;
  v_new_bal numeric;
  v_old_hours numeric := 0;
  v_new_hours numeric;
  v_diff numeric := 0;
  v_action text := 'none';
  v_txn_type text := '';
  v_reason_text text := '';
  v_is_revalidation boolean := false;
begin
  -- 1. Check caller permissions if authenticated
  if auth.uid() is not null then
    select id into v_actor_profile_id
    from public.user_profiles
    where auth_user_id = auth.uid()
      and app_role in ('admin', 'super_admin')
      and is_active = true
    limit 1;

    if v_actor_profile_id is null and current_user not in ('postgres', 'service_role', 'supabase_admin') then
      raise exception 'Admin access is required.';
    end if;
  end if;

  -- 2. Fetch the request
  select * into v_request
  from public.requests
  where id = p_request_id;

  if v_request.id is null then
    raise exception 'Request not found.';
  end if;

  -- Cannot validate rejected or cancelled requests
  if v_request.status in ('rejected', 'cancelled') then
    raise exception 'Cannot validate a % request.', v_request.status;
  end if;

  -- Determine if this is an initial validation or a re-validation
  v_is_revalidation := (v_request.status = 'validated');

  v_emp_id := v_request.submitted_by_employee_id;
  if v_emp_id is null then
    raise exception 'Target employee not found for this request.';
  end if;

  -- 3. Fetch request type and time details
  select * into v_request_type
  from public.request_types
  where id = v_request.request_type_id;

  select * into v_time
  from public.time_request_details
  where request_id = p_request_id;

  if v_time.id is null then
    update public.requests
    set status = 'validated',
        updated_at = now()
    where id = p_request_id;

    if v_is_revalidation then
      return 'ESARF request re-validated successfully.';
    else
      return 'ESARF request validated successfully.';
    end if;
  end if;

  v_old_hours := coalesce(v_time.total_hours, 0);
  v_new_hours := coalesce(p_total_hours, v_old_hours);

  if v_new_hours <= 0 then
    raise exception 'Total hours must be greater than zero.';
  end if;

  v_txn_type := lower(trim(coalesce(v_time.transaction_type, '')));
  v_reason_text := lower(trim(coalesce(v_time.reason, '')));

  -- Determine action: 'use' vs 'earn'
  if coalesce(v_request_type.code, '') = 'use_offset'
     or coalesce(v_request_type.affects_offset_balance, '') = 'use'
     or v_txn_type like '%use_offset%'
     or v_txn_type like '%use offset%'
     or v_reason_text like '%(use offset)%' then
    v_action := 'use';
  elsif coalesce(v_request_type.code, '') = 'offset_earn'
     or coalesce(v_request_type.affects_offset_balance, '') = 'earn'
     or v_txn_type like '%offset%'
     or v_reason_text like '%(offset)%' then
    v_action := 'earn';
  end if;

  -- 4. Update time_request_details with new total_hours and reason if provided
  update public.time_request_details
  set total_hours = v_new_hours,
      reason = coalesce(nullif(trim(p_reason), ''), reason)
  where request_id = p_request_id;

  -- 5. Update requests status to validated
  update public.requests
  set status = 'validated',
      updated_at = now()
  where id = p_request_id;

  -- 6. Process balance adjustment if it is an offset request
  if v_action <> 'none' then
    insert into public.offset_balances (employee_id, balance_hours, updated_at)
    values (v_emp_id, 0, now())
    on conflict (employee_id) do nothing;

    select coalesce(balance_hours, 0)
    into v_current_bal
    from public.offset_balances
    where employee_id = v_emp_id
    for update;

    -- Offset Earn request (e.g. OB/Offset)
    if v_action = 'earn' then
      v_diff := round(v_new_hours - v_old_hours, 2);

      -- Ensure previous base earn transaction exists in offset_transactions for complete audit trail
      if not exists (
        select 1 from public.offset_transactions
        where request_id = p_request_id and transaction_type in ('earn', 'credit')
      ) and (v_old_hours > 0 or v_new_hours > 0) then
        insert into public.offset_transactions (
          employee_id,
          request_id,
          transaction_type,
          hours,
          balance_after,
          created_at
        )
        values (
          v_emp_id,
          p_request_id,
          'earn',
          greatest(v_old_hours, v_new_hours),
          v_current_bal,
          coalesce(v_request.final_approved_at, v_request.submitted_at, now() - interval '1 second')
        );
      end if;

      if v_diff < 0 then
        -- Deduction from previous total hours (e.g. 5.0h -> 3.0h = -2.0h deduction, or on re-validation)
        v_new_bal := greatest(0, round(v_current_bal + v_diff, 2));

        update public.offset_balances
        set balance_hours = v_new_bal,
            updated_at = now()
        where employee_id = v_emp_id;

        insert into public.offset_transactions (
          employee_id,
          request_id,
          transaction_type,
          hours,
          balance_after,
          created_at
        )
        values (
          v_emp_id,
          p_request_id,
          'deduct',
          v_diff, -- negative value, e.g. -2.0
          v_new_bal,
          now()
        );
      elsif v_diff > 0 then
        -- Addition to previous total hours (e.g. 3.0h -> 4.0h = +1.0h addition on re-validation)
        v_new_bal := round(v_current_bal + v_diff, 2);

        update public.offset_balances
        set balance_hours = v_new_bal,
            updated_at = now()
        where employee_id = v_emp_id;

        insert into public.offset_transactions (
          employee_id,
          request_id,
          transaction_type,
          hours,
          balance_after,
          created_at
        )
        values (
          v_emp_id,
          p_request_id,
          'adjustment',
          v_diff,
          v_new_bal,
          now()
        );
      end if;

    elsif v_action = 'use' then
      -- Use Offset request
      -- If new hours < old hours, employee used less offset, so refund/add back difference
      -- If new hours > old hours, employee used more offset, so deduct extra
      v_diff := round(v_old_hours - v_new_hours, 2);

      if v_diff > 0 then
        -- Refund / add back difference
        v_new_bal := round(v_current_bal + v_diff, 2);

        update public.offset_balances
        set balance_hours = v_new_bal,
            updated_at = now()
        where employee_id = v_emp_id;

        insert into public.offset_transactions (
          employee_id,
          request_id,
          transaction_type,
          hours,
          balance_after,
          created_at
        )
        values (
          v_emp_id,
          p_request_id,
          'adjustment',
          v_diff,
          v_new_bal,
          now()
        );
      elsif v_diff < 0 then
        -- Used more offset, deduct difference
        v_new_bal := greatest(0, round(v_current_bal - abs(v_diff), 2));

        update public.offset_balances
        set balance_hours = v_new_bal,
            updated_at = now()
        where employee_id = v_emp_id;

        insert into public.offset_transactions (
          employee_id,
          request_id,
          transaction_type,
          hours,
          balance_after,
          created_at
        )
        values (
          v_emp_id,
          p_request_id,
          'deduct',
          -abs(v_diff),
          v_new_bal,
          now()
        );
      end if;
    end if;

    -- Audit log
    if v_actor_profile_id is not null then
      insert into public.audit_logs (
        actor_user_profile_id,
        action,
        entity_type,
        entity_id,
        metadata
      )
      values (
        v_actor_profile_id,
        case when v_is_revalidation then 'revalidate_esarf_request' else 'validate_esarf_request' end,
        'request',
        p_request_id,
        jsonb_build_object(
          'employee_id', v_emp_id,
          'old_total_hours', v_old_hours,
          'new_total_hours', v_new_hours,
          'diff_hours', v_diff,
          'action', v_action,
          'is_revalidation', v_is_revalidation
        )
      );
    end if;
  end if;

  if v_is_revalidation then
    return 'ESARF request re-validated successfully.';
  else
    return 'ESARF request validated successfully.';
  end if;
end;
$$;

grant execute on function public.admin_validate_esarf_request(uuid, numeric, text) to authenticated;
grant execute on function public.admin_validate_esarf_request(uuid, numeric, text) to anon;
grant execute on function public.admin_validate_esarf_request(uuid, numeric, text) to service_role;

-- 2. Update public.get_my_offset_history() to format validation & re-validation deductions cleanly
-- Super admin edited total hours transactions display:
--   Title: "Offset Added" or "Offset Deducted"
--   Subtitle: "Admin offset balance adjustment"
create or replace function public.get_my_offset_history()
returns table (
  id text,
  transaction_type text,
  category text,
  title text,
  subtitle text,
  hours numeric,
  balance_after numeric,
  created_at timestamptz,
  request_id uuid,
  request_status text,
  reason text,
  date_from date,
  date_to date
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee_id uuid;
begin
  if auth.uid() is null then
    return;
  end if;

  select employee_id into v_employee_id
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  if v_employee_id is null then
    return;
  end if;

  return query
  select
    ot.id::text,
    ot.transaction_type,
    case
      -- 1. Request-linked admin adjustments (hours edited by super admin)
      when ot.request_id is not null and (ot.transaction_type in ('deduct', 'deduction') or (ot.transaction_type = 'adjustment' and coalesce(ot.hours, 0) < 0)) then 'use'
      when ot.request_id is not null and ot.transaction_type in ('adjustment', 'add') and coalesce(ot.hours, 0) > 0 and coalesce(r.status, '') not in ('rejected', 'cancelled') then 'earn'
      when ot.request_id is not null and ot.transaction_type in ('earn', 'credit') and exists (
        select 1 from public.offset_transactions prev_ot
        where prev_ot.request_id = ot.request_id and prev_ot.id <> ot.id and prev_ot.created_at < ot.created_at
      ) then 'earn'

      -- 2. Direct admin adjustments (unlinked)
      when ot.request_id is null and (ot.transaction_type in ('deduct', 'deduction') or coalesce(ot.hours, 0) < 0) then 'use'
      when ot.request_id is null and (ot.transaction_type in ('earn', 'add', 'credit', 'adjustment') or coalesce(ot.hours, 0) > 0) then 'earn'

      -- 3. Request refunds upon rejection
      when ot.request_id is not null and (ot.transaction_type in ('refund') or (ot.transaction_type = 'adjustment' and coalesce(r.status, '') in ('rejected', 'cancelled'))) then 'refund'

      -- 4. Regular request transactions
      when ot.transaction_type = 'use' or coalesce(ot.hours, 0) < 0 then 'use'
      when ot.transaction_type in ('earn', 'credit') then 'earn'
      else 'adjustment'
    end as category,
    case
      -- Request-linked admin edits (hours edited by super admin)
      when ot.request_id is not null and (ot.transaction_type in ('deduct', 'deduction') or (ot.transaction_type = 'adjustment' and coalesce(ot.hours, 0) < 0)) then 'Offset Deducted'
      when ot.request_id is not null and ot.transaction_type in ('adjustment', 'add') and coalesce(ot.hours, 0) > 0 and coalesce(r.status, '') not in ('rejected', 'cancelled') then 'Offset Added'
      when ot.request_id is not null and ot.transaction_type in ('earn', 'credit') and exists (
        select 1 from public.offset_transactions prev_ot
        where prev_ot.request_id = ot.request_id and prev_ot.id <> ot.id and prev_ot.created_at < ot.created_at
      ) then 'Offset Added'

      -- Direct admin adjustments (unlinked)
      when ot.request_id is null and (ot.transaction_type in ('deduct', 'deduction') or coalesce(ot.hours, 0) < 0) then 'Offset Deducted'
      when ot.request_id is null and (ot.transaction_type in ('earn', 'add', 'credit', 'adjustment') or coalesce(ot.hours, 0) > 0) then 'Offset Added'

      -- Request refunds upon rejection
      when ot.request_id is not null and (ot.transaction_type in ('refund') or (ot.transaction_type = 'adjustment' and coalesce(r.status, '') in ('rejected', 'cancelled'))) then 'Offset Refunded'

      -- Regular request transactions
      when ot.transaction_type = 'use' then 'Offset Deducted'
      when ot.transaction_type in ('earn', 'credit') then 'Offset Earned'
      else case when coalesce(ot.hours, 0) < 0 then 'Offset Deducted' else 'Offset Added' end
    end as title,
    case
      -- Request-linked admin edits (hours edited by super admin)
      when ot.request_id is not null and (
        ot.transaction_type in ('deduct', 'deduction')
        or (ot.transaction_type in ('adjustment', 'add') and coalesce(r.status, '') not in ('rejected', 'cancelled'))
        or (ot.transaction_type in ('earn', 'credit') and exists (
          select 1 from public.offset_transactions prev_ot
          where prev_ot.request_id = ot.request_id and prev_ot.id <> ot.id and prev_ot.created_at < ot.created_at
        ))
      ) then 'Admin offset balance adjustment'

      -- Direct admin adjustments (unlinked)
      when ot.request_id is null then 'Admin offset balance adjustment'

      -- Request refunds upon rejection
      when ot.request_id is not null and (ot.transaction_type in ('refund') or (ot.transaction_type = 'adjustment' and coalesce(r.status, '') in ('rejected', 'cancelled'))) then 'Credited back (Rejected request)'

      -- Regular request transactions
      when trd.transaction_type is not null and trd.transaction_type <> '' then trd.transaction_type
      when ot.transaction_type = 'use' then 'Use Offset Request'
      when ot.transaction_type in ('earn', 'credit') then 'ESARF Offset Credit'
      else 'Offset Transaction'
    end as subtitle,
    case
      when ot.transaction_type in ('use', 'deduct', 'deduction') or coalesce(ot.hours, 0) < 0 then -abs(coalesce(ot.hours, 0))
      else abs(coalesce(ot.hours, 0))
    end as hours,
    ot.balance_after,
    ot.created_at,
    ot.request_id,
    r.status as request_status,
    coalesce(trd.reason, r.rejected_reason) as reason,
    trd.date_from,
    trd.date_to
  from public.offset_transactions ot
  left join public.requests r on r.id = ot.request_id
  left join public.time_request_details trd on trd.request_id = ot.request_id
  where ot.employee_id = v_employee_id
  order by ot.created_at desc, ot.id desc;
end;
$$;

grant execute on function public.get_my_offset_history() to authenticated;
grant execute on function public.get_my_offset_history() to anon;
grant execute on function public.get_my_offset_history() to service_role;

-- 3. Safe backfill of missing offset_transactions for all approved AND validated offset requests
-- Ensures requests already validated before this migration was applied also have their base offset_transactions
insert into public.offset_transactions (
  employee_id,
  request_id,
  transaction_type,
  hours,
  balance_after,
  created_at
)
select
  r.submitted_by_employee_id,
  r.id,
  'earn',
  abs(coalesce(trd.total_hours, 0)),
  ob.balance_hours,
  coalesce(r.final_approved_at, r.submitted_at, now())
from public.requests r
join public.time_request_details trd on trd.request_id = r.id
left join public.request_types rt on rt.id = r.request_type_id
left join public.offset_balances ob on ob.employee_id = r.submitted_by_employee_id
where r.status in ('approved', 'validated')
  and (
    coalesce(rt.code, '') = 'offset_earn'
    or coalesce(rt.affects_offset_balance, '') = 'earn'
    or lower(coalesce(trd.transaction_type, '')) like '%offset%'
    or lower(coalesce(trd.reason, '')) like '%(offset)%'
  )
  and coalesce(rt.code, '') <> 'use_offset'
  and coalesce(rt.affects_offset_balance, '') <> 'use'
  and lower(coalesce(trd.transaction_type, '')) not like '%use%offset%'
  and lower(coalesce(trd.reason, '')) not like '%(use offset)%'
  and coalesce(trd.total_hours, 0) > 0
  and not exists (
    select 1
    from public.offset_transactions ot
    where ot.request_id = r.id
  );

notify pgrst, 'reload schema';
