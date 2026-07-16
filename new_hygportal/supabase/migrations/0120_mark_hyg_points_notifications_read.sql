-- Restore existing HYG Points gift messages to the Read tab.

update public.notifications n
set is_read = true
from public.user_hyg_point_transactions t
where n.link_type = 'hyg_points_claim'
  and n.link_id = t.id
  and t.source = 'launch_phase_1_profile_creation'
  and n.is_read = false;
