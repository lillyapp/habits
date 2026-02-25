import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

type BroadcastRequest = {
  title?: string;
  body?: string;
  url?: string;
  data?: Record<string, string>;
};

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "authorization, content-type",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      ...corsHeaders,
    },
  });
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing env: ${name}`);
  return value;
}

function getBearerToken(req: Request): string {
  const auth = req.headers.get("authorization") || "";
  const match = auth.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() || "";
}

function chunk<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

async function getFcmAccessToken() {
  const projectId = requireEnv("FIREBASE_PROJECT_ID");
  const clientEmail = requireEnv("FIREBASE_CLIENT_EMAIL");
  const privateKey = requireEnv("FIREBASE_PRIVATE_KEY").replace(/\\n/g, "\n");

  const auth = new GoogleAuth({
    credentials: {
      project_id: projectId,
      client_email: clientEmail,
      private_key: privateKey,
    },
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });

  const client = await auth.getClient();
  const token = await client.getAccessToken();
  const accessToken = typeof token === "string" ? token : (token?.token || "");
  if (!accessToken) throw new Error("Could not obtain Google access token.");

  return { projectId, accessToken };
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Method not allowed" });

  try {
    const adminToken = requireEnv("PUSH_ADMIN_TOKEN");
    const bearer = getBearerToken(req);
    if (!bearer || bearer !== adminToken) {
      return json(401, { error: "Unauthorized" });
    }

    const body = (await req.json()) as BroadcastRequest;
    const title = String(body?.title || "").trim();
    const messageBody = String(body?.body || "").trim();
    const clickUrl = String(body?.url || "https://lillyapp.github.io/habits/").trim();
    const data = Object.fromEntries(
      Object.entries(body?.data || {}).map(([k, v]) => [String(k), String(v)])
    );

    if (!title || !messageBody) {
      return json(400, { error: "title and body are required" });
    }

    const supabaseUrl = requireEnv("SUPABASE_URL");
    const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { data: rows, error } = await supabase
      .from("push_subscriptions")
      .select("id, token")
      .eq("is_active", true);

    if (error) throw error;

    const tokens = Array.from(new Set((rows || []).map((r) => String(r.token || "")).filter(Boolean)));
    if (!tokens.length) {
      return json(200, { ok: true, sent: 0, failed: 0, inactive_marked: 0, message: "No active tokens found." });
    }

    const { projectId, accessToken } = await getFcmAccessToken();
    const endpoint = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

    const invalidTokens = new Set<string>();
    let sent = 0;
    let failed = 0;

    for (const batch of chunk(tokens, 50)) {
      const results = await Promise.allSettled(batch.map(async (token) => {
        const response = await fetch(endpoint, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify({
            message: {
              token,
              notification: {
                title,
                body: messageBody,
              },
              data: {
                url: clickUrl,
                ...data,
              },
              webpush: {
                fcm_options: { link: clickUrl },
                notification: {
                  icon: "https://lillyapp.github.io/habits/3FC2E555-7142-43BE-83DE-E5ED7A123793.png",
                  badge: "https://lillyapp.github.io/habits/3FC2E555-7142-43BE-83DE-E5ED7A123793.png",
                },
              },
            },
          }),
        });

        if (response.ok) return;

        const errJson = await response.json().catch(() => ({}));
        const errText = JSON.stringify(errJson);
        if (/UNREGISTERED|registration-token-not-registered|INVALID_ARGUMENT/i.test(errText)) {
          invalidTokens.add(token);
        }
        throw new Error(`FCM send failed (${response.status}): ${errText}`);
      }));

      for (const result of results) {
        if (result.status === "fulfilled") sent += 1;
        else failed += 1;
      }
    }

    let inactiveMarked = 0;
    if (invalidTokens.size > 0) {
      const { data: updatedRows, error: updateError } = await supabase
        .from("push_subscriptions")
        .update({ is_active: false, last_seen_at: new Date().toISOString() })
        .in("token", Array.from(invalidTokens))
        .select("id");
      if (!updateError) inactiveMarked = updatedRows?.length || 0;
    }

    return json(200, {
      ok: true,
      sent,
      failed,
      inactive_marked: inactiveMarked,
      total_tokens: tokens.length,
    });
  } catch (err) {
    console.error("send-fcm-broadcast error:", err);
    return json(500, { error: err instanceof Error ? err.message : String(err) });
  }
});
