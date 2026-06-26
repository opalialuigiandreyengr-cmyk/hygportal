create or replace function public.employee_company_options()
returns table (
  company_name text
)
language sql
security definer
set search_path = public
as $$
  select c.name as company_name
  from public.companies c
  where c.is_active = true
  order by c.name;
$$;

grant execute on function public.employee_company_options() to anon, authenticated;
