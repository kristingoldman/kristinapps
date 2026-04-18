-- receipts_app schema — richer product + merchant catalog for the
-- albastyle.com/receipts tracker. Replaces the flat public.receipts /
-- public.receipt_items / public.receipt_watcher_state added earlier today.
--
-- Access model (same as before): RLS enabled with no anon/authenticated
-- policies. The machine-local watcher uses the direct Postgres connection;
-- the /api/receipts Pages Function uses the service_role key. The
-- Supabase anon key ships to browsers on other pages and must not see
-- purchase data.

create schema if not exists receipts_app;

create or replace function receipts_app.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---- merchants ----
create table if not exists receipts_app.merchants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  normalized_name text generated always as
    (lower(regexp_replace(name, '[^a-zA-Z0-9]+', '', 'g'))) stored,
  website text,
  support_email text,
  default_return_window_days int,
  default_return_policy_url text,
  default_restrictions text[] default '{}',
  logo_url text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (normalized_name)
);

drop trigger if exists merchants_set_updated_at on receipts_app.merchants;
create trigger merchants_set_updated_at
  before update on receipts_app.merchants
  for each row execute function receipts_app.set_updated_at();

-- ---- products ----
create table if not exists receipts_app.products (
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references receipts_app.merchants(id) on delete cascade,
  canonical_name text not null,
  normalized_name text generated always as
    (lower(regexp_replace(canonical_name, '[^a-zA-Z0-9]+', '', 'g'))) stored,
  product_url text,
  image_url text,
  brand text,
  category text,
  description text,
  metadata jsonb not null default '{}'::jsonb,
  first_seen_on date,
  last_seen_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists products_merchant_url_key
  on receipts_app.products (merchant_id, product_url)
  where product_url is not null;
create index if not exists products_merchant_normname_idx
  on receipts_app.products (merchant_id, normalized_name);

drop trigger if exists products_set_updated_at on receipts_app.products;
create trigger products_set_updated_at
  before update on receipts_app.products
  for each row execute function receipts_app.set_updated_at();

-- ---- product_variants ----
create table if not exists receipts_app.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references receipts_app.products(id) on delete cascade,
  size text,
  color text,
  material text,
  sku text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Dedup variants by the full (size, color, material, sku) tuple. Nulls are
-- treated as equal via coalesce so we don't create duplicate "no variant" rows.
create unique index if not exists product_variants_dedup_key
  on receipts_app.product_variants (
    product_id,
    coalesce(size, ''),
    coalesce(color, ''),
    coalesce(material, ''),
    coalesce(sku, '')
  );

drop trigger if exists product_variants_set_updated_at on receipts_app.product_variants;
create trigger product_variants_set_updated_at
  before update on receipts_app.product_variants
  for each row execute function receipts_app.set_updated_at();

-- ---- receipts ----
create table if not exists receipts_app.receipts (
  id uuid primary key default gen_random_uuid(),
  owner_email text not null,
  gmail_message_id text not null,
  merchant_id uuid references receipts_app.merchants(id) on delete set null,
  source text,
  order_ref text,
  subtotal numeric,
  tax numeric,
  shipping numeric,
  discount numeric,
  total numeric,
  currency text default 'USD',
  purchase_date date,
  return_by date,
  return_window_days int,
  policy_source text,
  policy_text_from_email text,
  store_policy_url text,
  restrictions text[] default '{}',
  raw_subject text,
  added_on date not null default current_date,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_email, gmail_message_id)
);

create index if not exists receipts_owner_return_by_idx
  on receipts_app.receipts (owner_email, return_by);
create index if not exists receipts_merchant_idx
  on receipts_app.receipts (merchant_id);

drop trigger if exists receipts_set_updated_at on receipts_app.receipts;
create trigger receipts_set_updated_at
  before update on receipts_app.receipts
  for each row execute function receipts_app.set_updated_at();

