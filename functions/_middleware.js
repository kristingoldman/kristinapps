const ALLOWED_EMAILS = [
  "kristinhudsongoldman@gmail.com",
  "rgoldman@gmail.com",
];

const COOKIE_NAME = "albastyle_session";
const PROTECTED_PREFIX = "/pages/";

export async function onRequest(context) {
  const { request, next, env } = context;
  const url = new URL(request.url);

  if (!url.pathname.startsWith(PROTECTED_PREFIX)) {
    return next();
  }

  const session = await readSession(request, env.SESSION_SECRET);
  if (session && ALLOWED_EMAILS.includes(session.email) && session.exp > Date.now()) {
    return next();
  }

  const loginUrl = new URL("/auth/login", url.origin);
  loginUrl.searchParams.set("redirect", url.pathname + url.search);
  return Response.redirect(loginUrl.toString(), 302);
}

async function readSession(request, secret) {
  if (!secret) return null;
  const cookie = request.headers.get("Cookie") || "";
  const match = cookie.match(new RegExp(`${COOKIE_NAME}=([^;]+)`));
  if (!match) return null;

  const [payloadB64, sigB64] = match[1].split(".");
  if (!payloadB64 || !sigB64) return null;

  const expected = await hmacSign(payloadB64, secret);
  if (!timingSafeEqual(expected, sigB64)) return null;

  try {
    return JSON.parse(b64urlDecode(payloadB64));
  } catch {
    return null;
  }
}

async function hmacSign(data, secret) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(data));
  return b64urlEncode(new Uint8Array(sig));
}

function b64urlEncode(bytes) {
  let str = "";
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlDecode(s) {
  const pad = s.length % 4 === 0 ? "" : "=".repeat(4 - (s.length % 4));
  return atob(s.replace(/-/g, "+").replace(/_/g, "/") + pad);
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
