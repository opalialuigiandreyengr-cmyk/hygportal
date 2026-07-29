create or replace function public.position_level_for_profile(p_position text)
returns int
language plpgsql
immutable
as $$
begin
  return case lower(trim(coalesce(p_position, '')))
    when 'crew' then 1
    when 'service crew' then 1
    when 'kitchen crew' then 1
    when 'cashier' then 1
    when 'barista' then 1
    when 'baker' then 1
    when 'cake decorator' then 1
    when 'staff' then 1
    when 'it staff' then 1
    when 'accounting staff' then 1
    when 'inventory staff' then 1
    when 'warehouse staff' then 1
    when 'logistics staff' then 1
    when 'maintenance staff' then 1
    when 'maintenance technician' then 1
    when 'hr staff' then 1
    when 'admin staff' then 1
    when 'marketing staff' then 1
    when 'purchasing staff' then 1
    when 'assistant' then 1
    when 'officer' then 2
    when 'specialist' then 2
    when 'analyst' then 2
    when 'coordinator' then 2
    when 'team leader' then 2
    when 'supervisor' then 2
    when 'area supervisor' then 2
    when 'auditor' then 2
    when 'training officer' then 2
    when 'store manager' then 3
    when 'assistant store manager' then 3
    when 'branch manager' then 3
    when 'department manager' then 3
    when 'it manager' then 3
    when 'cluster manager' then 4
    when 'area manager' then 5
    when 'operations manager' then 5
    when 'director' then 7
    when 'operations director' then 7
    when 'finance director' then 7
    when 'general manager' then 8
    else 1
  end;
end;
$$;

with profile_departments(name) as (
  values
    ('ACCOUNTING AND INVENTORY'),
    ('ADMIN'),
    ('IT'),
    ('LOGISTICS'),
    ('MAINTENANCE'),
    ('OPERATIONS'),
    ('Accounting'),
    ('Inventory'),
    ('HR'),
    ('Marketing'),
    ('Customer Service'),
    ('Purchasing')
)
insert into public.functions (name, code)
select
  name,
  upper(regexp_replace(name, '[^a-zA-Z0-9]+', '_', 'g'))
from profile_departments
on conflict (name) do nothing;

with profile_departments(name) as (
  values
    ('ACCOUNTING AND INVENTORY'),
    ('ADMIN'),
    ('IT'),
    ('LOGISTICS'),
    ('MAINTENANCE'),
    ('OPERATIONS'),
    ('Accounting'),
    ('Inventory'),
    ('HR'),
    ('Marketing'),
    ('Customer Service'),
    ('Purchasing')
)
insert into public.departments (name, function_id)
select d.name, f.id
from profile_departments d
join public.functions f on lower(f.name) = lower(d.name)
on conflict (name) do update
set is_active = true;

with profile_positions(name) as (
  values
    ('Crew'),
    ('Service Crew'),
    ('Kitchen Crew'),
    ('Cashier'),
    ('Barista'),
    ('Baker'),
    ('Cake Decorator'),
    ('Supervisor'),
    ('Area Supervisor'),
    ('Store Manager'),
    ('Assistant Store Manager'),
    ('Branch Manager'),
    ('Department Manager'),
    ('Cluster Manager'),
    ('Area Manager'),
    ('Operations Manager'),
    ('Operations Director'),
    ('Finance Director'),
    ('General Manager'),
    ('Staff'),
    ('IT Staff'),
    ('IT Manager'),
    ('Accounting Staff'),
    ('Inventory Staff'),
    ('Warehouse Staff'),
    ('Logistics Staff'),
    ('Maintenance Staff'),
    ('Maintenance Technician'),
    ('HR Staff'),
    ('Admin Staff'),
    ('Marketing Staff'),
    ('Purchasing Staff'),
    ('Officer'),
    ('Specialist'),
    ('Analyst'),
    ('Coordinator'),
    ('Assistant'),
    ('Team Leader'),
    ('Auditor'),
    ('Training Officer'),
    ('Director')
)
insert into public.positions (name, authority_level)
select name, public.position_level_for_profile(name)
from profile_positions
on conflict (name) do update
set
  authority_level = excluded.authority_level,
  is_active = true;

