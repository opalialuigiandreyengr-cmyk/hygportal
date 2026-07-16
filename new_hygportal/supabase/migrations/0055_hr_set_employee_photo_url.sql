create or replace function public.hr_set_employee_photo_url(
  p_username text default null,
  p_password text default null,
  p_employee_id uuid default null,
  p_photo_url text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (
    public.is_hr_staff()
    or (
      lower(trim(coalesce(p_username, ''))) = 'hyg_hr'
      and coalesce(p_password, '') = 'hyg_hr2026'
    )
  ) then
    raise exception 'HR access is required.';
  end if;

  if p_employee_id is null then
    raise exception 'Employee id is required.';
  end if;

  if not exists (
    select 1
    from public.employees e
    where e.id = p_employee_id
  ) then
    raise exception 'Employee was not found.';
  end if;

  update public.employees
  set
    photo_url = nullif(trim(coalesce(p_photo_url, '')), ''),
    updated_at = now()
  where id = p_employee_id;

  return p_employee_id;
end;
$$;

grant execute on function public.hr_set_employee_photo_url(text, text, uuid, text) to anon, authenticated;

notify pgrst, 'reload schema';