-- ---- receipt_items ----
create table if not exists receipts_app.receipt_items (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references receipts_app.receipts(id) on delete cascade,
  product_variant_id uuid references receipts_app.product_variants(id) on delete set null,
  name_at_purchase text,
  qty int not null default 1,
  price_at_purchase numeric,
  url_at_purchase text,
  position int not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists receipt_items_receipt_idx
  on receipts_app.receipt_items (receipt_id);
create index if not exists receipt_items_variant_idx
  on receipts_app.receipt_items (product_variant_id)
  where product_variant_id is not null;

-- ---- returns ----
create table if not exists receipts_app.returns (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references receipts_app.receipts(id) on delete cascade,
  receipt_item_id uuid references receipts_app.receipt_items(id) on delete set null,
  status text not null default 'initiated'
    check (status in ('initiated', 'shipped', 'received', 'refunded', 'rejected', 'cancelled')),
  initiated_on date,
  shipped_on date,
  received_on date,
  refunded_on date,
  refund_amount numeric,
  refund_shipping_fee numeric,
  restocking_fee numeric,
  gmail_message_id text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists returns_receipt_idx
  on receipts_app.returns (receipt_id);
create index if not exists returns_status_idx
  on receipts_app.returns (status);

drop trigger if exists returns_set_updated_at on receipts_app.returns;
create trigger returns_set_updated_at
  before update on receipts_app.returns
  for each row execute function receipts_app.set_updated_at();

-- ---- watcher_state ----
create table if not exists receipts_app.watcher_state (
  owner_email text primary key,
  last_run timestamptz not null default 'epoch'::timestamptz,
  updated_at timestamptz not null default now()
);

drop trigger if exists watcher_state_set_updated_at on receipts_app.watcher_state;
create trigger watcher_state_set_updated_at
  before update on receipts_app.watcher_state
  for each row execute function receipts_app.set_updated_at();

-- ---- views ----

-- Latest return event per receipt — convenience for page rendering.
create or replace view receipts_app.v_latest_return as
select distinct on (receipt_id)
  receipt_id,
  id as return_id,
  status,
  initiated_on,
  shipped_on,
  received_on,
  refunded_on,
  refund_amount
from receipts_app.returns
order by receipt_id, created_at desc;

-- Receipts enriched with merchant + effective return status (active / returned /
-- expired / no_deadline) so the UI can filter without duplicating logic.
create or replace view receipts_app.v_receipts_enriched as
select
  r.id,
  r.owner_email,
  r.gmail_message_id,
  r.merchant_id,
  m.name as merchant_name,
  m.website as merchant_website,
  m.logo_url as merchant_logo_url,
  r.source,
  r.order_ref,
  r.subtotal,
  r.tax,
  r.shipping,
  r.discount,
  r.total,
  r.currency,
  r.purchase_date,
  r.return_by,
  r.return_window_days,
  r.policy_source,
  r.policy_text_from_email,
  r.store_policy_url,
  r.restrictions,
  r.raw_subject,
  r.added_on,
  r.created_at,
  lr.status as latest_return_status,
  lr.refunded_on as latest_refunded_on,
  case
    when lr.status in ('refunded', 'received') then 'returned'
    when r.return_by is null then 'no_deadline'
    when r.return_by < current_date then 'expired'
    else 'active'
  end as effective_status,
  case
    when r.return_by is null then null
    when r.return_by < current_date then 0
    else (r.return_by - current_date)
  end as days_to_return_deadline
from receipts_app.receipts r
left join receipts_app.merchants m on m.id = r.merchant_id
left join receipts_app.v_latest_return lr on lr.receipt_id = r.id;

-- Monthly spend rollup across owners / merchants.
create or replace view receipts_app.v_monthly_spend as
select
  r.owner_email,
  date_trunc('month', r.purchase_date)::date as month,
  m.name as merchant_name,
  count(*) as receipt_count,
  sum(coalesce(r.total, 0)) as total_spend,
  sum(coalesce(r.tax, 0)) as total_tax,
  sum(coalesce(r.shipping, 0)) as total_shipping
from receipts_app.receipts r
left join receipts_app.merchants m on m.id = r.merchant_id
where r.purchase_date is not null
group by r.owner_email, date_trunc('month', r.purchase_date), m.name
order by month desc nulls last, total_spend desc nulls last;

-- Per-product purchase frequency.
create or replace view receipts_app.v_product_purchases as
select
  p.id as product_id,
  p.merchant_id,
  m.name as merchant_name,
  p.canonical_name,
  p.product_url,
  p.image_url,
  count(distinct ri.receipt_id) as times_bought,
  sum(coalesce(ri.qty, 1)) as total_qty,
  sum(coalesce(ri.price_at_purchase * ri.qty, ri.price_at_purchase, 0)) as total_spent,
  min(r.purchase_date) as first_bought_on,
  max(r.purchase_date) as last_bought_on
from receipts_app.products p
join receipts_app.merchants m on m.id = p.merchant_id
left join receipts_app.product_variants v on v.product_id = p.id
left join receipts_app.receipt_items ri on ri.product_variant_id = v.id
left join receipts_app.receipts r on r.id = ri.receipt_id
group by p.id, p.merchant_id, m.name, p.canonical_name, p.product_url, p.image_url;

-- ---- RLS (lock out anon/authenticated; service_role and direct PG bypass) ----
alter table receipts_app.merchants enable row level security;
alter table receipts_app.products enable row level security;
alter table receipts_app.product_variants enable row level security;
alter table receipts_app.receipts enable row level security;
alter table receipts_app.receipt_items enable row level security;
alter table receipts_app.returns enable row level security;
alter table receipts_app.watcher_state enable row level security;

-- Expose schema to PostgREST so the service_role key can reach it over HTTPS.
-- (Harmless when service_role is the only grantee; the schema is still locked
-- for anon/authenticated by RLS above.)
grant usage on schema receipts_app to postgres, service_role;
grant all on all tables in schema receipts_app to postgres, service_role;
grant all on all sequences in schema receipts_app to postgres, service_role;
grant all on all functions in schema receipts_app to postgres, service_role;

alter default privileges in schema receipts_app
  grant all on tables to postgres, service_role;
alter default privileges in schema receipts_app
  grant all on sequences to postgres, service_role;
alter default privileges in schema receipts_app
  grant all on functions to postgres, service_role;

-- ---- backfill from public.receipts / public.receipt_items ----
-- One-shot: synthesize merchants from distinct names, recreate receipts and
-- items, preserving ids where possible so any existing links survive.
do $$
declare r record; mid uuid; pid uuid; vid uuid;
begin
  if to_regclass('public.receipts') is null then
    return;
  end if;

  for r in select * from public.receipts loop
    -- ensure merchant
    insert into receipts_app.merchants (name)
    values (coalesce(r.merchant, 'Unknown'))
    on conflict (normalized_name) do update set name = excluded.name
    returning id into mid;

    -- insert receipt
    insert into receipts_app.receipts (
      id, owner_email, gmail_message_id, merchant_id, source, order_ref,
      total, currency, purchase_date, return_by, return_window_days,
      policy_source, policy_text_from_email, store_policy_url, restrictions,
      raw_subject, added_on
    ) values (
      r.id, r.owner_email, r.gmail_message_id, mid, r.source, r.order_ref,
      r.total, r.currency, r.purchase_date, r.return_by, r.return_window_days,
      r.policy_source, r.policy_text_from_email, r.store_policy_url, r.restrictions,
      r.raw_subject, r.added_on
    ) on conflict (owner_email, gmail_message_id) do nothing;

    -- if the receipt already had an old "returned" status, log it as a return row
    if r.return_status = 'returned' then
      insert into receipts_app.returns (receipt_id, status, refunded_on)
      values (r.id, 'refunded', r.returned_on)
      on conflict do nothing;
    end if;
  end loop;

  -- items: create a product per (merchant, normalized item name) and a default
  -- variant, then link.
  for r in
    select ri.*, rc.merchant_id, rc.owner_email
      from public.receipt_items ri
      join receipts_app.receipts rc on rc.id = ri.receipt_id
  loop
    insert into receipts_app.products (merchant_id, canonical_name, product_url, first_seen_on)
    values (r.merchant_id, coalesce(r.name, 'Item'), r.url, current_date)
    on conflict do nothing;

    select id into pid
      from receipts_app.products
     where merchant_id = r.merchant_id
       and normalized_name = lower(regexp_replace(coalesce(r.name, 'Item'), '[^a-zA-Z0-9]+', '', 'g'))
     limit 1;

    insert into receipts_app.product_variants (product_id)
    values (pid)
    on conflict do nothing;

    select id into vid
      from receipts_app.product_variants
     where product_id = pid
       and coalesce(size, '') = ''
       and coalesce(color, '') = ''
     limit 1;

    insert into receipts_app.receipt_items (
      receipt_id, product_variant_id, name_at_purchase, qty, price_at_purchase, url_at_purchase, position
    ) values (
      r.receipt_id, vid, r.name, r.qty, r.price, r.url, r.position
    );
  end loop;

  -- copy watcher state
  if to_regclass('public.receipt_watcher_state') is not null then
    insert into receipts_app.watcher_state (owner_email, last_run)
      select owner_email, last_run from public.receipt_watcher_state
    on conflict (owner_email) do update set last_run = excluded.last_run;
  end if;
end $$;
