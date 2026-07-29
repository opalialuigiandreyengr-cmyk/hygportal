insert into storage.buckets (id, name, public)
values ('employee-profile-photos', 'employee-profile-photos', true)
on conflict (id) do update
set public = true;

drop policy if exists "Users can upload own employee profile photos" on storage.objects;
drop policy if exists "Users can update own employee profile photos" on storage.objects;
drop policy if exists "Anyone can read employee profile photos" on storage.objects;

create policy "Users can upload own employee profile photos"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'employee-profile-photos'
  and exists (
    select 1
    from public.user_profiles up
    where up.auth_user_id = auth.uid()
      and up.employee_id::text = (storage.foldername(name))[1]
  )
);

create policy "Users can update own employee profile photos"
on storage.objects for update
to authenticated
using (
  bucket_id = 'employee-profile-photos'
  and exists (
    select 1
    from public.user_profiles up
    where up.auth_user_id = auth.uid()
      and up.employee_id::text = (storage.foldername(name))[1]
  )
)
with check (
  bucket_id = 'employee-profile-photos'
  and exists (
    select 1
    from public.user_profiles up
    where up.auth_user_id = auth.uid()
      and up.employee_id::text = (storage.foldername(name))[1]
  )
);

create policy "Anyone can read employee profile photos"
on storage.objects for select
to public
using (bucket_id = 'employee-profile-photos');

create or replace function public.update_own_employee_photo(p_photo_url text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
  v_photo_url text := nullif(trim(p_photo_url), '');
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to update your profile photo.';
  end if;

  select *
  into v_profile
  from public.user_profiles
  where auth_user_id = auth.uid()
  limit 1;

  if v_profile.id is null or v_profile.employee_id is null then
    raise exception 'This login is not linked to an employee profile.';
  end if;

  update public.employees
  set photo_url = v_photo_url,
      updated_at = now()
  where id = v_profile.employee_id;

  return v_photo_url;
end;
$$;

grant execute on function public.update_own_employee_photo(text) to authenticated;
