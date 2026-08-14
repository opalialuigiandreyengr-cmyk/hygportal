create or replace function public.get_my_notifications()
returns table (
  id uuid,
  title text,
  body text,
  created_at timestamptz,
  read_at timestamptz,
  action_type text,
  action_label text,
  action_status text,
  action_id uuid,
  points numeric,
  release_at timestamptz,
  received_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    n.id,
    n.title,
    n.message as body,
    n.created_at,
    case when n.is_read then n.created_at else null end as read_at,
    case
      when n.link_type = 'hyg_points_claim' then 'hyg_points_claim'
      when n.link_type = 'approval' then 'approval'
      else n.link_type
    end as action_type,
    case
      when n.link_type = 'hyg_points_claim' and hpt.status = 'released' then 'Claim'
      when n.link_type = 'hyg_points_claim' and hpt.status = 'claimed' then 'Claimed'
      else null
    end as action_label,
    hpt.status as action_status,
    coalesce(hpt.id, n.link_id) as action_id,
    hpt.points,
    hpt.release_at,
    hpt.received_at
  from public.notifications n
  join public.user_profiles up
    on up.auth_user_id = auth.uid()
   and (up.id = n.user_profile_id or up.employee_id = n.employee_id)
  left join public.user_hyg_point_transactions hpt
    on n.link_type = 'hyg_points_claim'
   and hpt.id = n.link_id
   and hpt.auth_user_id = auth.uid()
  order by n.created_at desc
  limit 100;
$$;
