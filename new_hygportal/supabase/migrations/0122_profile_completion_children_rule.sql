-- Match the profile completion reward rule with the dashboard completion rule.

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
          nullif(btrim(coalesce(epd.children_count, '')), '') is not null
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

select public.ensure_profile_completion_hyg_points_gift(up.id)
from public.user_profiles up
where up.auth_user_id is not null
  and up.employee_id is not null
  and up.is_active = true
  and public.is_employee_profile_100_percent_complete(up.id);

revoke all on function public.is_employee_profile_100_percent_complete(uuid) from public, anon, authenticated;
