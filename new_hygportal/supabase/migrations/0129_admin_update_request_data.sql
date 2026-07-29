-- Admin: update editable fields of a request row
-- ESARF/Leave → time_request_details / leave_request_details
-- Perk        → employee_perk_requests

create or replace function public.admin_update_request_data(
  p_request_id     uuid,
  p_is_perk        boolean       default false,
  -- ESARF / time fields
  p_date_from      date          default null,
  p_date_to        date          default null,
  p_time_from      time          default null,
  p_time_to        time          default null,
  p_total_hours    numeric       default null,
  -- Leave fields
  p_leave_type     text          default null,
  p_leave_category text          default null,
  p_start_date     date          default null,
  p_end_date       date          default null,
  p_total_days     numeric       default null,
  -- Shared
  p_reason         text          default null,
  -- Perk fields
  p_product_name   text          default null,
  p_quantity       int           default null,
  p_amount         numeric       default null,
  p_final_amount   numeric       default null,
  p_txn_date       date          default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_is_perk then
    update public.employee_perk_requests
    set
      product_name     = coalesce(p_product_name,   product_name),
      quantity         = coalesce(p_quantity,        quantity),
      amount           = coalesce(p_amount,          amount),
      final_amount     = coalesce(p_final_amount,    final_amount),
      transaction_date = coalesce(p_txn_date,        transaction_date)
    where id = p_request_id;
  else
    -- Update time_request_details if the row exists (ESARF)
    if exists (select 1 from public.time_request_details where request_id = p_request_id) then
      update public.time_request_details
      set
        date_from   = coalesce(p_date_from,   date_from),
        date_to     = coalesce(p_date_to,     date_to),
        time_from   = coalesce(p_time_from,   time_from),
        time_to     = coalesce(p_time_to,     time_to),
        total_hours = coalesce(p_total_hours, total_hours),
        reason      = coalesce(p_reason,      reason)
      where request_id = p_request_id;
    end if;

    -- Update leave_request_details if the row exists (Leave)
    if exists (select 1 from public.leave_request_details where request_id = p_request_id) then
      update public.leave_request_details
      set
        leave_type     = coalesce(p_leave_type,     leave_type),
        leave_category = coalesce(p_leave_category, leave_category),
        start_date     = coalesce(p_start_date,     start_date),
        end_date       = coalesce(p_end_date,       end_date),
        total_days     = coalesce(p_total_days,     total_days),
        reason         = coalesce(p_reason,         reason)
      where request_id = p_request_id;
    end if;
  end if;

  return 'Request updated successfully.';
end;
$$;

grant execute on function public.admin_update_request_data(
  uuid, boolean,
  date, date, time, time, numeric,
  text, text, date, date, numeric,
  text,
  text, int, numeric, numeric, date
) to authenticated;

grant execute on function public.admin_update_request_data(
  uuid, boolean,
  date, date, time, time, numeric,
  text, text, date, date, numeric,
  text,
  text, int, numeric, numeric, date
) to service_role;

notify pgrst, 'reload schema';
