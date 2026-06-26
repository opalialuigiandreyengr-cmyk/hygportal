create or replace function public.verify_employee_for_registration(
  p_first_name text,
  p_last_name text,
  p_middle_name text,
  p_birth_date date,
  p_email text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employee public.employees;
  v_already_registered boolean;
begin
  if nullif(trim(p_first_name), '') is null
    or nullif(trim(p_last_name), '') is null
    or p_birth_date is null then
    raise exception 'First name, last name, and birthday are required.';
  end if;

  select *
  into v_employee
  from public.employees e
  where lower(trim(e.first_name)) = lower(trim(p_first_name))
    and lower(trim(e.last_name)) = lower(trim(p_last_name))
    and e.birth_date = p_birth_date
  order by e.created_at desc
  limit 1;

  if v_employee.id is null then
    return jsonb_build_object(
      'verified', false,
      'message', 'No employee profile matched the details entered.'
    );
  end if;

  select exists (
    select 1
    from public.user_profiles up
    where up.employee_id = v_employee.id
  )
  into v_already_registered;

  if v_already_registered then
    return jsonb_build_object(
      'verified', false,
      'already_registered', true,
      'message', 'This employee profile already has a registered login account.'
    );
  end if;

  return jsonb_build_object(
    'verified', true,
    'employee_id', v_employee.id,
    'employee_no', v_employee.employee_no,
    'full_name', trim(concat_ws(' ', v_employee.first_name, v_employee.middle_name, v_employee.last_name, v_employee.suffix))
  );
end;
$$;

grant execute on function public.verify_employee_for_registration(
  text,
  text,
  text,
  date,
  text
) to anon, authenticated;

create or replace function public.link_employee_login_account(
  p_employee_id uuid,
  p_auth_user_id uuid,
  p_terms_accepted boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
begin
  if p_employee_id is null or p_auth_user_id is null then
    raise exception 'Employee and login account are required.';
  end if;

  if p_terms_accepted is not true then
    raise exception 'Terms and conditions must be accepted.';
  end if;

  if exists (
    select 1
    from public.user_profiles
    where employee_id = p_employee_id
  ) then
    raise exception 'This employee profile already has a registered login account.';
  end if;

  insert into public.user_profiles (
    auth_user_id,
    employee_id,
    app_role,
    is_active
  )
  values (
    p_auth_user_id,
    p_employee_id,
    'employee',
    true
  )
  returning id into v_profile_id;

  return v_profile_id;
end;
$$;

grant execute on function public.link_employee_login_account(uuid, uuid, boolean) to anon, authenticated;
