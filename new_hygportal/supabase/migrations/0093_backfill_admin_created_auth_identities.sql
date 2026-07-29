-- Repair admin-created users that were inserted into auth.users without an email identity.

insert into auth.identities (
  provider_id,
  user_id,
  identity_data,
  provider,
  last_sign_in_at,
  created_at,
  updated_at
)
select
  au.id::text,
  au.id,
  jsonb_build_object(
    'sub', au.id::text,
    'email', au.email::text,
    'email_verified', true,
    'phone_verified', false
  ),
  'email',
  now(),
  now(),
  now()
from auth.users au
join public.user_profiles up on up.auth_user_id = au.id
where au.email is not null
  and not exists (
    select 1
    from auth.identities ai
    where ai.user_id = au.id
      and ai.provider = 'email'
  );

notify pgrst, 'reload schema';
