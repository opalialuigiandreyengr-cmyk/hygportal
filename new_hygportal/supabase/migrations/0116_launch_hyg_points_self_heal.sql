-- Let existing registered users self-heal the Phase 1 HYG Points gift when
-- they open the notification center.

create or replace function public.ensure_my_launch_hyg_points_gift()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
  v_transaction_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  select up.id
  into v_profile_id
  from public.user_profiles up
  where up.auth_user_id = auth.uid()
    and up.employee_id is not null
    and up.is_active = true
  order by up.created_at asc
  limit 1;

  if v_profile_id is null then
    raise exception 'Your login is not linked to an active employee profile.';
  end if;

  v_transaction_id := public.ensure_launch_hyg_points_gift(v_profile_id);
  return v_transaction_id;
end;
$$;

grant execute on function public.ensure_my_launch_hyg_points_gift() to authenticated;

notify pgrst, 'reload schema';
