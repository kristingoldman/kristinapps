import { readSession } from "../_shared/session.js";

export async function onRequestGet(context) {
  const { request, env } = context;

  const session = await readSession(request, env.SESSION_SECRET);
  if (!session) return json({ error: "unauthorized" }, 401);

  if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) {
    return json({ error: "server_not_configured" }, 500);
  }

  const base = env.SUPABASE_URL.replace(/\/$/, "");
  const headers = {
    apikey: env.SUPABASE_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
    "Content-Type": "application/json",
  };

  const receiptsRes = await fetch(
    `${base}/rest/v1/receipts?select=*&order=created_at.asc`,
    { headers },
  );
  if (!receiptsRes.ok) {
    return json({ error: "supabase_error", status: receiptsRes.status }, 502);
  }
  const receipts = await receiptsRes.json();

  if (receipts.length === 0) {
    return json({ receipts: [], viewer: session.email });
  }

  const idList = receipts.map((r) => `"${r.id}"`).join(",");
  const itemsRes = await fetch(
    `${base}/rest/v1/receipt_items?select=receipt_id,name,qty,price,url,position&receipt_id=in.(${idList})&order=receipt_id,position.asc`,
    { headers },
  );
  const items = itemsRes.ok ? await itemsRes.json() : [];

  const itemsByReceipt = {};
  for (const it of items) {
    (itemsByReceipt[it.receipt_id] ||= []).push({
      name: it.name,
      qty: it.qty,
      price: it.price,
      url: it.url,
    });
  }
  for (const r of receipts) {
    r.items = itemsByReceipt[r.id] || [];
  }

  return json({ receipts, viewer: session.email });
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
