drop policy if exists "Anyone can read active companies" on public.companies;

create policy "Anyone can read active companies"
on public.companies for select
to anon, authenticated
using (is_active = true);

notify pgrst, 'reload schema';
