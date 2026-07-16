-- Fallback storage for employee profile document photos when the Drive uploader is unreachable.

insert into storage.buckets (id, name, public)
values ('employee-documents', 'employee-documents', false)
on conflict (id) do update
set public = false;

drop policy if exists "Anyone can upload employee document photos" on storage.objects;
drop policy if exists "Authenticated users can upload employee document photos" on storage.objects;
drop policy if exists "Authenticated users can read employee document photos" on storage.objects;

create policy "Anyone can upload employee document photos"
on storage.objects for insert
to anon, authenticated
with check (bucket_id = 'employee-documents');

create policy "Authenticated users can upload employee document photos"
on storage.objects for update
to authenticated
using (bucket_id = 'employee-documents')
with check (bucket_id = 'employee-documents');

create policy "Authenticated users can read employee document photos"
on storage.objects for select
to authenticated
using (bucket_id = 'employee-documents');
