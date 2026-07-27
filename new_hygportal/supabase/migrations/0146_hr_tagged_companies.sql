-- Create table to assign HR users to specific companies
create table if not exists public.hr_company_assignments (
  id uuid primary key default gen_random_uuid(),
  user_profile_id uuid not null references public.user_profiles(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint hr_company_assignments_unique unique (user_profile_id, company_id)
);

-- Enable RLS
alter table public.hr_company_assignments enable row level security;

-- Create policies (idempotent)
do $$
begin
  if not exists (
    select 1 from pg_policies
    where policyname = 'Authenticated users can read hr_company_assignments'
      and tablename = 'hr_company_assignments'
  ) then
    create policy "Authenticated users can read hr_company_assignments"
    on public.hr_company_assignments for select
    to authenticated
    using (true);
  end if;

  if not exists (
    select 1 from pg_policies
    where policyname = 'Admins can manage hr_company_assignments'
      and tablename = 'hr_company_assignments'
  ) then
    create policy "Admins can manage hr_company_assignments"
    on public.hr_company_assignments for all
    to authenticated
    using (
      exists (
        select 1
        from public.user_profiles up
        where up.auth_user_id = auth.uid()
          and up.app_role in ('admin', 'super_admin')
      )
    );
  end if;
end
$$;

-- Update admin_create_unlinked_user
drop function if exists public.admin_create_unlinked_user(text, text, text, text, uuid);

create or replace function public.admin_create_unlinked_user(
  p_username text,
  p_email text,
  p_password text,
  p_app_role text default 'employee',
  p_employee_id uuid default null,
  p_company_ids uuid[] default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_admin record;
  v_username text := nullif(lower(trim(coalesce(p_username, ''))), '');
  v_email text := nullif(lower(trim(coalesce(p_email, ''))), '');
  v_password text := coalesce(p_password, '');
  v_role text := lower(trim(coalesce(p_app_role, 'employee')));
  v_auth_user_id uuid := gen_random_uuid();
  v_profile_id uuid;
begin
  select *
  into v_admin
  from public.admin_desktop_login_check()
  limit 1;

  if v_admin.app_role not in ('admin', 'super_admin') then
    raise exception 'Admin access is required.';
  end if;

  if v_username is null then
    raise exception 'Username is required.';
  end if;

  if v_email is null or v_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Enter a valid email address.';
  end if;

  if length(v_password) < 6 then
    raise exception 'Password must be at least 6 characters.';
  end if;

  if v_role not in ('employee', 'hr', 'admin', 'super_admin') then
    raise exception 'Role must be employee, hr, admin, or super_admin.';
  end if;

  if v_role = 'super_admin' and v_admin.app_role <> 'super_admin' then
    raise exception 'Only a super admin can create a super admin.';
  end if;

  if exists (select 1 from public.user_profiles where lower(username) = v_username) then
    raise exception 'This username is already taken.';
  end if;

  if exists (select 1 from auth.users where lower(email::text) = v_email) then
    raise exception 'This email is already registered.';
  end if;

  if p_employee_id is not null then
    if not exists (select 1 from public.employees where id = p_employee_id) then
      raise exception 'Selected employee was not found.';
    end if;
    if exists (select 1 from public.user_profiles where employee_id = p_employee_id) then
      raise exception 'This employee is already linked to another user.';
    end if;
  end if;

  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    confirmation_token,
    recovery_token,
    email_change,
    email_change_token_new,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    v_auth_user_id,
    'authenticated',
    'authenticated',
    v_email,
    crypt(v_password, gen_salt('bf', 10)),
    now(),
    '',
    '',
    '',
    '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('email_verified', true),
    now(),
    now()
  );

  insert into auth.identities (
    provider_id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  )
  values (
    v_auth_user_id::text,
    v_auth_user_id,
    jsonb_build_object(
      'sub', v_auth_user_id::text,
      'email', v_email,
      'email_verified', true,
      'phone_verified', false
    ),
    'email',
    now(),
    now(),
    now()
  );

  insert into public.user_profiles (
    auth_user_id,
    employee_id,
    username,
    app_role,
    is_active
  )
  values (
    v_auth_user_id,
    p_employee_id,
    v_username,
    v_role,
    true
  )
  returning id into v_profile_id;

  if p_employee_id is not null then
    insert into public.leave_balances (employee_id, annual_credit_days, used_days)
    values (p_employee_id, 7, 0)
    on conflict (employee_id) do nothing;
  end if;

  -- Insert company assignments if company ids are provided
  if p_company_ids is not null then
    declare
      c_id uuid;
    begin
      foreach c_id in array p_company_ids loop
        insert into public.hr_company_assignments (user_profile_id, company_id)
        values (v_profile_id, c_id);
      end loop;
    end;
  end if;

  return v_profile_id;
end;
$$;

grant execute on function public.admin_create_unlinked_user(text, text, text, text, uuid, uuid[]) to authenticated;


-- Update hr_employee_directory to filter by company if HR role
drop function if exists public.hr_employee_directory(text, text);

create or replace function public.hr_employee_directory(
  p_username text default null,
  p_password text default null
)
returns table (
  employee_id uuid,
  employee_no text,
  full_name text,
  first_name text,
  middle_name text,
  last_name text,
  suffix text,
  email text,
  phone text,
  photo_url text,
  employment_status text,
  company_name text,
  department_name text,
  position_name text,
  hired_date date,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_role text;
  v_user_profile_id uuid;
begin
  select app_role, id
  into v_user_role, v_user_profile_id
  from public.user_profiles
  where auth_user_id = auth.uid()
    and is_active = true;

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
    e.id as employee_id,
    e.employee_no,
    trim(concat_ws(
      ' ',
      case
        when lower(trim(coalesce(e.first_name, ''))) in ('', 'n/a', 'na') then null
        else trim(e.first_name)
      end,
      case
        when lower(trim(coalesce(e.middle_name, ''))) in ('', 'n/a', 'na') then null
        else upper(left(trim(e.middle_name), 1)) || '.'
      end,
      case
        when lower(trim(coalesce(e.last_name, ''))) in ('', 'n/a', 'na') then null
        else trim(e.last_name)
      end,
      case
        when lower(trim(coalesce(e.suffix, ''))) in ('', 'n/a', 'na') then null
        else trim(e.suffix)
      end
    )) as full_name,
    e.first_name,
    e.middle_name,
    e.last_name,
    e.suffix,
    e.email,
    e.phone,
    e.photo_url,
    e.employment_status,
    c.name as company_name,
    d.name as department_name,
    p.name as position_name,
    ea.effective_from as hired_date,
    e.created_at
  from public.employees e
  join public.employee_profile_details epd on epd.employee_id = e.id
  left join lateral (
    select *
    from public.employee_assignments current_ea
    where current_ea.employee_id = e.id
      and current_ea.is_primary = true
    order by
      case
        when current_ea.effective_to is null or current_ea.effective_to >= current_date then 0
        else 1
      end,
      current_ea.effective_from desc,
      current_ea.created_at desc
    limit 1
  ) ea on true
  left join public.companies c on c.id = ea.company_id
  left join public.departments d on d.id = ea.department_id
  left join public.positions p on p.id = ea.position_id
  where (
    v_user_role is null
    or v_user_role <> 'hr'
    or ea.company_id in (
      select company_id
      from public.hr_company_assignments
      where user_profile_id = v_user_profile_id
    )
  )
  order by e.created_at desc, e.last_name, e.first_name;
end;
$$;

grant execute on function public.hr_employee_directory(text, text) to anon, authenticated;


-- Update hr_company_directory to filter by company if HR role
drop function if exists public.hr_company_directory(text, text);

create or replace function public.hr_company_directory(
  p_username text default null,
  p_password text default null
)
returns table (
  company_id uuid,
  company_name text,
  company_code text,
  contact_number text,
  address text,
  logo_url text,
  is_active boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_role text;
  v_user_profile_id uuid;
begin
  select up.app_role, up.id
  into v_user_role, v_user_profile_id
  from public.user_profiles up
  where up.auth_user_id = auth.uid()
    and up.is_active = true;

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
    c.id as company_id,
    c.name as company_name,
    c.code as company_code,
    coalesce(nullif(c.contact_number, ''), '-') as contact_number,
    coalesce(nullif(c.address, ''), '-') as address,
    c.logo_url,
    c.is_active
  from public.companies c
  where (
    v_user_role is null
    or v_user_role <> 'hr'
    or not exists (
      select 1
      from public.hr_company_assignments
      where user_profile_id = v_user_profile_id
    )
    or c.id in (
      select company_id
      from public.hr_company_assignments
      where user_profile_id = v_user_profile_id
    )
  )
  order by c.name;
end;
$$;

grant execute on function public.hr_company_directory(text, text) to anon, authenticated;


-- Update admin_get_all_requests to filter by company if HR role
drop function if exists public.admin_get_all_requests();

create or replace function public.admin_get_all_requests()
returns table (
  request_id uuid,
  request_type_code text,
  request_type_name text,
  status text,
  submitted_at timestamptz,
  final_approved_at timestamptz,
  rejected_at timestamptz,
  rejected_reason text,
  employee_id uuid,
  employee_no text,
  employee_name text,
  employee_photo text,
  department_name text,
  position_name text,
  company_name text,
  store_name text,
  date_from date,
  date_to date,
  time_from time,
  time_to time,
  time_schedule text,
  day_off text,
  payroll_class text,
  transaction_type text,
  total_hours numeric,
  leave_type text,
  leave_category text,
  start_date date,
  end_date date,
  total_days numeric,
  paid_days numeric,
  unpaid_days numeric,
  reason text,
  perk_approval_code text,
  perk_amount numeric,
  perk_discount_amount numeric,
  perk_final_amount numeric,
  perk_benefit text,
  perk_product_name text,
  perk_quantity int,
  approval_summary jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_role text;
  v_user_profile_id uuid;
begin
  select app_role, id
  into v_user_role, v_user_profile_id
  from public.user_profiles
  where auth_user_id = auth.uid()
    and is_active = true;

  return query
  with all_requests_raw as (
    -- ESARF time + leave requests
    select
      r.id as request_id,
      rt.code as request_type_code,
      rt.name as request_type_name,
      r.status,
      r.submitted_at,
      r.final_approved_at,
      r.rejected_at,
      r.rejected_reason,
      e.id as employee_id,
      e.employee_no,
      nullif(trim(
        concat_ws(' ',
          e.first_name,
          case when nullif(trim(e.middle_name), '') is not null
               then left(trim(e.middle_name), 1) || '.'
               else null end,
          e.last_name,
          nullif(trim(e.suffix), '')
        )
      ), '') as employee_name,
      e.photo_url as employee_photo,
      d.name as department_name,
      p.name as position_name,
      c.name as company_name,
      s.name as store_name,
      trd.date_from,
      trd.date_to,
      trd.time_from,
      trd.time_to,
      trd.time_schedule,
      trd.day_off,
      trd.payroll_class,
      trd.transaction_type,
      trd.total_hours,
      lrd.leave_type,
      lrd.leave_category,
      lrd.start_date,
      lrd.end_date,
      lrd.total_days,
      lrd.paid_days,
      lrd.unpaid_days,
      coalesce(trd.reason, lrd.reason) as reason,
      null::text as perk_approval_code,
      null::numeric as perk_amount,
      null::numeric as perk_discount_amount,
      null::numeric as perk_final_amount,
      null::text as perk_benefit,
      null::text as perk_product_name,
      null::int as perk_quantity,
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'step_order', ras.step_order,
              'required_level', ras.required_level,
              'status', ras.status,
              'acted_at', ras.acted_at,
              'remarks', ras.remarks,
              'skipped_reason', ras.skipped_reason,
              'approver_name', nullif(trim(
                concat_ws(' ',
                  ae.first_name,
                  case when nullif(trim(ae.middle_name), '') is not null
                       then left(trim(ae.middle_name), 1) || '.'
                       else null end,
                  ae.last_name,
                  nullif(trim(ae.suffix), '')
                )
              ), ''),
              'approver_position_name', ap.name,
              'approver_employee_no', ae.employee_no
            )
            order by ras.step_order asc
          )
          from public.request_approval_steps ras
          left join public.employees ae on ae.id = ras.assigned_approver_employee_id
          left join lateral (
            select ea.position_id
            from public.employee_assignments ea
            where ea.employee_id = ae.id
              and ea.is_primary = true
              and ea.effective_from <= current_date
              and (ea.effective_to is null or ea.effective_to >= current_date)
            order by ea.effective_from desc, ea.created_at desc
            limit 1
          ) aa on true
          left join public.positions ap on ap.id = aa.position_id
          where ras.request_id = r.id
        ),
        '[]'::jsonb
      ) as approval_summary,
      ea.company_id as _filter_cid
    from public.requests r
    join public.request_types rt on rt.id = r.request_type_id
    join public.employees e on e.id = r.submitted_by_employee_id
    left join public.time_request_details trd on trd.request_id = r.id
    left join public.leave_request_details lrd on lrd.request_id = r.id
    left join lateral (
      select ea.department_id, ea.company_id, ea.store_id, ea.position_id
      from public.employee_assignments ea
      where ea.employee_id = e.id
        and ea.is_primary = true
        and ea.effective_from <= current_date
        and (ea.effective_to is null or ea.effective_to >= current_date)
      order by ea.effective_from desc, ea.created_at desc
      limit 1
    ) ea on true
    left join public.departments d on d.id = ea.department_id
    left join public.positions p on p.id = ea.position_id
    left join public.companies c on c.id = ea.company_id
    left join public.stores s on s.id = ea.store_id

    union all

    -- Perk requests (discount / charge)
    select
      pr.id as request_id,
      pr.form_type as request_type_code,
      pr.request_label as request_type_name,
      case when pr.status = 'pending_verification' then 'pending' else pr.status end as status,
      pr.created_at as submitted_at,
      pr.approved_at as final_approved_at,
      null::timestamptz as rejected_at,
      null::text as rejected_reason,
      e.id as employee_id,
      e.employee_no,
      nullif(trim(
        concat_ws(' ',
          e.first_name,
          case when nullif(trim(e.middle_name), '') is not null
               then left(trim(e.middle_name), 1) || '.'
               else null end,
          e.last_name,
          nullif(trim(e.suffix), '')
        )
      ), '') as employee_name,
      e.photo_url as employee_photo,
      d.name as department_name,
      p.name as position_name,
      c.name as company_name,
      s.name as store_name,
      pr.transaction_date as date_from,
      pr.transaction_date as date_to,
      null::time as time_from,
      null::time as time_to,
      null::text as time_schedule,
      null::text as day_off,
      null::text as payroll_class,
      pr.request_label as transaction_type,
      null::numeric as total_hours,
      null::text as leave_type,
      null::text as leave_category,
      null::date as start_date,
      null::date as end_date,
      null::numeric as total_days,
      null::numeric as paid_days,
      null::numeric as unpaid_days,
      pr.product_name as reason,
      pr.approval_code as perk_approval_code,
      pr.amount as perk_amount,
      round(pr.amount - pr.final_amount, 2) as perk_discount_amount,
      pr.final_amount as perk_final_amount,
      case
        when pr.discount_applies then '15% shared cash/credit discount'
        else 'Employee charge'
      end as perk_benefit,
      pr.product_name as perk_product_name,
      pr.quantity as perk_quantity,
      jsonb_build_array(jsonb_build_object(
        'step_order', 1,
        'required_level', 1,
        'status', pr.status,
        'acted_at', pr.approved_at,
        'remarks', null,
        'skipped_reason', null,
        'approver_name', 'Email code verified',
        'approver_position_name', null,
        'approver_employee_no', null
      )) as approval_summary,
      ea.company_id as _filter_cid
    from public.employee_perk_requests pr
    join public.employees e on e.id = pr.submitted_by_employee_id
    left join lateral (
      select ea.department_id, ea.company_id, ea.store_id, ea.position_id
      from public.employee_assignments ea
      where ea.employee_id = e.id
        and ea.is_primary = true
        and ea.effective_from <= current_date
        and (ea.effective_to is null or ea.effective_to >= current_date)
      order by ea.effective_from desc, ea.created_at desc
      limit 1
    ) ea on true
    left join public.departments d on d.id = ea.department_id
    left join public.positions p on p.id = ea.position_id
    left join public.companies c on c.id = ea.company_id
    left join public.stores s on s.id = ea.store_id
  )
  select
    ar.request_id, ar.request_type_code, ar.request_type_name, ar.status,
    ar.submitted_at, ar.final_approved_at, ar.rejected_at, ar.rejected_reason,
    ar.employee_id, ar.employee_no, ar.employee_name, ar.employee_photo,
    ar.department_name, ar.position_name, ar.company_name, ar.store_name,
    ar.date_from, ar.date_to, ar.time_from, ar.time_to,
    ar.time_schedule, ar.day_off, ar.payroll_class, ar.transaction_type, ar.total_hours,
    ar.leave_type, ar.leave_category, ar.start_date, ar.end_date,
    ar.total_days, ar.paid_days, ar.unpaid_days, ar.reason,
    ar.perk_approval_code, ar.perk_amount, ar.perk_discount_amount, ar.perk_final_amount,
    ar.perk_benefit, ar.perk_product_name, ar.perk_quantity,
    ar.approval_summary
  from all_requests_raw ar
  where (
    v_user_role is null
    or v_user_role <> 'hr'
    or not exists (
      select 1
      from public.hr_company_assignments
      where user_profile_id = v_user_profile_id
    )
    or ar._filter_cid in (
      select company_id
      from public.hr_company_assignments
      where user_profile_id = v_user_profile_id
    )
  )
  order by submitted_at desc;
