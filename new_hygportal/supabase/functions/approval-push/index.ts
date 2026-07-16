import { createClient } from 'npm:@supabase/supabase-js@2';

type OutboxRecord = {
  id?: string;
};

type WebhookPayload = {
  record?: OutboxRecord;
};

type PushTokenRow = {
  expo_push_token: string;
};

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed.' }, 405);
  }

  try {
    const payload = (await req.json()) as WebhookPayload;
    const outboxId = payload.record?.id;
    if (!outboxId) {
      return json({ error: 'Outbox notification id is required.' }, 400);
    }

    const supabase = createClient(requiredEnv('SUPABASE_URL'), requiredEnv('SUPABASE_SERVICE_ROLE_KEY'), {
      auth: { persistSession: false },
    });

    const { data: outbox, error: outboxError } = await supabase
      .from('approval_push_outbox')
      .select('id, recipient_user_profile_id, title, message, payload, delivery_status')
      .eq('id', outboxId)
      .maybeSingle();

    if (outboxError) throw new Error(outboxError.message);
    if (!outbox || outbox.delivery_status !== 'queued') {
      return json({ ok: true, skipped: 'Notification is already processed or missing.' });
    }

    const { data: tokens, error: tokenError } = await supabase
      .from('mobile_push_tokens')
      .select('expo_push_token')
      .eq('user_profile_id', outbox.recipient_user_profile_id)
      .eq('is_enabled', true);

    if (tokenError) throw new Error(tokenError.message);
    if (!tokens?.length) {
      await updateOutbox(supabase, outbox.id, 'skipped', 'No enabled push token is registered.');
      return json({ ok: true, skipped: 'No enabled push token is registered.' });
    }

    const ticketResponse = await sendExpoNotifications(
      tokens as PushTokenRow[],
      outbox.title,
      outbox.message,
      outbox.payload as Record<string, unknown>,
    );
    const tickets = Array.isArray(ticketResponse.data) ? ticketResponse.data : [];
    const invalidTokens: string[] = [];
    const errors: string[] = [];

    tickets.forEach((ticket: { status?: string; message?: string; details?: { error?: string } }, index: number) => {
      if (ticket.status !== 'error') return;
      if (ticket.details?.error === 'DeviceNotRegistered') {
        invalidTokens.push(tokens[index].expo_push_token);
      }
      errors.push(ticket.message ?? ticket.details?.error ?? 'Expo Push rejected the alert.');
    });

    if (invalidTokens.length) {
      await supabase
        .from('mobile_push_tokens')
        .update({ is_enabled: false })
        .in('expo_push_token', invalidTokens);
    }

    await updateOutbox(supabase, outbox.id, errors.length ? 'failed' : 'sent', errors.join(' ') || null);
    return json({ ok: errors.length === 0, sent: tokens.length, errors });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Unable to send approval push notification.' }, 500);
  }
});

async function sendExpoNotifications(
  tokens: PushTokenRow[],
  title: string,
  body: string,
  data: Record<string, unknown>,
) {
  const headers: Record<string, string> = {
    Accept: 'application/json',
    'Accept-Encoding': 'gzip, deflate',
    'Content-Type': 'application/json',
  };
  const accessToken = Deno.env.get('EXPO_ACCESS_TOKEN');
  if (accessToken) {
    headers.Authorization = `Bearer ${accessToken}`;
  }

  const response = await fetch('https://exp.host/--/api/v2/push/send', {
    method: 'POST',
    headers,
    body: JSON.stringify(tokens.map(({ expo_push_token }) => ({
      to: expo_push_token,
      title,
      body,
      sound: 'default',
      priority: 'high',
      channelId: 'hygportal-alerts',
      data,
    }))),
  });

  const result = await response.json();
  if (!response.ok) {
    throw new Error(result?.errors?.[0]?.message ?? `Expo Push returned HTTP ${response.status}.`);
  }
  return result as { data?: Array<{ status?: string; message?: string; details?: { error?: string } }> };
}

async function updateOutbox(
  supabase: ReturnType<typeof createClient>,
  id: string,
  deliveryStatus: 'sent' | 'skipped' | 'failed',
  lastError: string | null,
) {
  const { error } = await supabase
    .from('approval_push_outbox')
    .update({
      delivery_status: deliveryStatus,
      attempts: 1,
      last_error: lastError,
      delivered_at: deliveryStatus === 'sent' ? new Date().toISOString() : null,
    })
    .eq('id', id);
  if (error) throw new Error(error.message);
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not configured.`);
  return value;
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
