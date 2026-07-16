create or replace function public.hr_set_employee_status(
  p_username text,
  p_password text,
  p_employee_id uuid,
  p_employment_status text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text := lower(trim(coalesce(p_employment_status, '')));
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

  if v_status not in ('pending', 'active', 'inactive') then
    raise exception 'Invalid employment status.';
  end if;

  update public.employees
  set
    employment_status = v_status,
    updated_at = timezone('utc', now())
  where id = p_employee_id;

  if not found then
    raise exception 'Employee profile was not found.';
  end if;

  return p_employee_id;
end;
$$;

grant execute on function public.hr_set_employee_status(text, text, uuid, text) to anon, authenticated;
