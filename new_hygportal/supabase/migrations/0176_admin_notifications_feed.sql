-- Migration 0176: Admin notifications feed
-- Provides secure RPC for admin and HR roles to retrieve system notifications joined with employee details.

create or replace function public.admin_get_notifications(p_limit int default 100)
returns table (
  id uuid,
  employee_id uuid,
  user_profile_id uuid,
  title text,
  message text,
  link_type text,
  link_id uuid,
  is_read boolean,
  created_at timestamptz,
  employee_name text,
  employee_no text,
  employee_photo text,
  department_name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
begin
  select app_role into v_role
  from public.user_profiles
  where auth_user_id = auth.uid() and is_active = true;

  if v_role is null or v_role not in ('hr', 'admin', 'super_admin') then
    raise exception 'Admin access required';
  end if;

  return query
  select
    n.id,
    n.employee_id,
    n.user_profile_id,
    n.title,
    n.message,
    n.link_type,
    n.link_id,
    n.is_read,
    n.created_at,
    nullif(trim(concat_ws(' ', e.first_name, e.last_name)), '') as employee_name,
    e.employee_no,
    e.photo_url as employee_photo,
    d.name as department_name
  from public.notifications n
  left join public.employees e on e.id = n.employee_id
  left join lateral (
    select ea.department_id
    from public.employee_assignments ea
    where ea.employee_id = e.id and ea.is_primary = true
    limit 1
  ) ea on true
  left join public.departments d on d.id = ea.department_id
  order by n.created_at desc
  limit coalesce(p_limit, 100);
end;
$$;

grant execute on function public.admin_get_notifications(int) to authenticated;
grant execute on function public.admin_get_notifications(int) to service_role;

notify pgrst, 'reload schema';
