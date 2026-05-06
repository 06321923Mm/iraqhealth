import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ── Service-account credentials from Supabase Edge Function secrets ──────────
const FIREBASE_PROJECT_ID  = Deno.env.get("FIREBASE_PROJECT_ID") ?? "";
const FIREBASE_CLIENT_EMAIL = Deno.env.get("FIREBASE_CLIENT_EMAIL") ?? "";
// Newlines are stored escaped in secrets; unescape them.
const FIREBASE_PRIVATE_KEY  = (Deno.env.get("FIREBASE_PRIVATE_KEY") ?? "")
  .replace(/\\n/g, "\n");

// ── Helpers ───────────────────────────────────────────────────────────────────

function base64url(data: ArrayBuffer | string): string {
  let str: string;
  if (typeof data === "string") {
    str = btoa(data);
  } else {
    str = btoa(String.fromCharCode(...new Uint8Array(data)));
  }
  return str.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Import the PEM private key as a CryptoKey usable with RS256. */
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const pemBody = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");

  const der = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

/**
 * Build a signed JWT and exchange it for a short-lived OAuth2 access token
 * scoped to Firebase Cloud Messaging.
 */
async function getFcmAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const claims = {
    iss:   FIREBASE_CLIENT_EMAIL,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud:   "https://oauth2.googleapis.com/token",
    iat:   now,
    exp:   now + 3600,
  };

  const header  = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64url(JSON.stringify(claims));
  const unsigned = `${header}.${payload}`;

  const privateKey = await importPrivateKey(FIREBASE_PRIVATE_KEY);
  const signatureBytes = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    privateKey,
    new TextEncoder().encode(unsigned),
  );
  const signature = base64url(signatureBytes);
  const jwt = `${unsigned}.${signature}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion:  jwt,
    }),
  });

  if (!tokenRes.ok) {
    const detail = await tokenRes.text();
    throw new Error(`Google token exchange failed (${tokenRes.status}): ${detail}`);
  }

  const { access_token } = await tokenRes.json();
  if (!access_token) throw new Error("No access_token in Google response.");
  return access_token as string;
}

// ── Main handler ──────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  // Handle pre-flight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    // Validate presence of required env vars
    if (!FIREBASE_PROJECT_ID || !FIREBASE_CLIENT_EMAIL || !FIREBASE_PRIVATE_KEY) {
      throw new Error(
        "Missing Firebase credentials. Ensure FIREBASE_PROJECT_ID, " +
        "FIREBASE_CLIENT_EMAIL, and FIREBASE_PRIVATE_KEY secrets are set.",
      );
    }

    const { user_id, title, body, data } = await req.json() as {
      user_id: string;
      title:   string;
      body:    string;
      data?:   Record<string, string>;
    };

    if (!user_id || !title || !body) {
      return new Response(
        JSON.stringify({ error: "user_id, title, and body are required." }),
        { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    // Use service-role key so we can read any user's FCM token.
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: tokenRow, error: tokenErr } = await supabase
      .from("user_fcm_tokens")
      .select("fcm_token, platform")
      .eq("user_id", user_id)
      .single();

    if (tokenErr || !tokenRow?.fcm_token) {
      // Not an error — user simply hasn't registered a token yet.
      return new Response(
        JSON.stringify({ skipped: true, reason: "No FCM token found for user." }),
        { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    const accessToken = await getFcmAccessToken();

    const fcmPayload = {
      message: {
        token:        tokenRow.fcm_token,
        notification: { title, body },
        // data values must be strings
        data: Object.fromEntries(
          Object.entries(data ?? {}).map(([k, v]) => [k, String(v)]),
        ),
        android: {
          priority:     "high",
          notification: {
            channel_id:   "verification_updates",
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        apns: {
          payload: { aps: { sound: "default", badge: 1 } },
          headers: { "apns-priority": "10" },
        },
        webpush: {
          headers:      { Urgency: "high" },
          notification: { icon: "/icons/Icon-192.png" },
        },
      },
    };

    const fcmUrl =
      `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`;

    const fcmRes = await fetch(fcmUrl, {
      method:  "POST",
      headers: {
        Authorization:  `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(fcmPayload),
    });

    const fcmBody = await fcmRes.json();

    if (!fcmRes.ok) {
      throw new Error(
        `FCM API returned ${fcmRes.status}: ${JSON.stringify(fcmBody)}`,
      );
    }

    return new Response(
      JSON.stringify({ success: true, message_id: fcmBody.name }),
      { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("[send-notification]", message);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }
});
