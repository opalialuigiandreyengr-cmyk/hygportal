-- Assign employee numbers to existing employees that do not have one yet.
-- Format: MMDDYYYY-## based on the employee's primary assignment effective_from date.
-- Example: 09262002-01, 09262002-02

with missing_numbers as (
  select
    e.id as employee_id,
    coalesce(
      (
        select ea.effective_from
        from public.employee_assignments ea
        where ea.employee_id = e.id
          and ea.is_primary = true
        order by
          case when ea.effective_to is null then 0 else 1 end,
          ea.effective_from asc,
          ea.created_at asc
        limit 1
      ),
      e.created_at::date,
      current_date
    ) as hired_date,
    e.created_at,
    e.id
  from public.employees e
  where nullif(trim(coalesce(e.employee_no, '')), '') is null
),
existing_max as (
  select
    left(e.employee_no, 8) as prefix,
    max(nullif(split_part(e.employee_no, '-', 2), '')::int) as max_sequence
  from public.employees e
  where e.employee_no ~ '^[0-9]{8}-[0-9]+$'
  group by left(e.employee_no, 8)
),
numbered as (
  select
    mn.employee_id,
    to_char(mn.hired_date, 'MMDDYYYY') as prefix,
    row_number() over (
      partition by mn.hired_date
      order by mn.created_at asc, mn.id asc
    ) as new_sequence
  from missing_numbers mn
)
update public.employees e
set
  employee_no = numbered.prefix || '-' || lpad((coalesce(existing_max.max_sequence, 0) + numbered.new_sequence)::text, 2, '0'),
  updated_at = now()
from numbered
left join existing_max on existing_max.prefix = numbered.prefix
where e.id = numbered.employee_id;
