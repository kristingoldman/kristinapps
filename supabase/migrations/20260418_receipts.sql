-- Receipt tracker tables for albastyle.com/pages/receipts
-- Data source: receipt_watcher.py scans Gmail, extracts receipts via Claude CLI.
-- Access: service_role only. Machine-local Python script uses direct PG connection;
-- Cloudflare Pages Function at /api/receipts uses the Supabase service_role key.
-- RLS is enabled and no policies are granted to anon/authenticated — the anon key
-- cannot read these tables, which is important because it ships to browsers.

create table if not exists public.receipts (
  id uuid primary key default gen_random_uuid(),
  owner_email text not null,
  gmail_message_id text not null,
  source text,
  merchant text,
  order_ref text,
  total numeric,
  currency text default 'USD',
  purchase_date date,
  return_by date,
  return_window_days int,
  policy_source text,
  policy_text_from_email text,
  store_policy_url text,
  restrictions text[] default '{}',
  return_status text not null default 'active',
  returned_on date,
  raw_subject text,
  added_on date not null default current_date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_email, gmail_message_id)
);

create index if not exists receipts_owner_return_by_idx
  on public.receipts (owner_email, return_by);
create index if not exists receipts_owner_status_idx
  on public.receipts (owner_email, return_status);

create table if not exists public.receipt_items (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null references public.receipts(id) on delete cascade,
  name text,
  qty int default 1,
  price numeric,
  url text,
  position int not null default 0
);

create index if not exists receipt_items_receipt_idx
  on public.receipt_items (receipt_id);

create table if not exists public.receipt_watcher_state (
  owner_email text primary key,
  last_run timestamptz not null default 'epoch'::timestamptz,
  updated_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists receipts_set_updated_at on public.receipts;
create trigger receipts_set_updated_at
  before update on public.receipts
  for each row execute function public.set_updated_at();

drop trigger if exists receipt_watcher_state_set_updated_at on public.receipt_watcher_state;
create trigger receipt_watcher_state_set_updated_at
  before update on public.receipt_watcher_state
  for each row execute function public.set_updated_at();

alter table public.receipts enable row level security;
alter table public.receipt_items enable row level security;
alter table public.receipt_watcher_state enable row level security;
