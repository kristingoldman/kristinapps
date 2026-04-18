export async function onRequestGet(context) {
  return new Response(
    JSON.stringify({ clientId: context.env.GOOGLE_CLIENT_ID || "" }),
    {
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "public, max-age=60",
      },
    },
  );
}
