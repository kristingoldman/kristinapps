export async function onRequest(context) {
  const url = new URL(context.request.url);
  const redirect = url.searchParams.get("redirect") || "/";

  return new Response(null, {
    status: 302,
    headers: {
      "Location": redirect,
      "Set-Cookie": "albastyle_session=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0",
    },
  });
}
