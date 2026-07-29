-- Release a second 100 HYG Points gift for employees with 100% profile completion.

create or replace function public.is_employee_profile_100_percent_complete(p_user_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select
      nullif(btrim(coalesce(e.first_name, '')), '') is not null
      and nullif(btrim(coalesce(e.last_name, '')), '') is not null
      and e.birth_date is not null
      and nullif(btrim(coalesce(e.gender, '')), '') is not null
      and nullif(btrim(coalesce(epd.religion, '')), '') is not null
      and nullif(btrim(coalesce(epd.birth_place, '')), '') is not null
      and nullif(btrim(coalesce(epd.nationality, '')), '') is not null
      and nullif(btrim(coalesce(e.civil_status, '')), '') is not null
      and nullif(btrim(coalesce(epd.height, '')), '') is not null
      and nullif(btrim(coalesce(epd.weight, '')), '') is not null
      and nullif(btrim(coalesce(e.email, '')), '') is not null
      and nullif(btrim(coalesce(e.phone, '')), '') is not null
      and nullif(btrim(coalesce(epd.other_phone, '')), '') is not null
      and nullif(btrim(coalesce(epd.social_media_type, '')), '') is not null
      and nullif(btrim(coalesce(epd.social_media_detail, '')), '') is not null
      and nullif(btrim(coalesce(epd.present_address, '')), '') is not null
      and nullif(btrim(coalesce(epd.zip_code, '')), '') is not null
      and nullif(btrim(coalesce(epd.permanent_address, '')), '') is not null
      and nullif(btrim(coalesce(epd.employee_type, '')), '') is not null
      and nullif(btrim(coalesce(up.username, '')), '') is not null
      and nullif(btrim(coalesce(epd.tin, '')), '') is not null
      and nullif(btrim(coalesce(epd.sss, '')), '') is not null
      and nullif(btrim(coalesce(epd.pagibig, '')), '') is not null
      and nullif(btrim(coalesce(epd.philhealth, '')), '') is not null
      and nullif(btrim(coalesce(epd.bank_type, '')), '') is not null
      and nullif(btrim(coalesce(epd.account_no, '')), '') is not null
      and nullif(btrim(coalesce(epd.elementary_school, '')), '') is not null
      and nullif(btrim(coalesce(epd.elementary_year, '')), '') is not null
      and nullif(btrim(coalesce(epd.secondary_school, '')), '') is not null
      and nullif(btrim(coalesce(epd.secondary_year, '')), '') is not null
      and nullif(btrim(coalesce(epd.college_school, '')), '') is not null
      and nullif(btrim(coalesce(epd.college_year, '')), '') is not null
      and nullif(btrim(coalesce(epd.college_course, '')), '') is not null
      and nullif(btrim(coalesce(epd.year_graduated, '')), '') is not null
      and nullif(btrim(coalesce(epd.father_name, '')), '') is not null
      and nullif(btrim(coalesce(epd.father_occupation, '')), '') is not null
      and nullif(btrim(coalesce(epd.mother_maiden_name, '')), '') is not null
      and nullif(btrim(coalesce(epd.mother_occupation, '')), '') is not null
      and nullif(btrim(coalesce(epd.number_of_siblings, '')), '') is not null
      and nullif(btrim(coalesce(epd.birth_order, '')), '') is not null
      and nullif(btrim(coalesce(epd.emergency_contact, '')), '') is not null
      and nullif(btrim(coalesce(epd.emergency_contact_no, '')), '') is not null
      and (
        lower(btrim(coalesce(e.civil_status, ''))) <> 'married'
        or (
          nullif(btrim(coalesce(epd.spouse_name, '')), '') is not null
          and nullif(btrim(coalesce(epd.spouse_occupation, '')), '') is not null
          and nullif(btrim(coalesce(epd.spouse_contact, '')), '') is not null
        )
      )
      and (
        not (
          case
            when btrim(coalesce(epd.children_count, '')) ~ '^[0-9]+$'
              then btrim(epd.children_count)::int
            else 0
          end > 0
          or nullif(btrim(coalesce(epd.children_names, '')), '') is not null
        )
        or (
          case
            when btrim(coalesce(epd.children_count, '')) ~ '^[0-9]+$'
              then btrim(epd.children_count)::int
            else 0
          end > 0
          and nullif(btrim(coalesce(epd.children_names, '')), '') is not null
        )
      )
    from public.user_profiles up
    join public.employees e
      on e.id = up.employee_id
    left join public.employee_profile_details epd
      on epd.employee_id = e.id
    where up.id = p_user_profile_id
      and up.auth_user_id is not null
      and up.employee_id is not null
      and up.is_active = true
  ), false);
