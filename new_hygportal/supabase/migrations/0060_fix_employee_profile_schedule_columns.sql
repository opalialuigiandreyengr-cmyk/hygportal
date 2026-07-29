alter table public.employee_profile_details
  add column if not exists time_schedule text,
  add column if not exists day_off text;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'employee_profile_details'
      and column_name = 'time_scedule'
  ) then
    execute '
      update public.employee_profile_details
      set time_schedule = coalesce(time_schedule, time_scedule)
      where coalesce(time_schedule, '''') = ''''
        and coalesce(time_scedule, '''') <> ''''
    ';
  end if;
end
$$;

notify pgrst, 'reload schema';
