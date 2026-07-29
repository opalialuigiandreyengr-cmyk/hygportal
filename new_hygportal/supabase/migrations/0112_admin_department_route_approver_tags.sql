-- Include tagged approver names in the admin approval route list so mobile can
-- show the same route meaning as the approver assignment screen.

drop function if exists public.admin_department_approval_ladders();

create or replace function public.admin_department_approval_ladders()
returns table (
  department_id uuid,
  department_name text,
  route_levels int[],
  route_roles jsonb,
  route_approvers jsonb
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_super_admin() then
    raise exception 'Admin access is required.';
  end if;

  return query
  select
    d.id as department_id,
    d.name as department_name,
    coalesce(
      array_agg(l.authority_level order by l.authority_level)
        filter (where l.authority_level is not null and l.authority_level > 1),
      '{}'::int[]
    ) as route_levels,
    coalesce(
      jsonb_object_agg(
        l.authority_level::text,
        jsonb_build_object(
          'position_id', p.id,
          'position_name', p.name
        )
      ) filter (where l.authority_level > 1 and p.id is not null),
      '{}'::jsonb
    ) as route_roles,
    coalesce(
      (
        select jsonb_object_agg(level_approvers.level_key, level_approvers.names)
        from (
          select
            dl.authority_level::text as level_key,
            coalesce(
              (
                select jsonb_agg(approver_names.full_name order by approver_names.full_name)
                from (
                  select distinct
                    nullif(trim(concat_ws(' ', e.first_name, e.middle_name, e.last_name, e.suffix)), '') as full_name
                  from public.authority_assignments aa
                  join public.employees e on e.id = aa.employee_id
                  left join public.employee_assignments ea on ea.employee_id = e.id
                    and ea.is_primary = true
                    and ea.effective_from <= current_date
                    and (ea.effective_to is null or ea.effective_to >= current_date)
                  where aa.department_id = d.id
                    and aa.authority_level = dl.authority_level
                    and aa.is_active = true
                    and aa.effective_from <= current_date
                    and (aa.effective_to is null or aa.effective_to >= current_date)
                    and (dl.approver_position_id is null or ea.position_id = dl.approver_position_id)
                ) approver_names
                where approver_names.full_name is not null
              ),
              '[]'::jsonb
            ) as names
          from public.department_approval_ladders dl
          where dl.department_id = d.id
            and dl.authority_level > 1
        ) level_approvers
      ),
      '{}'::jsonb
    ) as route_approvers
  from public.departments d
  left join public.department_approval_ladders l on l.department_id = d.id
  left join public.positions p on p.id = l.approver_position_id
  where d.is_active = true
  group by d.id, d.name
  order by d.name;
end;
$$;

grant execute on function public.admin_department_approval_ladders() to authenticated;

notify pgrst, 'reload schema';
