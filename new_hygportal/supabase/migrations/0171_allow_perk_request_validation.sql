-- Migration 0171: Allow perk requests to have 'validated' status and maintain annual pool counts

-- 1. Allow 'validated', 'rejected', 'pending', and fallback statuses in employee_perk_requests
alter table public.employee_perk_requests
  drop constraint if exists employee_perk_requests_status_check;

alter table public.employee_perk_requests
  add constraint employee_perk_requests_status_check
  check (status in (
    'pending_verification',
    'pending',
    'approved',
    'validated',
    'rejected',
    'cancelled',
    'needs_admin_review',
    'admin_fallback'
  ));

-- 2. Update start_employee_perk_request so both 'approved' and 'validated' count toward annual limits
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
    and status in ('approved', 'validated')
    and discount_applies = true
    and created_at >= date_trunc('year', now())
    and created_at < date_trunc('year', now()) + interval '1 year';

  select count(*)
  into v_charge_count
  from public.employee_perk_requests
  where submitted_by_user_id = v_profile.id
    and form_type = 'charge'
    and status in ('approved', 'validated')
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

-- 3. Update get_my_perk_usage so both 'approved' and 'validated' count in user's perk summary
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
    and status in ('approved', 'validated')
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
    and status in ('approved', 'validated')
    and created_at >= date_trunc('year', now())
    and created_at < date_trunc('year', now()) + interval '1 year';

  select
    coalesce(sum(final_amount), 0),
    count(*)
  into credit_amount_used, credit_transactions_used
  from public.employee_perk_requests
  where submitted_by_user_id = v_profile.id
    and form_type = 'charge'
    and status in ('approved', 'validated')
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

grant execute on function public.start_employee_perk_request(text, date, jsonb, text) to authenticated;
grant execute on function public.get_my_perk_usage() to authenticated;

notify pgrst, 'reload schema';
