-- Migration 0214: Create public storage bucket and RLS policies for company logos

insert into storage.buckets (id, name, public)
values ('company-logos', 'company-logos', true)
on conflict (id) do update
set public = true;

drop policy if exists "Anyone can read company logos" on storage.objects;
drop policy if exists "Authenticated users can upload company logos" on storage.objects;
drop policy if exists "Authenticated users can update company logos" on storage.objects;
drop policy if exists "Authenticated users can delete company logos" on storage.objects;
drop policy if exists "Anon and authenticated can upload company logos" on storage.objects;
drop policy if exists "Anon and authenticated can update company logos" on storage.objects;
drop policy if exists "Anon and authenticated can delete company logos" on storage.objects;

-- Allow reading company logos publicly
create policy "Anyone can read company logos"
on storage.objects for select
to public
using (bucket_id = 'company-logos');

-- Allow uploading company logos for anon and authenticated
create policy "Anon and authenticated can upload company logos"
on storage.objects for insert
to anon, authenticated
with check (bucket_id = 'company-logos');

-- Allow updating company logos
create policy "Anon and authenticated can update company logos"
on storage.objects for update
to anon, authenticated
using (bucket_id = 'company-logos')
with check (bucket_id = 'company-logos');

-- Allow deleting company logos
create policy "Anon and authenticated can delete company logos"
on storage.objects for delete
to anon, authenticated
using (bucket_id = 'company-logos');