$$;

create or replace function public.ensure_profile_completion_hyg_points_gift(p_user_profile_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_account_id uuid;
  v_transaction_id uuid;
  v_notification_id uuid;
begin
  if not public.is_employee_profile_100_percent_complete(p_user_profile_id) then
    return null;
  end if;

  select *
  into v_profile
  from public.user_profiles up
  where up.id = p_user_profile_id
    and up.auth_user_id is not null
    and up.employee_id is not null
    and up.is_active = true;

  if v_profile.id is null then
    return null;
  end if;

  insert into public.user_hyg_point_accounts (
    user_profile_id,
    auth_user_id,
    employee_id
  )
  values (
    v_profile.id,
    v_profile.auth_user_id,
    v_profile.employee_id
  )
  on conflict (user_profile_id) do update
  set auth_user_id = excluded.auth_user_id,
      employee_id = excluded.employee_id,
      updated_at = now()
  returning id into v_account_id;

  select t.id, t.notification_id
  into v_transaction_id, v_notification_id
  from public.user_hyg_point_transactions t
  where t.user_profile_id = v_profile.id
    and t.source = 'profile_completion_100_percent';

  if v_transaction_id is not null then
    update public.user_hyg_point_transactions
    set account_id = v_account_id,
        auth_user_id = v_profile.auth_user_id,
        employee_id = v_profile.employee_id
    where id = v_transaction_id;

    return v_transaction_id;
  end if;

  insert into public.user_hyg_point_transactions (
    account_id,
    user_profile_id,
    auth_user_id,
    employee_id,
    source,
    points,
    status,
    release_at,
    note
  )
  values (
    v_account_id,
    v_profile.id,
    v_profile.auth_user_id,
    v_profile.employee_id,
    'profile_completion_100_percent',
    100,
    'released',
    now(),
    '100% employee profile completion reward.'
  )
  returning id into v_transaction_id;

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
    '100 HYG Points Profile Completion Gift',
    'You received 100 HYG Points for successfully completing 100% of your employee profile. Claim your gift to add it to your HYG Points balance.',
    'hyg_points_claim',
    v_transaction_id
  )
  returning id into v_notification_id;

  update public.user_hyg_point_transactions
  set notification_id = v_notification_id
  where id = v_transaction_id;

  return v_transaction_id;
end;
$$;

create or replace function public.ensure_my_profile_completion_hyg_points_gift()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
begin
  select up.id
  into v_profile_id
  from public.user_profiles up
  where up.auth_user_id = auth.uid()
    and up.employee_id is not null
    and up.is_active = true
  order by up.created_at desc
  limit 1;

  if v_profile_id is null then
    return null;
  end if;

  return public.ensure_profile_completion_hyg_points_gift(v_profile_id);
end;
$$;

create or replace function public.delete_my_notification(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.user_hyg_point_transactions t
  set notification_deleted_at = now(),
      notification_id = null
  from public.notifications n
  where n.id = p_notification_id
    and t.notification_id = n.id
    and t.auth_user_id = auth.uid()
    and n.link_type = 'hyg_points_claim';

  delete from public.notifications n
  where n.id = p_notification_id
    and exists (
      select 1
      from public.user_profiles up
      where up.auth_user_id = auth.uid()
        and (up.id = n.user_profile_id or up.employee_id = n.employee_id)
    );
end;
$$;

select public.ensure_profile_completion_hyg_points_gift(up.id)
from public.user_profiles up
where up.auth_user_id is not null
  and up.employee_id is not null
  and up.is_active = true
  and public.is_employee_profile_100_percent_complete(up.id);

revoke all on function public.is_employee_profile_100_percent_complete(uuid) from public, anon, authenticated;
revoke all on function public.ensure_profile_completion_hyg_points_gift(uuid) from public, anon, authenticated;
grant execute on function public.ensure_my_profile_completion_hyg_points_gift() to authenticated;
grant execute on function public.delete_my_notification(uuid) to authenticated;
