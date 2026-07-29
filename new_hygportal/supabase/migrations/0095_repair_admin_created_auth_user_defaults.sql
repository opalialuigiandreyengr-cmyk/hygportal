-- Repair auth defaults for SQL-created users so Supabase Auth password login can read them.

update auth.users au
set
  confirmation_token = coalesce(au.confirmation_token, ''),
  recovery_token = coalesce(au.recovery_token, ''),
  email_change = coalesce(au.email_change, ''),
  email_change_token_new = coalesce(au.email_change_token_new, ''),
  raw_user_meta_data = coalesce(au.raw_user_meta_data, '{}'::jsonb)
    || jsonb_build_object('email_verified', true),
  updated_at = now()
from public.user_profiles up
where up.auth_user_id = au.id
  and au.email is not null;

update auth.identities ai
set
  identity_data = coalesce(ai.identity_data, '{}'::jsonb)
    || jsonb_build_object(
      'sub', au.id::text,
      'email', au.email::text,
      'email_verified', true,
      'phone_verified', false
    ),
  updated_at = now()
from auth.users au
join public.user_profiles up on up.auth_user_id = au.id
where ai.user_id = au.id
  and ai.provider = 'email'
  and au.email is not null;

notify pgrst, 'reload schema';
