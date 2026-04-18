import { readSession } from "./_shared/session.js";

const PROTECTED_PREFIXES = ["/pages/", "/receipts/"];

export async function onRequest(context) {
  const { request, next, env } = context;
  const url = new URL(request.url);

  const isProtected = PROTECTED_PREFIXES.some((p) => url.pathname.startsWith(p));
  if (!isProtected) {
    return next();
  }

  const session = await readSession(request, env.SESSION_SECRET);
  if (session) {
    return next();
  }

  const loginUrl = new URL("/auth/login", url.origin);
  loginUrl.searchParams.set("redirect", url.pathname + url.search);
  return Response.redirect(loginUrl.toString(), 302);
}