with department_position_names(department_name, position_name) as (
  values
    ('OPERATIONS', 'Crew'),
    ('OPERATIONS', 'Service Crew'),
    ('OPERATIONS', 'Kitchen Crew'),
    ('OPERATIONS', 'Cashier'),
    ('OPERATIONS', 'Barista'),
    ('OPERATIONS', 'Baker'),
    ('OPERATIONS', 'Cake Decorator'),
    ('OPERATIONS', 'Supervisor'),
    ('OPERATIONS', 'Area Supervisor'),
    ('OPERATIONS', 'Store Manager'),
    ('OPERATIONS', 'Assistant Store Manager'),
    ('OPERATIONS', 'Branch Manager'),
    ('OPERATIONS', 'Department Manager'),
    ('OPERATIONS', 'Cluster Manager'),
    ('OPERATIONS', 'Area Manager'),
    ('OPERATIONS', 'Operations Manager'),
    ('OPERATIONS', 'Operations Director'),
    ('IT', 'IT Staff'),
    ('IT', 'IT Manager'),
    ('IT', 'Staff'),
    ('IT', 'Officer'),
    ('IT', 'Specialist'),
    ('IT', 'Analyst'),
    ('ACCOUNTING AND INVENTORY', 'Accounting Staff'),
    ('ACCOUNTING AND INVENTORY', 'Inventory Staff'),
    ('ACCOUNTING AND INVENTORY', 'Warehouse Staff'),
    ('ACCOUNTING AND INVENTORY', 'Analyst'),
    ('ACCOUNTING AND INVENTORY', 'Officer'),
    ('ACCOUNTING AND INVENTORY', 'Supervisor'),
    ('ACCOUNTING AND INVENTORY', 'Auditor'),
    ('ACCOUNTING AND INVENTORY', 'Finance Director'),
    ('Accounting', 'Accounting Staff'),
    ('Accounting', 'Analyst'),
    ('Accounting', 'Officer'),
    ('Accounting', 'Auditor'),
    ('Accounting', 'Finance Director'),
    ('Inventory', 'Inventory Staff'),
    ('Inventory', 'Warehouse Staff'),
    ('Inventory', 'Coordinator'),
    ('Inventory', 'Supervisor'),
    ('LOGISTICS', 'Logistics Staff'),
    ('LOGISTICS', 'Warehouse Staff'),
    ('LOGISTICS', 'Coordinator'),
    ('LOGISTICS', 'Supervisor'),
    ('MAINTENANCE', 'Maintenance Staff'),
    ('MAINTENANCE', 'Maintenance Technician'),
    ('MAINTENANCE', 'Coordinator'),
    ('MAINTENANCE', 'Supervisor'),
    ('ADMIN', 'Admin Staff'),
    ('ADMIN', 'Assistant'),
    ('ADMIN', 'Officer'),
    ('ADMIN', 'Supervisor'),
    ('HR', 'HR Staff'),
    ('HR', 'Officer'),
    ('HR', 'Coordinator'),
    ('HR', 'Training Officer'),
    ('Marketing', 'Marketing Staff'),
    ('Marketing', 'Specialist'),
    ('Marketing', 'Coordinator'),
    ('Customer Service', 'Staff'),
    ('Customer Service', 'Team Leader'),
    ('Customer Service', 'Supervisor'),
    ('Purchasing', 'Purchasing Staff'),
    ('Purchasing', 'Officer'),
    ('Purchasing', 'Coordinator')
)
insert into public.department_positions (department_id, position_id)
select d.id, p.id
from department_position_names dpn
join public.departments d on lower(d.name) = lower(dpn.department_name)
join public.positions p on lower(p.name) = lower(dpn.position_name)
on conflict do nothing;

notify pgrst, 'reload schema';
