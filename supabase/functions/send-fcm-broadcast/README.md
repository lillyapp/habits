# send-fcm-broadcast

Supabase Edge Function to send one FCM push message to all active rows in `public.push_subscriptions`.

## Required Secrets

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `PUSH_ADMIN_TOKEN` (your own shared secret for calling this function)

Firebase credentials (choose one variant):

- Preferred: `FIREBASE_SERVICE_ACCOUNT_JSON` (entire service-account JSON as one secret)
- Or legacy split secrets:
  - `FIREBASE_PROJECT_ID`
  - `FIREBASE_CLIENT_EMAIL`
  - `FIREBASE_PRIVATE_KEY` (paste with `\n` escaped line breaks)

## Set Secrets (recommended JSON variant)

1. Open your Firebase service-account JSON file.
2. Copy the full JSON (single line or pretty-printed both work).
3. Set secrets:

```bash
supabase secrets set \
  PUSH_ADMIN_TOKEN="YOUR_LONG_SECRET" \
  FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account","project_id":"...","private_key_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n","client_email":"...","client_id":"..."}'
```

The function also needs `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` (usually already available in Supabase Edge Functions runtime).

## Example Invocation

```bash
curl -X POST "https://<PROJECT-REF>.functions.supabase.co/send-fcm-broadcast" \
  -H "Authorization: Bearer <PUSH_ADMIN_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Reminder",
    "body": "Zeit für deine Habits.",
    "url": "https://lillyapp.github.io/habits/",
    "data": { "type": "reminder" }
  }'
```
