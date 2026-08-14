-- Backfill existing time_request_details rows where time_schedule, day_off, or payroll_class are NULL
update public.time_request_details trd
set
  time_schedule = coalesce(
    nullif(trim(trd.time_schedule), ''),
    case
      when trd.time_from is not null and trd.time_to is not null
      then to_char(trd.time_from, 'HH12:MI AM') || ' - ' || to_char(trd.time_to, 'HH12:MI AM')
      else '09:00AM - 06:00PM'
    end
  ),
  day_off = coalesce(
    nullif(trim(trd.day_off), ''),
    'Sun'
  ),
  payroll_class = coalesce(
    nullif(trim(trd.payroll_class), ''),
    'Rank and File'
  )
where trd.time_schedule is null
   or trd.day_off is null
   or trd.payroll_class is null;

notify pgrst, 'reload schema';
