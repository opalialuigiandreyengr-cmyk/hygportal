create table if not exists public.employee_perk_requests (
  id uuid primary key default gen_random_uuid(),
  submitted_by_employee_id uuid not null references public.employees(id),
  submitted_by_user_id uuid not null references public.user_profiles(id),
  form_type text not null check (form_type in ('discount', 'charge')),
  status text not null default 'pending_verification' check (status in ('pending_verification', 'approved', 'cancelled')),
  email text not null,
  approval_code text not null,
  request_label text not null,
  product_name text not null,
  quantity int not null check (quantity > 0),
  price numeric(10, 2) not null check (price > 0),
  products jsonb not null default '[]'::jsonb,
  transaction_date date not null,
  amount numeric(10, 2) not null default 0,
  final_amount numeric(10, 2) not null default 0,
  discount_applies boolean not null default false,
  created_at timestamptz not null default now(),
  approved_at timestamptz
);

alter table public.employee_perk_requests enable row level security;

drop policy if exists "Users can read own perk requests" on public.employee_perk_requests;
create policy "Users can read own perk requests"
on public.employee_perk_requests for select
to authenticated
using (
  exists (
    select 1
    from public.user_profiles up
    where up.auth_user_id = auth.uid()
      and up.id = employee_perk_requests.submitted_by_user_id
  )
);

create or replace function public.parse_perk_products(p_products jsonb)
returns table (
  product_summary text,
  total_quantity int,
  average_price numeric,
  total_amount numeric,
  normalized_products jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item jsonb;
  v_name text;
  v_quantity int;
  v_price numeric;
  v_line_total numeric;
  v_summary_parts text[] := '{}';
  v_products jsonb := '[]'::jsonb;
  v_total_quantity int := 0;
  v_total_amount numeric := 0;
begin
  if jsonb_typeof(coalesce(p_products, '[]'::jsonb)) <> 'array' then
    raise exception 'Products must be an array.';
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(p_products, '[]'::jsonb))
  loop
    v_name := nullif(trim(coalesce(v_item->>'name', v_item->>'product_name', '')), '');
    v_quantity := coalesce(nullif(v_item->>'quantity', '')::int, 0);
    v_price := coalesce(nullif(v_item->>'price', '')::numeric, 0);

    if v_name is null or v_quantity <= 0 or v_price <= 0 then
      raise exception 'Invalid product details.';
    end if;

    v_line_total := round(v_quantity * v_price, 2);
    v_summary_parts := array_append(v_summary_parts, v_name || ' x' || v_quantity || ' @ ' || to_char(v_price, 'FM999999990.00'));
    v_total_quantity := v_total_quantity + v_quantity;
    v_total_amount := v_total_amount + v_line_total;
    v_products := v_products || jsonb_build_array(jsonb_build_object(
      'name', v_name,
      'quantity', v_quantity,
      'price', round(v_price, 2),
      'line_total', v_line_total
    ));
  end loop;

  if v_total_quantity <= 0 then
    raise exception 'At least one product is required.';
  end if;

  product_summary := array_to_string(v_summary_parts, '; ');
  total_quantity := v_total_quantity;
  average_price := round(v_total_amount / v_total_quantity, 2);
  total_amount := round(v_total_amount, 2);
  normalized_products := v_products;
  return next;
end;
$$;

create or replace function public.generate_perk_approval_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  loop
    v_code := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (
      select 1
      from public.employee_perk_requests
      where approval_code = v_code
        and created_at >= now() - interval '1 year'
    );
  end loop;
  return v_code;
end;
$$;

