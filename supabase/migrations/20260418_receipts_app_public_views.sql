-- Public pass-through views for the /api/receipts Pages Function.
--
-- The Supabase PostgREST instance only exposes the public schema by default
-- (see SUPABASE dashboard → Settings → API → Exposed schemas). Rather than
-- asking the user to add receipts_app to that list, we expose read-only
-- pass-through views here.
--
-- RLS on the underlying receipts_app.* tables still prevents anon and
-- authenticated roles from reading data through these views — only
-- service_role (used by our Pages Function) and direct Postgres connections
-- (used by the watcher) can see anything.

create or replace view public.receipts_enriched as
  select * from receipts_app.v_receipts_enriched;

create or replace view public.receipt_items_enriched as
  select
    ri.id,
    ri.receipt_id,
    ri.product_variant_id,
    ri.name_at_purchase as name,
    ri.qty,
    ri.price_at_purchase as price,
    ri.url_at_purchase as url,
    ri.position,
    p.id as product_id,
    p.canonical_name as product_name,
    p.product_url as product_url_canonical,
    p.image_url as product_image_url,
    p.brand,
    p.category,
    m.id as merchant_id,
    m.name as merchant_name
  from receipts_app.receipt_items ri
  left join receipts_app.product_variants v on v.id = ri.product_variant_id
  left join receipts_app.products p on p.id = v.product_id
  left join receipts_app.merchants m on m.id = p.merchant_id;

grant select on public.receipts_enriched to service_role;
grant select on public.receipt_items_enriched to service_role;
