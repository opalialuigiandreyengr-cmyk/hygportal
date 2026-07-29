-- Treat MAIN OFFICE HQ as N/A instead of a real store.
-- N/A is represented by a null store_id throughout the app.

do $$
declare
  v_store_ids uuid[];
begin
  select coalesce(array_agg(id), '{}'::uuid[])
  into v_store_ids
  from public.stores
  where lower(trim(name)) = 'main office hq';

  if array_length(v_store_ids, 1) is null then
    return;
  end if;

  update public.employee_assignments
  set store_id = null
  where store_id = any(v_store_ids);

  update public.authority_assignments
  set store_id = null
  where store_id = any(v_store_ids);

  update public.requests
  set store_id = null
  where store_id = any(v_store_ids);

  update public.stores
  set cluster_id = null,
      area_id = null
  where id = any(v_store_ids);

  delete from public.stores
  where id = any(v_store_ids);
exception
  when foreign_key_violation then
    update public.stores
    set is_active = false,
        cluster_id = null,
        area_id = null
    where id = any(v_store_ids);
end;
$$;

notify pgrst, 'reload schema';
