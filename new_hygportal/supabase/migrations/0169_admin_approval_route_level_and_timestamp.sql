-- Migration 0169: Ensure admin_get_all_requests returns accurate approval route levels and timestamps
-- Dynamically matches approver_level from public.approval_level_routes and provides explicit level, approver_level, required_level, acted_at, and approved_at.

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
              'step_id', ras.id,
              'step_order', ras.step_order,
              'required_level', coalesce(alr.approver_level, ras.required_level),
              'level', coalesce(alr.approver_level, ras.required_level),
              'approver_level', coalesce(alr.approver_level, ras.required_level),
              'status', ras.status,
              'acted_at', ras.acted_at,
              'approved_at', case when ras.status = 'approved' then ras.acted_at else null end,
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
          left join lateral (
            select alr.approver_level
            from public.approval_level_routes alr
            where alr.requester_level = r.requester_level
              and alr.step_order = ras.step_order
              and (alr.department_id = ea.department_id or alr.department_id is null)
            order by case when alr.department_id = ea.department_id then 0 else 1 end
            limit 1
          ) alr on true
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
        'level', 1,
        'approver_level', 1,
        'status', pr.status,
        'acted_at', pr.approved_at,
        'approved_at', pr.approved_at,
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

notify pgrst, 'reload schema';
