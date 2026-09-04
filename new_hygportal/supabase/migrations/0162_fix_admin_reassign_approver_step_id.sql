-- Migration 0162: Fix admin_get_all_requests, admin_reassign_request_approver, and admin_refresh_assigned_approvers

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

-- Reassign request approver function: target specific p_step_id when provided
drop function if exists public.admin_reassign_request_approver(uuid, uuid, uuid);
drop function if exists public.admin_reassign_request_approver(uuid, uuid);

create or replace function public.admin_reassign_request_approver(
  p_request_id uuid,
  p_new_approver_employee_id uuid,
  p_step_id uuid default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_step_id uuid;
  v_user_profile_id uuid;
  v_target_step_order int;
  v_prev_unapproved_count int;
begin
  -- Get user_profile_id of the new approver from user_profiles table
  select id
  into v_user_profile_id
  from public.user_profiles
  where employee_id = p_new_approver_employee_id
  limit 1;

  if p_step_id is not null then
    v_target_step_id := p_step_id;
  else
    -- Find step that needs approver assignment
    select id
    into v_target_step_id
    from public.request_approval_steps
    where request_id = p_request_id
      and (assigned_approver_employee_id is null or status in ('admin_fallback', 'needs_admin_review', 'pending', 'waiting'))
    order by
      case when status = 'admin_fallback' then 1
           when assigned_approver_employee_id is null then 2
           when status = 'needs_admin_review' then 3
           when status = 'pending' then 4
           else 5 end,
      step_order asc
    limit 1;
  end if;

  if v_target_step_id is null then
    raise exception 'No editable approval step found for this request';
  end if;

  -- Get step_order of target step
  select step_order
  into v_target_step_order
  from public.request_approval_steps
  where id = v_target_step_id;

  -- Count unapproved previous steps for this request
  select count(*)
  into v_prev_unapproved_count
  from public.request_approval_steps
  where request_id = p_request_id
    and step_order < v_target_step_order
    and status not in ('approved', 'skipped');

  -- Update approval step: set status to 'pending' if all previous steps are approved, otherwise keep 'waiting'
  update public.request_approval_steps
  set assigned_approver_employee_id = p_new_approver_employee_id,
      assigned_approver_user_id = v_user_profile_id,
      status = case when v_prev_unapproved_count = 0 then 'pending' else 'waiting' end,
      skipped_reason = null
  where id = v_target_step_id;

  -- Update requests status from admin_fallback / needs_admin_review to pending
  update public.requests
  set status = 'pending',
      updated_at = now()
  where id = p_request_id
    and status in ('admin_fallback', 'needs_admin_review');

  -- Update employee_perk_requests status from admin_fallback / needs_admin_review to pending
  update public.employee_perk_requests
  set status = 'pending'
  where id = p_request_id
    and status in ('admin_fallback', 'needs_admin_review');

  return 'Approver reassigned successfully.';
end;
$$;

-- Overload with 2 parameters (p_request_id, p_new_approver_employee_id)
create or replace function public.admin_reassign_request_approver(
  p_request_id uuid,
  p_new_approver_employee_id uuid
)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.admin_reassign_request_approver(
    p_request_id => p_request_id,
    p_new_approver_employee_id => p_new_approver_employee_id,
    p_step_id => null
  );
end;
$$;

grant execute on function public.admin_reassign_request_approver(uuid, uuid, uuid) to authenticated;
grant execute on function public.admin_reassign_request_approver(uuid, uuid, uuid) to service_role;
grant execute on function public.admin_reassign_request_approver(uuid, uuid) to authenticated;
grant execute on function public.admin_reassign_request_approver(uuid, uuid) to service_role;

-- Function: admin_refresh_assigned_approvers
create or replace function public.admin_refresh_assigned_approvers()
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_admin record;
  v_request record;
  v_assignment public.employee_assignments;
  v_step record;
  v_approver record;
  v_used_employee_ids uuid[];
  v_request_updated boolean;
  v_has_fallback_step boolean;
  v_first_pending_found boolean;
  v_updated_count int := 0;
  v_step_status text;
  v_requester_level int;
  v_target_route_level int;
  v_last_resolved_level int;
  v_existing_step_count int;
  v_approval_count int;
  v_route record;
  v_max_step_order int;
begin
  select *
  into v_admin
  from public.admin_desktop_login_check()
  limit 1;

  if v_admin.app_role not in ('admin', 'super_admin') then
    raise exception 'Admin access is required.';
  end if;

  for v_request in
    select id, submitted_by_employee_id as employee_id, 'request' as source_table, request_type_id
    from public.requests
    where status in ('pending', 'waiting', 'admin_fallback', 'needs_admin_review')
    union all
    select id, submitted_by_employee_id as employee_id, 'perk_request' as source_table, null::uuid as request_type_id
    from public.employee_perk_requests
    where status in ('pending', 'waiting', 'admin_fallback', 'needs_admin_review')
  loop
    v_request_updated := false;
    v_has_fallback_step := false;
    v_first_pending_found := false;
    v_used_employee_ids := '{}'::uuid[];
    v_last_resolved_level := 0;

    -- Get employee assignment for requester
    select ea.*
    into v_assignment
    from public.employee_assignments ea
    where ea.employee_id = v_request.employee_id
      and ea.is_primary = true
      and ea.effective_from <= current_date
      and (ea.effective_to is null or ea.effective_to >= current_date)
    order by ea.created_at desc
    limit 1;

    if v_assignment.id is null then
      select ea.*
      into v_assignment
      from public.employee_assignments ea
      where ea.employee_id = v_request.employee_id
      order by ea.created_at desc
      limit 1;
    end if;

    if v_assignment.id is not null then
      if v_assignment.store_id is not null then
        select
          coalesce(s.area_id, cl.area_id, v_assignment.area_id),
          coalesce(s.cluster_id, v_assignment.cluster_id)
        into v_assignment.area_id, v_assignment.cluster_id
        from public.stores s
        left join public.clusters cl on cl.id = s.cluster_id
        where s.id = v_assignment.store_id;
      end if;

      -- Get requester authority level
      select p.authority_level
      into v_requester_level
      from public.positions p
      where p.id = v_assignment.position_id
      limit 1;

      -- Get expected approval count for this request type
      if v_request.source_table = 'request' and v_request.request_type_id is not null then
        select approval_count
        into v_approval_count
        from public.request_types
        where id = v_request.request_type_id;
      else
        v_approval_count := 1;
      end if;
      v_approval_count := coalesce(v_approval_count, 2);

      -- Check existing steps count
      select count(*), coalesce(max(step_order), 0)
      into v_existing_step_count, v_max_step_order
      from public.request_approval_steps
      where request_id = v_request.id;

      -- If request has NO steps at all, create them based on approval_level_routes
      if v_existing_step_count = 0 and v_request.source_table = 'request' then
        for v_route in
          select distinct on (step_order) *
          from public.approval_level_routes
          where requester_level = coalesce(v_requester_level, 1)
            and (department_id = v_assignment.department_id or department_id is null)
          order by
            step_order asc,
            case when department_id = v_assignment.department_id then 0 else 1 end
          limit v_approval_count
        loop
          select *
          into v_approver
          from public.find_request_approver(
            v_assignment.id,
            v_assignment.function_id,
            v_route.approver_level,
            v_request.employee_id,
            v_used_employee_ids
          )
          limit 1;

          if v_approver.approver_employee_id is not null then
            v_max_step_order := v_max_step_order + 1;
            v_step_status := case when not v_first_pending_found then 'pending' else 'waiting' end;
            v_first_pending_found := true;

            insert into public.request_approval_steps (
              request_id,
              step_order,
              required_function_id,
              required_level,
              assigned_approver_employee_id,
              assigned_approver_user_id,
              status
            )
            values (
              v_request.id,
              v_max_step_order,
              v_assignment.function_id,
              v_approver.resolved_level,
              v_approver.approver_employee_id,
              v_approver.approver_user_profile_id,
              v_step_status
            );

            v_used_employee_ids := array_append(v_used_employee_ids, v_approver.approver_employee_id);
            v_request_updated := true;
          else
            v_max_step_order := v_max_step_order + 1;
            v_step_status := case when not v_first_pending_found then 'admin_fallback' else 'waiting' end;
            v_first_pending_found := true;

            insert into public.request_approval_steps (
              request_id,
              step_order,
              required_function_id,
              required_level,
              assigned_approver_employee_id,
              assigned_approver_user_id,
              status,
              skipped_reason
            )
            values (
              v_request.id,
              v_max_step_order,
              v_assignment.function_id,
              v_route.approver_level,
              null,
              null,
              v_step_status,
              'No active non-banned matching approver found.'
            );

            v_request_updated := true;
            if v_step_status = 'admin_fallback' then
              v_has_fallback_step := true;
            end if;
          end if;
        end loop;
      else
        -- Request ALREADY has steps: refresh existing steps
        for v_step in
          select *
          from public.request_approval_steps
          where request_id = v_request.id
          order by step_order asc
        loop
          if v_step.status in ('approved', 'rejected') then
            if v_step.assigned_approver_employee_id is not null then
              v_used_employee_ids := array_append(v_used_employee_ids, v_step.assigned_approver_employee_id);
            end if;
            v_last_resolved_level := greatest(v_last_resolved_level, coalesce(v_step.required_level, 1));
            continue;
          end if;

          -- Look up target level from approval_level_routes for this step_order
          select r.approver_level
          into v_target_route_level
          from public.approval_level_routes r
          where r.requester_level = coalesce(v_requester_level, 1)
            and (r.department_id = v_assignment.department_id or r.department_id is null)
            and r.step_order = v_step.step_order
          order by case when r.department_id = v_assignment.department_id then 0 else 1 end
          limit 1;

          select *
          into v_approver
          from public.find_request_approver(
            v_assignment.id,
            coalesce(v_step.required_function_id, v_assignment.function_id),
            greatest(coalesce(v_target_route_level, v_step.required_level, 1), coalesce(v_last_resolved_level + 1, 1)),
            v_request.employee_id,
            v_used_employee_ids
          )
          limit 1;

          if v_approver.approver_employee_id is not null then
            v_step_status := case when not v_first_pending_found then 'pending' else 'waiting' end;
            v_first_pending_found := true;

            if v_step.assigned_approver_employee_id is distinct from v_approver.approver_employee_id
               or v_step.assigned_approver_user_id is distinct from v_approver.approver_user_profile_id
               or v_step.status in ('admin_fallback', 'needs_admin_review')
               or v_step.status is distinct from v_step_status then
              update public.request_approval_steps
              set assigned_approver_employee_id = v_approver.approver_employee_id,
                  assigned_approver_user_id = v_approver.approver_user_profile_id,
                  required_level = v_approver.resolved_level,
                  status = v_step_status,
                  skipped_reason = null
              where id = v_step.id;

              v_request_updated := true;
            end if;

            v_last_resolved_level := v_approver.resolved_level;
            v_used_employee_ids := array_append(v_used_employee_ids, v_approver.approver_employee_id);
          else
            v_step_status := case when not v_first_pending_found then 'admin_fallback' else 'waiting' end;
            v_first_pending_found := true;

            if v_step.assigned_approver_employee_id is not null
               or v_step.status is distinct from v_step_status then
              update public.request_approval_steps
              set assigned_approver_employee_id = null,
                  assigned_approver_user_id = null,
                  status = v_step_status,
                  skipped_reason = 'No active non-banned matching approver found.'
              where id = v_step.id;

              v_request_updated := true;
            end if;

            if v_step_status = 'admin_fallback' then
              v_has_fallback_step := true;
            end if;
          end if;
        end loop;
      end if;

      if v_has_fallback_step then
        if v_request.source_table = 'request' then
          update public.requests
          set status = 'needs_admin_review', updated_at = now()
          where id = v_request.id and status <> 'needs_admin_review';
        else
          update public.employee_perk_requests
          set status = 'needs_admin_review'
          where id = v_request.id and status <> 'needs_admin_review';
        end if;
      else
        if v_request.source_table = 'request' then
          update public.requests
          set status = 'pending', updated_at = now()
          where id = v_request.id and status in ('needs_admin_review', 'admin_fallback');
        else
          update public.employee_perk_requests
          set status = 'pending'
          where id = v_request.id and status in ('needs_admin_review', 'admin_fallback');
        end if;
      end if;

      if v_request_updated then
        v_updated_count := v_updated_count + 1;
      end if;
    end if;
  end loop;

  if v_updated_count > 0 then
    return 'Successfully refreshed assigned approvers. ' || v_updated_count || ' request(s) updated.';
  else
    return 'All approver assignments are already up to date.';
  end if;
end;
$$;

grant execute on function public.admin_refresh_assigned_approvers() to authenticated;
grant execute on function public.admin_refresh_assigned_approvers() to service_role;

notify pgrst, 'reload schema';
