import {
  ALLOWED_EMAILS,
  COOKIE_NAME,
  hmacSign,
  b64urlEncode,
} from "../_shared/session.js";

const SESSION_TTL_SECONDS = 7 * 24 * 60 * 60;

export async function onRequestPost(context) {
  const { request, env } = context;

  if (!env.SESSION_SECRET || !env.GOOGLE_CLIENT_ID) {
    return json({ error: "server_not_configured" }, 500);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const credential = body?.credential;
  if (!credential) return json({ error: "missing_credential" }, 400);

  const payload = await verifyGoogleIdToken(credential, env.GOOGLE_CLIENT_ID);
  if (!payload) return json({ error: "invalid_token" }, 401);

  if (!payload.email_verified) return json({ error: "email_not_verified" }, 403);
  if (!ALLOWED_EMAILS.includes(payload.email)) {
    return json({ error: "not_authorized", email: payload.email }, 403);
  }

  const exp = Date.now() + SESSION_TTL_SECONDS * 1000;
  const session = { email: payload.email, name: payload.name || "", exp };
  const cookieValue = await signSession(session, env.SESSION_SECRET);

  return new Response(JSON.stringify({ ok: true, email: payload.email }), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "Set-Cookie": `${COOKIE_NAME}=${cookieValue}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${SESSION_TTL_SECONDS}`,
    },
  });
}

async function verifyGoogleIdToken(token, expectedClientId) {
  const res = await fetch(
    `https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(token)}`,
  );
  if (!res.ok) return null;
  const data = await res.json();

  if (data.aud !== expectedClientId) return null;
  if (data.iss !== "https://accounts.google.com" && data.iss !== "accounts.google.com") return null;
  if (Number(data.exp) * 1000 < Date.now()) return null;

  return data;
}

async function signSession(payload, secret) {
  const payloadB64 = b64urlEncode(new TextEncoder().encode(JSON.stringify(payload)));
  const sig = await hmacSign(payloadB64, secret);
  return `${payloadB64}.${sig}`;
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
