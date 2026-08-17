drop function if exists public.get_request_details_by_id(uuid);

create function public.get_request_details_by_id(p_request_id uuid)
returns table (
  time_schedule text,
  day_off text,
  payroll_class text,
  transaction_type text
)
language sql
security definer
set search_path = public
as $$
  select
    trd.time_schedule,
    trd.day_off,
    trd.payroll_class,
    trd.transaction_type
  from public.time_request_details trd
  where trd.request_id = p_request_id
  limit 1;
$$;

grant execute on function public.get_request_details_by_id(uuid) to authenticated;

notify pgrst, 'reload schema';
