-- ============================================================================
-- Migration 0227: Super Admin Audit Trail & System Activity Logging
--
-- Objective:
-- Enable Super Admins to track and monitor all critical administrative activities,
-- specifically:
-- 1. Password resets and credential changes
-- 2. User account updates, roles, bans, and creations
-- 3. Employee personal info, supplemental details, and assignment updates
-- 4. Fast, paginated querying with search, filtering, and summary metrics
-- ============================================================================

-- 1. Optimize public.audit_logs indexes for high-throughput queries
create index if not exists idx_audit_logs_created_at_desc
  on public.audit_logs (created_at desc);

create index if not exists idx_audit_logs_action
  on public.audit_logs (action);

create index if not exists idx_audit_logs_entity
  on public.audit_logs (entity_type, entity_id);

create index if not exists idx_audit_logs_actor
  on public.audit_logs (actor_user_profile_id);

-- 2. Update admin_reset_user_password with audit logging
create or replace function public.admin_reset_user_password(
  p_user_profile_id uuid,
  p_new_password text
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_admin record;
  v_profile public.user_profiles;
  v_password text := coalesce(p_new_password, '');
  v_admin_profile_id uuid;
  v_target_employee public.employees%rowtype;
  v_target_email text;
begin
  select *
  into v_admin
  from public.admin_desktop_login_check()
  limit 1;

  if v_admin.app_role not in ('admin', 'super_admin') then
    raise exception 'Admin access is required.';
  end if;

  if length(v_password) < 6 then
    raise exception 'Password must be at least 6 characters.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null then
    raise exception 'User was not found.';
  end if;

  -- Look up actor user profile id
  select id into v_admin_profile_id
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  -- Look up employee details for richer audit log
  if v_profile.employee_id is not null then
    select * into v_target_employee
    from public.employees
    where id = v_profile.employee_id;
  end if;

  select email::text into v_target_email
  from auth.users
  where id = v_profile.auth_user_id;

  update auth.users
  set encrypted_password = crypt(v_password, gen_salt('bf')),
      updated_at = now()
  where id = v_profile.auth_user_id;

  -- Insert audit log entry
  insert into public.audit_logs (
    actor_user_profile_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    v_admin_profile_id,
    'password_reset',
    'user',
    p_user_profile_id,
    jsonb_build_object(
      'target_username', v_profile.username,
      'target_email', v_target_email,
      'target_name', nullif(trim(concat_ws(' ', v_target_employee.first_name, v_target_employee.last_name)), ''),
      'target_employee_no', v_target_employee.employee_no,
      'actor_username', v_admin.username,
      'actor_role', v_admin.app_role,
      'description', 'Password was reset for user ''' || coalesce(v_profile.username, 'unknown') || ''' (' || coalesce(v_target_email, 'no email') || ')'
    )
  );

  return p_user_profile_id;
end;
$$;

-- 3. Update admin_set_user_role with audit logging
create or replace function public.admin_set_user_role(
  p_user_profile_id uuid,
  p_app_role text
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
  v_admin_profile_id uuid;
  v_target_employee public.employees%rowtype;
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

  select id into v_admin_profile_id
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  if v_profile.employee_id is not null then
    select * into v_target_employee
    from public.employees
    where id = v_profile.employee_id;
  end if;

  update public.user_profiles
  set app_role = v_role
  where id = p_user_profile_id;

  insert into public.audit_logs (
    actor_user_profile_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    v_admin_profile_id,
    'user_role_change',
    'user',
    p_user_profile_id,
    jsonb_build_object(
      'target_username', v_profile.username,
      'target_name', nullif(trim(concat_ws(' ', v_target_employee.first_name, v_target_employee.last_name)), ''),
      'target_employee_no', v_target_employee.employee_no,
      'old_role', v_profile.app_role,
      'new_role', v_role,
      'actor_username', v_admin.username,
      'actor_role', v_admin.app_role,
      'description', 'Changed role from ''' || coalesce(v_profile.app_role, 'none') || ''' to ''' || v_role || ''' for user ''' || coalesce(v_profile.username, 'unknown') || ''''
    )
  );

  return p_user_profile_id;
end;
$$;

-- 4. Update admin_set_user_ban with audit logging
create or replace function public.admin_set_user_ban(
  p_user_profile_id uuid,
  p_is_banned boolean
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_admin record;
  v_profile public.user_profiles;
  v_admin_profile_id uuid;
  v_target_employee public.employees%rowtype;
begin
  select *
  into v_admin
  from public.admin_desktop_login_check()
  limit 1;

  if v_admin.app_role not in ('admin', 'super_admin') then
    raise exception 'Admin access is required.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where id = p_user_profile_id;

  if v_profile.id is null then
    raise exception 'User was not found.';
  end if;

  if v_profile.auth_user_id = auth.uid() then
    raise exception 'You cannot ban your own admin account.';
  end if;

  select id into v_admin_profile_id
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  if v_profile.employee_id is not null then
    select * into v_target_employee
    from public.employees
    where id = v_profile.employee_id;
  end if;

  update auth.users
  set banned_until = case
        when p_is_banned then now() + interval '100 years'
        else null
      end,
      updated_at = now()
  where id = v_profile.auth_user_id;

  update public.user_profiles
  set is_active = not p_is_banned
  where id = p_user_profile_id;

  insert into public.audit_logs (
    actor_user_profile_id,
    action,
    entity_type,
    entity_id,
    metadata
  )
  values (
    v_admin_profile_id,
    case when p_is_banned then 'user_banned' else 'user_unbanned' end,
    'user',
    p_user_profile_id,
    jsonb_build_object(
      'target_username', v_profile.username,
      'target_name', nullif(trim(concat_ws(' ', v_target_employee.first_name, v_target_employee.last_name)), ''),
      'target_employee_no', v_target_employee.employee_no,
      'is_banned', p_is_banned,
      'actor_username', v_admin.username,
      'actor_role', v_admin.app_role,
      'description', case
        when p_is_banned then 'Account was banned for user ''' || coalesce(v_profile.username, 'unknown') || ''''
        else 'Account was unbanned for user ''' || coalesce(v_profile.username, 'unknown') || ''''
      end
    )
  );

  return p_user_profile_id;
end;
$$;

-- 5. Automatic audit trigger for public.employees updates
create or replace function public.fn_audit_employees_update()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_changes jsonb := '{}'::jsonb;
  v_actor_profile_id uuid;
  v_actor_username text := 'system';
begin
  if OLD.first_name is distinct from NEW.first_name then
    v_changes := v_changes || jsonb_build_object('first_name', jsonb_build_object('old', OLD.first_name, 'new', NEW.first_name));
  end if;
  if OLD.last_name is distinct from NEW.last_name then
    v_changes := v_changes || jsonb_build_object('last_name', jsonb_build_object('old', OLD.last_name, 'new', NEW.last_name));
  end if;
  if OLD.middle_name is distinct from NEW.middle_name then
    v_changes := v_changes || jsonb_build_object('middle_name', jsonb_build_object('old', OLD.middle_name, 'new', NEW.middle_name));
  end if;
  if OLD.suffix is distinct from NEW.suffix then
    v_changes := v_changes || jsonb_build_object('suffix', jsonb_build_object('old', OLD.suffix, 'new', NEW.suffix));
  end if;
  if OLD.employment_status is distinct from NEW.employment_status then
    v_changes := v_changes || jsonb_build_object('employment_status', jsonb_build_object('old', OLD.employment_status, 'new', NEW.employment_status));
  end if;
  if OLD.employee_no is distinct from NEW.employee_no then
    v_changes := v_changes || jsonb_build_object('employee_no', jsonb_build_object('old', OLD.employee_no, 'new', NEW.employee_no));
  end if;
  if OLD.email is distinct from NEW.email then
    v_changes := v_changes || jsonb_build_object('email', jsonb_build_object('old', OLD.email, 'new', NEW.email));
  end if;
  if OLD.phone is distinct from NEW.phone then
    v_changes := v_changes || jsonb_build_object('phone', jsonb_build_object('old', OLD.phone, 'new', NEW.phone));
  end if;
  if OLD.civil_status is distinct from NEW.civil_status then
    v_changes := v_changes || jsonb_build_object('civil_status', jsonb_build_object('old', OLD.civil_status, 'new', NEW.civil_status));
  end if;
  if OLD.gender is distinct from NEW.gender then
    v_changes := v_changes || jsonb_build_object('gender', jsonb_build_object('old', OLD.gender, 'new', NEW.gender));
  end if;
  if OLD.birth_date is distinct from NEW.birth_date then
    v_changes := v_changes || jsonb_build_object('birth_date', jsonb_build_object('old', OLD.birth_date, 'new', NEW.birth_date));
  end if;

  if v_changes <> '{}'::jsonb then
    if auth.uid() is not null then
      select id, username into v_actor_profile_id, v_actor_username
      from public.user_profiles
      where auth_user_id = auth.uid()
      limit 1;
    end if;

    insert into public.audit_logs (
      actor_user_profile_id,
      action,
      entity_type,
      entity_id,
      metadata
    )
    values (
      v_actor_profile_id,
      'update_employee_information',
      'employee',
      NEW.id,
      jsonb_build_object(
        'target_name', trim(concat_ws(' ', NEW.first_name, NEW.middle_name, NEW.last_name, NEW.suffix)),
        'target_employee_no', NEW.employee_no,
        'actor_username', coalesce(v_actor_username, 'system'),
        'changes', v_changes,
        'description', 'Employee profile updated for ' || trim(concat_ws(' ', NEW.first_name, NEW.last_name))
      )
    );
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_audit_employees_update on public.employees;
create trigger trg_audit_employees_update
  after update on public.employees
  for each row
  execute function public.fn_audit_employees_update();

-- 6. Automatic audit trigger for public.user_profiles updates
create or replace function public.fn_audit_user_profiles_update()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_changes jsonb := '{}'::jsonb;
  v_actor_profile_id uuid;
  v_actor_username text := 'system';
begin
  if OLD.username is distinct from NEW.username then
    v_changes := v_changes || jsonb_build_object('username', jsonb_build_object('old', OLD.username, 'new', NEW.username));
  end if;
  if OLD.app_role is distinct from NEW.app_role then
    v_changes := v_changes || jsonb_build_object('app_role', jsonb_build_object('old', OLD.app_role, 'new', NEW.app_role));
  end if;
  if OLD.is_active is distinct from NEW.is_active then
    v_changes := v_changes || jsonb_build_object('is_active', jsonb_build_object('old', OLD.is_active, 'new', NEW.is_active));
  end if;
  if OLD.employee_id is distinct from NEW.employee_id then
    v_changes := v_changes || jsonb_build_object('employee_id', jsonb_build_object('old', OLD.employee_id, 'new', NEW.employee_id));
  end if;

  if v_changes <> '{}'::jsonb then
    if auth.uid() is not null then
      select id, username into v_actor_profile_id, v_actor_username
      from public.user_profiles
      where auth_user_id = auth.uid()
      limit 1;
    end if;

    insert into public.audit_logs (
      actor_user_profile_id,
      action,
      entity_type,
      entity_id,
      metadata
    )
    values (
      v_actor_profile_id,
      'update_user_information',
      'user',
      NEW.id,
      jsonb_build_object(
        'target_username', NEW.username,
        'actor_username', coalesce(v_actor_username, 'system'),
        'changes', v_changes,
        'description', 'User profile updated for ''' || coalesce(NEW.username, 'unknown') || ''''
      )
    );
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_audit_user_profiles_update on public.user_profiles;
create trigger trg_audit_user_profiles_update
  after update on public.user_profiles
  for each row
  execute function public.fn_audit_user_profiles_update();

-- 7. Automatic audit trigger for public.employee_profile_details updates
create or replace function public.fn_audit_employee_profile_details_update()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_changes jsonb := '{}'::jsonb;
  v_actor_profile_id uuid;
  v_actor_username text := 'system';
  v_emp public.employees%rowtype;
begin
  if OLD.present_address is distinct from NEW.present_address then
    v_changes := v_changes || jsonb_build_object('present_address', jsonb_build_object('old', OLD.present_address, 'new', NEW.present_address));
  end if;
  if OLD.emergency_contact is distinct from NEW.emergency_contact then
    v_changes := v_changes || jsonb_build_object('emergency_contact', jsonb_build_object('old', OLD.emergency_contact, 'new', NEW.emergency_contact));
  end if;
  if OLD.tin is distinct from NEW.tin then
    v_changes := v_changes || jsonb_build_object('tin', jsonb_build_object('old', OLD.tin, 'new', NEW.tin));
  end if;
  if OLD.sss is distinct from NEW.sss then
    v_changes := v_changes || jsonb_build_object('sss', jsonb_build_object('old', OLD.sss, 'new', NEW.sss));
  end if;
  if OLD.pagibig is distinct from NEW.pagibig then
    v_changes := v_changes || jsonb_build_object('pagibig', jsonb_build_object('old', OLD.pagibig, 'new', NEW.pagibig));
  end if;
  if OLD.philhealth is distinct from NEW.philhealth then
    v_changes := v_changes || jsonb_build_object('philhealth', jsonb_build_object('old', OLD.philhealth, 'new', NEW.philhealth));
  end if;
  if OLD.bank_type is distinct from NEW.bank_type then
    v_changes := v_changes || jsonb_build_object('bank_type', jsonb_build_object('old', OLD.bank_type, 'new', NEW.bank_type));
  end if;
  if OLD.account_no is distinct from NEW.account_no then
    v_changes := v_changes || jsonb_build_object('account_no', jsonb_build_object('old', OLD.account_no, 'new', NEW.account_no));
  end if;
  if OLD.employee_type is distinct from NEW.employee_type then
    v_changes := v_changes || jsonb_build_object('employee_type', jsonb_build_object('old', OLD.employee_type, 'new', NEW.employee_type));
  end if;
  if OLD.work_unit_name is distinct from NEW.work_unit_name then
    v_changes := v_changes || jsonb_build_object('work_unit_name', jsonb_build_object('old', OLD.work_unit_name, 'new', NEW.work_unit_name));
  end if;
  if OLD.education is distinct from NEW.education then
    v_changes := v_changes || jsonb_build_object('education', jsonb_build_object('old', OLD.education, 'new', NEW.education));
  end if;

  if v_changes <> '{}'::jsonb then
    if auth.uid() is not null then
      select id, username into v_actor_profile_id, v_actor_username
      from public.user_profiles
      where auth_user_id = auth.uid()
      limit 1;
    end if;

    select * into v_emp from public.employees where id = NEW.employee_id;

    insert into public.audit_logs (
      actor_user_profile_id,
      action,
      entity_type,
      entity_id,
      metadata
    )
    values (
      v_actor_profile_id,
      'update_employee_details',
      'employee',
      NEW.employee_id,
      jsonb_build_object(
        'target_name', trim(concat_ws(' ', v_emp.first_name, v_emp.last_name)),
        'target_employee_no', v_emp.employee_no,
        'actor_username', coalesce(v_actor_username, 'system'),
        'changes', v_changes,
        'description', 'Profile details updated for ' || coalesce(trim(concat_ws(' ', v_emp.first_name, v_emp.last_name)), 'employee')
      )
    );
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_audit_employee_profile_details_update on public.employee_profile_details;
create trigger trg_audit_employee_profile_details_update
  after update on public.employee_profile_details
  for each row
  execute function public.fn_audit_employee_profile_details_update();

-- 8. Main RPC: admin_get_audit_logs with search, filters, and pagination
drop function if exists public.admin_get_audit_logs(text, text, text, timestamptz, timestamptz, int, int);

create or replace function public.admin_get_audit_logs(
  p_search text default null,
  p_action text default null,
  p_entity_type text default null,
  p_start_date timestamptz default null,
  p_end_date timestamptz default null,
  p_limit int default 50,
  p_offset int default 0
)
returns table (
  id uuid,
  created_at timestamptz,
  action text,
  action_label text,
  entity_type text,
  entity_id uuid,
  actor_user_profile_id uuid,
  actor_username text,
  actor_full_name text,
  actor_role text,
  target_name text,
  target_identifier text,
  description text,
  metadata jsonb,
  total_count bigint
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_admin record;
  v_search text := nullif(lower(trim(p_search)), '');
begin
  select *
  into v_admin
  from public.admin_desktop_login_check()
  limit 1;

  if v_admin.app_role not in ('super_admin', 'admin') then
    raise exception 'Admin or Super Admin access is required to view the Audit Trail.';
  end if;

  return query
  with filtered as (
    select
      al.id,
      al.created_at,
      al.action,
      case
        when al.action = 'password_reset' then 'Password Reset'
        when al.action in ('update_employee_profile', 'update_employee_information') then 'Employee Info Updated'
        when al.action = 'update_employee_assignment' then 'Job Assignment Updated'
        when al.action = 'update_employee_details' then 'Employee Details Updated'
        when al.action in ('update_user_information', 'user_role_change') then 'User Role / Info Changed'
        when al.action = 'user_banned' then 'User Banned'
        when al.action = 'user_unbanned' then 'User Unbanned'
        when al.action in ('create_user', 'admin_create_user') then 'User Created'
        when al.action = 'admin_delete_user' then 'User Deleted'
        when al.action = 'hr_delete_employee' then 'Employee Deleted'
        when al.action = 'admin_set_employee_leave_credits' then 'Leave Credits Set'
        when al.action = 'admin_deduct_employee_leave_credits' then 'Leave Credits Deducted'
        when al.action = 'admin_reimburse_employee_leave_credits' then 'Leave Credits Reimbursed'
        when al.action = 'admin_set_employee_offset_balance' then 'Offset Balance Set'
        when al.action = 'admin_add_employee_offset_balance' then 'Offset Balance Added'
        when al.action = 'admin_deduct_employee_offset_balance' then 'Offset Balance Deducted'
        when al.action = 'admin_set_authority_assignment' then 'Authority Assignment'
        when al.action = 'admin_approval_routes' then 'Approval Route Changed'
        when al.action = 'department_approval_ladders' then 'Approval Ladder Changed'
        when al.action = 'department_position_catalog' then 'Position Catalog Changed'
        else initcap(replace(al.action, '_', ' '))
      end as action_label,
      al.entity_type,
      al.entity_id,
      al.actor_user_profile_id,
      coalesce(al.metadata->>'actor_username', actor_up.username, 'System') as actor_username,
      coalesce(
        nullif(trim(concat_ws(' ', actor_e.first_name, actor_e.last_name)), ''),
        al.metadata->>'actor_full_name',
        actor_up.username,
        'System'
      ) as actor_full_name,
      coalesce(al.metadata->>'actor_role', actor_up.app_role, 'system') as actor_role,
      coalesce(
        al.metadata->>'target_name',
        al.metadata->>'target_full_name',
        al.metadata->>'full_name',
        nullif(trim(concat_ws(' ', target_e.first_name, target_e.last_name)), ''),
        target_up.username,
        al.metadata->>'target_username',
        'N/A'
      ) as target_name,
      coalesce(
        al.metadata->>'target_employee_no',
        al.metadata->>'employee_no',
        target_e.employee_no,
        al.metadata->>'target_username',
        target_up.username,
        al.metadata->>'username',
        ''
      ) as target_identifier,
      coalesce(
        al.metadata->>'description',
        al.metadata->>'reason',
        case
          when al.action = 'admin_set_employee_leave_credits' then
            concat('Set annual leave credits to ', al.metadata->>'annual_credit_days', ' days')
          when al.action = 'admin_deduct_employee_leave_credits' then
            concat('Deducted ', al.metadata->>'deduct_days', ' leave days')
          when al.action = 'admin_reimburse_employee_leave_credits' then
            concat('Reimbursed ', al.metadata->>'reimburse_days', ' leave days')
          when al.action = 'admin_set_employee_offset_balance' then
            concat('Set offset balance to ', al.metadata->>'new_balance_hours', ' hrs')
          when al.action = 'admin_add_employee_offset_balance' then
            concat('Added ', al.metadata->>'add_hours', ' hrs to offset balance')
          when al.action = 'admin_deduct_employee_offset_balance' then
            concat('Deducted ', al.metadata->>'deduct_hours', ' hrs from offset balance')
          else null
        end,
        al.metadata->>'note',
        ''
      ) as description,
      al.metadata
    from public.audit_logs al
    left join public.user_profiles actor_up on actor_up.id = al.actor_user_profile_id
    left join public.employees actor_e on actor_e.id = actor_up.employee_id
    left join public.user_profiles target_up on (
      (al.entity_type in ('user', 'user_profile') and target_up.id = al.entity_id)
      or (al.entity_type in ('leave_balance', 'offset_balance') and target_up.id = (al.metadata->>'user_profile_id')::uuid)
    )
    left join public.employees target_e on (
      (al.entity_type in ('employee', 'leave_balance', 'offset_balance') and target_e.id = al.entity_id)
      or (al.entity_type in ('user', 'user_profile') and target_e.id = target_up.employee_id)
    )
    where
      (p_action is null or p_action = 'all' or al.action = p_action)
      and (
        p_entity_type is null or p_entity_type = 'all'
        or al.entity_type = p_entity_type
        or (p_entity_type = 'balance' and al.entity_type in ('leave_balance', 'offset_balance'))
      )
      and (p_start_date is null or al.created_at >= p_start_date)
      and (p_end_date is null or al.created_at <= p_end_date)
      and (
        v_search is null
        or lower(al.action) like '%' || v_search || '%'
        or lower(al.entity_type) like '%' || v_search || '%'
        or lower(coalesce(actor_up.username, '')) like '%' || v_search || '%'
        or lower(coalesce(actor_e.first_name || ' ' || actor_e.last_name, '')) like '%' || v_search || '%'
        or lower(coalesce(al.metadata::text, '')) like '%' || v_search || '%'
      )
  )
  select
    f.id,
    f.created_at,
    f.action,
    f.action_label,
    f.entity_type,
    f.entity_id,
    f.actor_user_profile_id,
    f.actor_username,
    f.actor_full_name,
    f.actor_role,
    f.target_name,
    f.target_identifier,
    f.description,
    f.metadata,
    count(*) over() as total_count
  from filtered f
  order by f.created_at desc
  limit coalesce(p_limit, 50)
  offset coalesce(p_offset, 0);
end;
$$;

-- 9. Stats RPC: admin_get_audit_stats
drop function if exists public.admin_get_audit_stats();

create or replace function public.admin_get_audit_stats()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_admin record;
  v_total bigint;
  v_password_resets bigint;
  v_user_updates bigint;
  v_today_actions bigint;
begin
  select *
  into v_admin
  from public.admin_desktop_login_check()
  limit 1;

  if v_admin.app_role not in ('super_admin', 'admin') then
    raise exception 'Admin or Super Admin access is required.';
  end if;

  select count(*) into v_total from public.audit_logs;
  select count(*) into v_password_resets from public.audit_logs where action = 'password_reset';
  select count(*) into v_user_updates from public.audit_logs where action in ('update_employee_information', 'update_employee_profile', 'update_employee_details', 'update_user_information', 'user_role_change');
  select count(*) into v_today_actions from public.audit_logs where created_at >= date_trunc('day', now());

  return jsonb_build_object(
    'total_logs', coalesce(v_total, 0),
    'password_resets', coalesce(v_password_resets, 0),
    'user_updates', coalesce(v_user_updates, 0),
    'today_actions', coalesce(v_today_actions, 0)
  );
end;
$$;

-- 10. Grant permissions
grant execute on function public.admin_reset_user_password(uuid, text) to authenticated;
grant execute on function public.admin_set_user_role(uuid, text) to authenticated;
grant execute on function public.admin_set_user_ban(uuid, boolean) to authenticated;
grant execute on function public.admin_get_audit_logs(text, text, text, timestamptz, timestamptz, int, int) to authenticated;
grant execute on function public.admin_get_audit_stats() to authenticated;

notify pgrst, 'reload schema';

