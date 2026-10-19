-- Migration 0198: Soft Delete Balance Transactions from Table View
-- Allows admins to remove/hide balance transactions from the table view
-- without deleting the underlying records from requests, leave_transactions, offset_transactions, or audit_logs.

create table if not exists public.hidden_balance_transactions (
  transaction_id text primary key,
  hidden_by uuid references auth.users(id),
  reason text default 'Removed from table by admin',
  is_hard_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.hidden_balance_transactions add column if not exists is_hard_deleted boolean not null default false;

alter table public.hidden_balance_transactions enable row level security;

drop policy if exists "Admins can view hidden balance transactions" on public.hidden_balance_transactions;
create policy "Admins can view hidden balance transactions"
  on public.hidden_balance_transactions for select
  to authenticated
  using (true);

drop policy if exists "Admins can insert hidden balance transactions" on public.hidden_balance_transactions;
create policy "Admins can insert hidden balance transactions"
  on public.hidden_balance_transactions for insert
  to authenticated
  with check (true);

drop policy if exists "Admins can update hidden balance transactions" on public.hidden_balance_transactions;
create policy "Admins can update hidden balance transactions"
  on public.hidden_balance_transactions for update
  to authenticated
  using (true)
  with check (true);

drop policy if exists "Admins can delete hidden balance transactions" on public.hidden_balance_transactions;
create policy "Admins can delete hidden balance transactions"
  on public.hidden_balance_transactions for delete
  to authenticated
  using (true);

grant all on public.hidden_balance_transactions to authenticated, anon, service_role;

-- RPC to soft delete a balance transaction
create or replace function public.admin_soft_delete_balance_transaction(
  p_transaction_id text,
  p_reason text default 'Removed from table by admin'
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_transaction_id is null or trim(p_transaction_id) = '' then
    return false;
  end if;

  insert into public.hidden_balance_transactions (transaction_id, hidden_by, reason, is_hard_deleted)
  values (p_transaction_id, auth.uid(), coalesce(p_reason, 'Removed from table by admin'), false)
  on conflict (transaction_id) do update
  set reason = excluded.reason,
      is_hard_deleted = false,
      created_at = now();

  return true;
end;
$$;

grant execute on function public.admin_soft_delete_balance_transaction(text, text) to authenticated, anon, service_role;

-- RPC to restore a soft-deleted balance transaction
create or replace function public.admin_restore_balance_transaction(p_transaction_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.hidden_balance_transactions
  where transaction_id = p_transaction_id;
  return true;
end;
$$;

grant execute on function public.admin_restore_balance_transaction(text) to authenticated, anon, service_role;

-- RPC to permanently hard-delete a balance transaction record from the database
create or replace function public.admin_hard_delete_balance_transaction(p_transaction_id text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uuid uuid;
  v_raw_id text;
begin
  if p_transaction_id is null or trim(p_transaction_id) = '' then
    return false;
  end if;

  -- 1. If it is a synthetic entitlement row (policy_grant_), mark it as permanently purged so it never appears again
  if p_transaction_id like 'policy_grant_%' then
    insert into public.hidden_balance_transactions (transaction_id, hidden_by, reason, is_hard_deleted)
    values (p_transaction_id, auth.uid(), 'Permanently deleted by admin', true)
    on conflict (transaction_id) do update
    set is_hard_deleted = true,
        reason = 'Permanently deleted by admin';
    return true;
  end if;

  -- 2. Remove from hidden_balance_transactions
  delete from public.hidden_balance_transactions
  where transaction_id = p_transaction_id;

  -- 3. Detect source and delete underlying record
  if p_transaction_id like 'offset_%' then
    v_raw_id := substring(p_transaction_id from 8);
    begin
      v_uuid := v_raw_id::uuid;
      delete from public.offset_transactions where id = v_uuid;
    exception when others then
      null;
    end;
  elsif p_transaction_id like 'ot_%' then
    v_raw_id := substring(p_transaction_id from 4);
    begin
      v_uuid := v_raw_id::uuid;
      delete from public.offset_transactions where id = v_uuid;
    exception when others then
      null;
    end;
  elsif p_transaction_id like 'leave_%' then
    v_raw_id := substring(p_transaction_id from 7);
    begin
      v_uuid := v_raw_id::uuid;
      delete from public.leave_transactions where id = v_uuid;
    exception when others then
      null;
    end;
  elsif p_transaction_id like 'audit_%' then
    v_raw_id := substring(p_transaction_id from 7);
    begin
      v_uuid := v_raw_id::uuid;
      delete from public.audit_logs where id = v_uuid;
    exception when others then
      null;
    end;
  elsif p_transaction_id like 'req_%' then
    v_raw_id := substring(p_transaction_id from 5);
    begin
      v_uuid := v_raw_id::uuid;
      delete from public.requests where id = v_uuid;
    exception when others then
      null;
    end;
  else
    -- Fallback: try raw uuid delete directly
    begin
      v_uuid := p_transaction_id::uuid;
      delete from public.offset_transactions where id = v_uuid;
      delete from public.leave_transactions where id = v_uuid;
    exception when others then
      null;
    end;
  end if;

  return true;
end;
$$;

grant execute on function public.admin_hard_delete_balance_transaction(text) to authenticated, anon, service_role;

notify pgrst, 'reload schema';

