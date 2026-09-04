-- Fix foreign key constraint violations when deleting requests
-- Alter offset_transactions and leave_transactions to CASCADE on delete of requests

alter table public.offset_transactions
  drop constraint if exists offset_transactions_request_id_fkey,
  add constraint offset_transactions_request_id_fkey
    foreign key (request_id)
    references public.requests(id)
    on delete cascade;

alter table public.leave_transactions
  drop constraint if exists leave_transactions_request_id_fkey,
  add constraint leave_transactions_request_id_fkey
    foreign key (request_id)
    references public.requests(id)
    on delete cascade;

-- Update admin_delete_request to explicitly delete related rows before deleting from requests
create or replace function public.admin_delete_request(
  p_request_id uuid,
  p_is_perk boolean default false
)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_is_perk then
    -- Perk request: single table
    delete from public.employee_perk_requests where id = p_request_id;
  else
    -- ESARF / Leave: delete related child records and transactions, then the request
    delete from public.approval_push_outbox where request_id = p_request_id;
    delete from public.offset_transactions where request_id = p_request_id;
    delete from public.leave_transactions where request_id = p_request_id;
    delete from public.time_request_details where request_id = p_request_id;
    delete from public.leave_request_details where request_id = p_request_id;
    delete from public.request_approval_steps where request_id = p_request_id;
    delete from public.requests where id = p_request_id;
  end if;

  return 'Request deleted successfully.';
end;
$$;

grant execute on function public.admin_delete_request(uuid, boolean) to authenticated;
grant execute on function public.admin_delete_request(uuid, boolean) to anon;
grant execute on function public.admin_delete_request(uuid, boolean) to service_role;

notify pgrst, 'reload schema';
