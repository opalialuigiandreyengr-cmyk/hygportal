drop function if exists public.start_employee_perk_request(text, date, jsonb, text);
create function public.start_employee_perk_request(
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
  v_shared_discount_used numeric;
  v_shared_discount_count int;
  v_charge_count int;
  v_final_amount numeric;
  v_label text;
  v_discount_applies boolean := true;
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
  into v_shared_discount_count, v_shared_discount_used
  from public.employee_perk_requests
  where submitted_by_user_id = v_profile.id
    and status = 'approved'
    and discount_applies = true
    and created_at >= date_trunc('year', now())
    and created_at < date_trunc('year', now()) + interval '1 year';

  select count(*)
  into v_charge_count
  from public.employee_perk_requests
  where submitted_by_user_id = v_profile.id
    and form_type = 'charge'
    and status = 'approved'
    and created_at >= date_trunc('year', now())
    and created_at < date_trunc('year', now()) + interval '1 year';

  v_label := case
    when p_form_type = 'discount' then 'Employee Discount (Cash)'
    else 'Employee Charge (Credit)'
  end;
  v_final_amount := round(v_product.total_amount * 0.85, 2);

  if v_shared_discount_count >= 6 then
    raise exception 'You have reached the shared maximum of 6 cash or credit discount transactions for this year.';
  end if;
  if v_shared_discount_used + v_final_amount > 3000 then
    raise exception 'This request exceeds your remaining shared PHP 3,000 cash or credit discount limit.';
  end if;
  if p_form_type = 'charge' and v_final_amount > 3000 then
    raise exception 'Employee charge requests can only charge up to PHP 3,000 per transaction.';
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
  credit_transactions_used int,
  shared_discount_amount_used numeric,
  shared_discount_amount_limit numeric,
  shared_discount_transactions_used int,
  shared_discount_transactions_limit int,
  credit_transaction_limit numeric
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
  into shared_discount_amount_used, shared_discount_transactions_used
  from public.employee_perk_requests
  where submitted_by_user_id = v_profile.id
    and status = 'approved'
    and discount_applies = true
    and created_at >= date_trunc('year', now())
    and created_at < date_trunc('year', now()) + interval '1 year';

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

  credit_first_discount_used := shared_discount_transactions_used > 0;
  cash_amount_limit := 3000;
  cash_transactions_limit := 6;
  credit_amount_limit := 3000;
  shared_discount_amount_limit := 3000;
  shared_discount_transactions_limit := 6;
  credit_transaction_limit := 3000;
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
    when v_request.discount_applies then '15% shared cash/credit discount'
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
        when pr.discount_applies then '15% shared cash/credit discount'
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