create or replace function public.start_employee_perk_request(
  p_form_type text,
  p_transaction_date date,
  p_products jsonb,
  p_email text default null
)
returns table (
  request_id uuid,
  email text,
  approval_code text,
  request_label text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_employee public.employees;
  v_email text;
  v_code text;
  v_product record;
  v_discount_used numeric;
  v_discount_count int;
  v_charge_count int;
  v_charge_used numeric;
  v_final_amount numeric;
  v_label text;
  v_discount_applies boolean := false;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  if p_form_type not in ('discount', 'charge') then
    raise exception 'Invalid perk request type.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  if v_profile.id is null or v_profile.employee_id is null then
    raise exception 'Your login is not linked to an employee profile.';
  end if;

  select *
  into v_employee
  from public.employees
  where id = v_profile.employee_id
  limit 1;

  v_email := nullif(lower(trim(coalesce(v_employee.email, ''))), '');
  if v_email is null then
    v_email := nullif(lower(trim(coalesce(p_email, ''))), '');
    if v_email is null then
      raise exception 'Your employee profile does not have a registered email address. Please enter your email first.';
    end if;
    if v_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$' then
      raise exception 'Please enter a valid email address.';
    end if;

    update public.employees
    set email = v_email,
        updated_at = now()
    where id = v_profile.employee_id;
  end if;

  select *
  into v_product
  from public.parse_perk_products(p_products)
  limit 1;

  select count(*), coalesce(sum(final_amount), 0)
  into v_discount_count, v_discount_used
  from public.employee_perk_requests
  where submitted_by_user_id = v_profile.id
    and form_type = 'discount'
    and status = 'approved'
    and created_at >= date_trunc('year', now())
    and created_at < date_trunc('year', now()) + interval '1 year';

  select count(*), coalesce(sum(final_amount), 0)
  into v_charge_count, v_charge_used
  from public.employee_perk_requests
  where submitted_by_user_id = v_profile.id
    and form_type = 'charge'
    and status = 'approved'
    and created_at >= date_trunc('year', now())
    and created_at < date_trunc('year', now()) + interval '1 year';

  if p_form_type = 'discount' then
    v_label := 'Employee Discount (Cash)';
    v_final_amount := round(v_product.total_amount * 0.85, 2);
    v_discount_applies := true;

    if v_discount_count >= 6 then
      raise exception 'You have reached the maximum of 6 employee discount transactions for this year.';
    end if;
    if v_discount_used + v_final_amount > 3000 then
      raise exception 'This discount request exceeds your remaining yearly cash discount limit.';
    end if;
  else
    v_label := 'Employee Charge (Credit)';
    v_discount_applies := v_charge_count = 0;
    v_final_amount := case when v_discount_applies then round(v_product.total_amount * 0.85, 2) else v_product.total_amount end;

    if v_charge_used + v_final_amount > 3000 then
      raise exception 'This employee charge request exceeds your remaining yearly credit limit.';
    end if;
  end if;

  v_code := public.generate_perk_approval_code();

  insert into public.employee_perk_requests (
    submitted_by_employee_id,
    submitted_by_user_id,
    form_type,
    status,
    email,
    approval_code,
    request_label,
    product_name,
    quantity,
    price,
    products,
    transaction_date,
    amount,
    final_amount,
    discount_applies
  )
  values (
    v_profile.employee_id,
    v_profile.id,
    p_form_type,
    'pending_verification',
    v_email,
    v_code,
    v_label,
    v_product.product_summary,
    v_product.total_quantity,
    v_product.average_price,
    v_product.normalized_products,
    p_transaction_date,
    v_product.total_amount,
    v_final_amount,
    v_discount_applies
  )
  returning id into request_id;

  email := v_email;
  approval_code := v_code;
  request_label := v_label;
  return next;
end;
$$;

drop function if exists public.get_my_perk_usage();
create function public.get_my_perk_usage()
returns table (
  cash_amount_used numeric,
  cash_amount_limit numeric,
  cash_transactions_used int,
  cash_transactions_limit int,
  credit_amount_used numeric,
  credit_amount_limit numeric,
  credit_first_discount_used boolean,
  credit_transactions_used int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  if v_profile.id is null then
    raise exception 'Your login is not linked to an employee profile.';
  end if;

  select
    coalesce(sum(final_amount), 0),
    count(*)
  into cash_amount_used, cash_transactions_used
  from public.employee_perk_requests
  where submitted_by_user_id = v_profile.id
    and form_type = 'discount'
    and status = 'approved'
    and created_at >= date_trunc('year', now())
    and created_at < date_trunc('year', now()) + interval '1 year';

  select exists (
    select 1
    from public.employee_perk_requests
    where submitted_by_user_id = v_profile.id
      and form_type = 'charge'
      and status = 'approved'
      and discount_applies = true
      and created_at >= date_trunc('year', now())
      and created_at < date_trunc('year', now()) + interval '1 year'
  )
  into credit_first_discount_used;

  select
    coalesce(sum(final_amount), 0),
    count(*)
  into credit_amount_used, credit_transactions_used
  from public.employee_perk_requests
  where submitted_by_user_id = v_profile.id
    and form_type = 'charge'
    and status = 'approved'
    and created_at >= date_trunc('year', now())
    and created_at < date_trunc('year', now()) + interval '1 year';

  cash_amount_limit := 3000;
  cash_transactions_limit := 6;
  credit_amount_limit := 3000;
  return next;
end;
$$;

drop function if exists public.verify_employee_perk_request(uuid, text);
create function public.verify_employee_perk_request(
  p_request_id uuid,
  p_approval_code text
)
returns table (
  request_id uuid,
  email text,
  form_type text,
  request_label text,
  approval_code text,
  product_name text,
  transaction_date date,
  amount numeric,
  final_amount numeric,
  discount_amount numeric,
  benefit text,
  employee_name text,
  employee_no text,
  department_name text,
  company_name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_request public.employee_perk_requests;
  v_employee public.employees;
  v_department_name text;
  v_company_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  select *
  into v_request
  from public.employee_perk_requests
  where id = p_request_id
    and submitted_by_user_id = v_profile.id
  for update;

  if v_request.id is null then
    raise exception 'No perk request is waiting for verification.';
  end if;
  if v_request.status <> 'pending_verification' then
    raise exception 'This perk request is already completed.';
  end if;
  if trim(coalesce(p_approval_code, '')) <> v_request.approval_code then
    raise exception 'Invalid approval code. Please try again.';
  end if;

  update public.employee_perk_requests
  set status = 'approved',
      approved_at = now()
  where id = v_request.id;

  insert into public.notifications (
    employee_id,
    user_profile_id,
    title,
    message,
    link_type,
    link_id
  )
  values (
    v_profile.employee_id,
    v_profile.id,
    'Perk approved',
    'Your ' || v_request.request_label || ' request was approved.',
    'perk',
    v_request.id
  );

  select *
  into v_employee
  from public.employees
  where id = v_profile.employee_id;

  select d.name, c.name
  into v_department_name, v_company_name
  from public.employee_assignments ea
  left join public.departments d on d.id = ea.department_id
  left join public.companies c on c.id = ea.company_id
  where ea.employee_id = v_profile.employee_id
    and ea.effective_from <= current_date
    and (ea.effective_to is null or ea.effective_to >= current_date)
  order by ea.is_primary desc, ea.effective_from desc, ea.created_at desc
  limit 1;

  request_id := v_request.id;
  email := v_request.email;
  form_type := v_request.form_type;
  request_label := v_request.request_label;
  approval_code := v_request.approval_code;
  product_name := v_request.product_name;
  transaction_date := v_request.transaction_date;
  amount := v_request.amount;
  final_amount := v_request.final_amount;
  discount_amount := round(v_request.amount - v_request.final_amount, 2);
  benefit := case
    when v_request.discount_applies then '15% first-transaction discount'
    when v_request.form_type = 'discount' then '15% employee cash discount'
    else 'Employee charge'
  end;
  employee_name := nullif(trim(concat_ws(' ', v_employee.first_name, v_employee.middle_name, v_employee.last_name, v_employee.suffix)), '');
  employee_no := coalesce(nullif(v_employee.employee_no, ''), 'N/A');
  department_name := coalesce(nullif(v_department_name, ''), 'N/A');
  company_name := coalesce(nullif(v_company_name, ''), 'N/A');
  return next;
end;
$$;

drop function if exists public.get_my_requests();
create function public.get_my_requests()
returns table (
  request_id uuid,
  request_type_code text,
  request_type_name text,
  status text,
  submitted_at timestamptz,
  final_approved_at timestamptz,
  rejected_at timestamptz,
  rejected_reason text,
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
  approval_summary jsonb
)
language sql
security definer
set search_path = public
as $$
  select * from (
    select
      r.id as request_id,
      rt.code as request_type_code,
      rt.name as request_type_name,
      r.status,
      r.submitted_at,
      r.final_approved_at,
      r.rejected_at,
      r.rejected_reason,
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
              'approver_name', nullif(trim(concat_ws(' ', ae.first_name, ae.middle_name, ae.last_name, ae.suffix)), ''),
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
      ) as approval_summary
    from public.requests r
    join public.request_types rt on rt.id = r.request_type_id
    left join public.time_request_details trd on trd.request_id = r.id
    left join public.leave_request_details lrd on lrd.request_id = r.id
    join public.user_profiles up on up.employee_id = r.submitted_by_employee_id
    where up.auth_user_id = auth.uid()

    union all

    select
      pr.id as request_id,
      pr.form_type as request_type_code,
      pr.request_label as request_type_name,
      case when pr.status = 'pending_verification' then 'pending' else pr.status end as status,
      pr.created_at as submitted_at,
      pr.approved_at as final_approved_at,
      null::timestamptz as rejected_at,
      null::text as rejected_reason,
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
        when pr.discount_applies then '15% first-transaction discount'
        when pr.form_type = 'discount' then '15% employee cash discount'
        else 'Employee charge'
      end as perk_benefit,
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
      )) as approval_summary
    from public.employee_perk_requests pr
    join public.user_profiles up on up.id = pr.submitted_by_user_id
    where up.auth_user_id = auth.uid()
  ) all_requests
  order by submitted_at desc;
$$;

grant execute on function public.start_employee_perk_request(text, date, jsonb, text) to authenticated;
grant execute on function public.verify_employee_perk_request(uuid, text) to authenticated;
grant execute on function public.get_my_perk_usage() to authenticated;
grant execute on function public.get_my_requests() to authenticated;

notify pgrst, 'reload schema';
