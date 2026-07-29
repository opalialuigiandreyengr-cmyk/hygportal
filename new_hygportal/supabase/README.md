# Supabase

This folder contains Supabase migrations, seed data, and Edge Functions.

Planned structure:

```text
migrations/
seed/
functions/
```

The database owns the approval engine and access rules. The mobile app should not decide who approves a request.

## Approval Push Notifications

Migration `0065_approval_push_notifications.sql` stores Expo push tokens and creates the notification outbox. Migration `0066_request_workflow_notifications.sql` sends alerts when an ESARF or leave request reaches an approver and when the requester's ESARF or leave request is approved or rejected. The `approval-push` Edge Function sends those outbox records to Expo Push.

Deployment for a new environment:

```bash
supabase db push
supabase secrets set APPROVAL_PUSH_WEBHOOK_SECRET=<strong-random-secret>
supabase functions deploy approval-push --no-verify-jwt
```

Bind an asynchronous `INSERT` webhook from `public.approval_push_outbox` to the function, using either a Supabase Database Webhook or `pg_net`. Send the same secret as this request header:

```text
URL: https://<project-ref>.supabase.co/functions/v1/approval-push
Header: x-approval-push-secret: <same-secret>
```

The hosted `hygportal` project is configured with the `pg_net` version of this binding; its shared secret is stored only as hosted configuration, not in the repository.

An EAS development or production build is required for remote push testing on a physical Android/iOS device; Expo Go does not support this remote notification flow on current Android SDKs.
