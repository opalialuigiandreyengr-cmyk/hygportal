create or replace function public.resolve_login_email(p_username text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_identifier text := lower(trim(p_username));
  v_email text;
  v_employee_id uuid;
begin
  if v_identifier = 'hygportal' then
    return 'hygportal@gmail.com';
  end if;

  select au.email
  into v_email
  from public.user_profiles up
  join auth.users au on au.id = up.auth_user_id
  where lower(up.username) = v_identifier
    and up.is_active = true
  limit 1;

  if v_email is not null then
    return v_email;
  end if;

  select e.id
  into v_employee_id
  from public.employees e
  where lower(trim(coalesce(e.email, ''))) = v_identifier
  limit 1;

  if v_employee_id is not null
    and not exists (
      select 1
      from public.user_profiles up
      where up.employee_id = v_employee_id
    ) then
    raise exception 'Employee profile found but no login account is registered yet.';
  end if;

  raise exception 'Username was not found.';
end;
$$;

grant execute on function public.resolve_login_email(text) to anon, authenticated;
