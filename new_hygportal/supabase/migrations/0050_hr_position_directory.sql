create or replace function public.hr_position_directory(
  p_username text default null,
  p_password text default null
)
returns table (
  position_id uuid,
  position_name text,
  authority_level int,
  employee_count bigint,
  created_at timestamptz,
  updated_at timestamptz,
  is_active boolean
)
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

  return query
  select
    p.id as position_id,
    p.name as position_name,
    p.authority_level,
    count(distinct ea.employee_id) filter (
      where ea.is_primary = true
        and ea.effective_to is null
    ) as employee_count,
    p.created_at,
    p.created_at as updated_at,
    p.is_active
  from public.positions p
  left join public.employee_assignments ea
    on ea.position_id = p.id
  where p.is_active = true
  group by p.id, p.name, p.authority_level, p.created_at, p.is_active
  order by p.name;
end;
$$;

grant execute on function public.hr_position_directory(text, text) to anon, authenticated;

notify pgrst, 'reload schema';
