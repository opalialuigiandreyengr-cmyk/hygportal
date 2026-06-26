create or replace function public.resolve_login_email(p_username text)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email text;
begin
  if lower(trim(p_username)) = 'hygportal' then
    return 'hygportal@gmail.com';
  end if;

  select au.email
  into v_email
  from public.user_profiles up
  join auth.users au on au.id = up.auth_user_id
  where lower(up.username) = lower(trim(p_username))
    and up.is_active = true
  limit 1;

  if v_email is null then
    raise exception 'Username was not found.';
  end if;

  return v_email;
end;
$$;

grant execute on function public.resolve_login_email(text) to anon, authenticated;