end;
$$;

grant execute on function public.admin_get_all_requests() to authenticated;
grant execute on function public.admin_get_all_requests() to anon;
grant execute on function public.admin_get_all_requests() to service_role;

-- Drop old 2-parameter role change function to avoid overloading ambiguity
drop function if exists public.admin_set_user_role(uuid, text);

-- Update admin_set_user_role to handle company tagging
create or replace function public.admin_set_user_role(
  p_user_profile_id uuid,
  p_app_role text,
  p_company_ids uuid[] default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_admin record;
  v_profile public.user_profiles;
  v_role text := lower(trim(coalesce(p_app_role, '')));
begin
  select *
  into v_admin
  from public.admin_desktop_login_check()
  limit 1;

  if v_admin.app_role not in ('admin', 'super_admin') then
    raise exception 'Admin access is required.';
  end if;

  if v_role not in ('employee', 'hr', 'admin', 'super_admin') then
    raise exception 'Role must be employee, hr, admin, or super_admin.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null then
    raise exception 'User was not found.';
  end if;

  if v_profile.auth_user_id = auth.uid() then
    raise exception 'You cannot change your own admin role.';
  end if;

  if v_role = 'super_admin' and v_admin.app_role <> 'super_admin' then
    raise exception 'Only a super admin can assign super admin.';
  end if;

  update public.user_profiles
  set app_role = v_role
  where id = p_user_profile_id;

  -- Handle HR company assignments
  delete from public.hr_company_assignments
  where user_profile_id = p_user_profile_id;

  if p_company_ids is not null and array_length(p_company_ids, 1) > 0 then
    insert into public.hr_company_assignments (user_profile_id, company_id)
    select p_user_profile_id, unnest(p_company_ids);
  end if;

  return p_user_profile_id;
end;
$$;

grant execute on function public.admin_set_user_role(uuid, text, uuid[]) to authenticated;
grant execute on function public.admin_set_user_role(uuid, text, uuid[]) to anon;
grant execute on function public.admin_set_user_role(uuid, text, uuid[]) to service_role;

notify pgrst, 'reload schema';
