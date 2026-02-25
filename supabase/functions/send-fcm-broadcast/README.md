# send-fcm-broadcast

Supabase Edge Function to send one FCM push message to all active rows in `public.push_subscriptions`.

## Required Secrets

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `PUSH_ADMIN_TOKEN` (your own shared secret for calling this function)
- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY` (paste with `\n` escaped line breaks)

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
