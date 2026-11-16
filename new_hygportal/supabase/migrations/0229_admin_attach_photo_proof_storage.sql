-- Storage for photo proofs attached by HR/admin users from Admin Desktop.
insert into storage.buckets (id, name, public)
values ('photo-proof-attachments', 'photo-proof-attachments', true)
on conflict (id) do update set public = true;

drop policy if exists "Authenticated users can upload admin photo proofs" on storage.objects;
drop policy if exists "Anyone can read admin photo proofs" on storage.objects;

create policy "Authenticated users can upload admin photo proofs"
on storage.objects for insert
to authenticated
with check (bucket_id = 'photo-proof-attachments');

create policy "Anyone can read admin photo proofs"
on storage.objects for select
to anon, authenticated
using (bucket_id = 'photo-proof-attachments');
