-- Clean all current portal data while keeping the database schema.
-- Run this once in the Supabase SQL editor when you want to remove test data.
-- After running this file, run seed/0001_core_seed.sql again to restore reference data.

truncate table
  public.notifications,
  public.leave_transactions,
  public.leave_balances,
  public.offset_transactions,
  public.offset_balances,
  public.leave_request_details,
  public.time_request_details,
  public.request_approval_steps,
  public.requests,
  public.authority_assignments,
  public.employee_assignments,
  public.user_profiles,
  public.employees,
  public.stores,
  public.clusters,
  public.areas,
  public.departments,
  public.companies
restart identity cascade;

do $$
begin
  if to_regclass('public.employee_profile_details') is not null then
    execute 'truncate table public.employee_profile_details restart identity cascade';
  end if;
end $$;

delete from public.positions
where name in (
  'Assistant Manager',
  'IT Staff',
  'Payroll Officer',
  'Maintenance Staff',
  'Logistic Driver/Checker',
  'Purchaser'
);

delete from public.companies
where code = 'HYGTEST'
   or name ilike 'HYG Test%'
   or name ilike 'Test %';
