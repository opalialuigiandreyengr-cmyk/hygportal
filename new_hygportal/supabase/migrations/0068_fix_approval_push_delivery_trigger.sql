-- Replace the malformed hosted webhook binding with an asynchronous pg_net
-- request. The Edge Function can only send existing queued outbox messages.

create extension if not exists pg_net with schema extensions;

do $$
declare
  v_trigger record;
begin
  for v_trigger in
    select t.tgname
    from pg_trigger t
    where t.tgrelid = 'public.approval_push_outbox'::regclass
      and not t.tgisinternal
  loop
    execute format('drop trigger if exists %I on public.approval_push_outbox', v_trigger.tgname);
  end loop;
end;
$$;

create or replace function public.send_approval_push_outbox_record()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform net.http_post(
    url := 'https://dkabosehgvldiwtdmvxh.supabase.co/functions/v1/approval-push',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object('record', jsonb_build_object('id', new.id))
  );

  return new;
end;
$$;

create trigger trg_send_approval_push_outbox_record
after insert on public.approval_push_outbox
for each row
execute function public.send_approval_push_outbox_record();

notify pgrst, 'reload schema';
