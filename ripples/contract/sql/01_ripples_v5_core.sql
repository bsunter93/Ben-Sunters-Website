-- Knock-On v5 / W1: migration ripples_v5_core
-- Schema ripples (NOT exposed to PostgREST), W1 tables, internal helpers, storage bucket.
create schema if not exists ripples;
revoke all on schema ripples from public, anon, authenticated;
grant usage on schema ripples to service_role;

create table if not exists ripples.config (
  key   text primary key,
  value jsonb not null
);

create table if not exists ripples.puzzles (
  n              int primary key,
  kind           text not null check (kind in ('live','practice','fixture')),
  puzzle_date    date not null,
  data_date      date,
  from_date      date,
  status         text not null check (status in ('built','published','vetoed','delayed','fixture')),
  payload        jsonb,
  reveal         jsonb,
  board          jsonb,
  answers        jsonb,
  final_multiple numeric,
  chain_id       bigint,
  built_at       timestamptz default now(),
  published_at   timestamptz,
  -- n-range guards: live > 0, practice < 0, fixture = 0 (and only the fixture has status 'fixture')
  constraint puzzles_n_kind check (
       (kind = 'live'     and n > 0)
    or (kind = 'practice' and n < 0)
    or (kind = 'fixture'  and n = 0)),
  constraint puzzles_fixture_status check ((kind = 'fixture') = (status = 'fixture'))
);
create index if not exists puzzles_kind_n on ripples.puzzles (kind, n desc);

create table if not exists ripples.callit (
  n               int not null,
  qid             text not null,
  title           text not null,
  emoji           text,
  category        text,
  baseline_median numeric,
  model_p         numeric check (model_p is null or (model_p >= 0 and model_p <= 1)),
  window_start    date not null,
  window_end      date not null,
  outcome         text not null default 'pending' check (outcome in ('pending','hit','miss')),
  max_z           numeric,
  resolved_at     timestamptz,
  primary key (n, qid)
);

create table if not exists ripples.plays (
  n           int not null,
  client_hash text not null,
  ip_hash     text,
  picks       jsonb not null,
  codes       smallint[] not null,
  score       smallint not null,
  max_score   smallint not null,
  mag_guess   numeric,
  mag_err     numeric,          -- |log10(guess/actual)|
  country     text,
  created_at  timestamptz not null default now(),
  unique (n, client_hash)
);
create index if not exists plays_created on ripples.plays (created_at);

create table if not exists ripples.calls (
  n           int not null,
  client_hash text not null,
  qid         text not null,
  created_at  timestamptz not null default now(),
  unique (n, client_hash)
);

create table if not exists ripples.waitlist (
  id         bigserial primary key,
  email_norm text not null unique,
  role       text,
  price      text,
  topics     text[],
  source     text,
  ip_hash    text,
  created_at timestamptz not null default now(),
  confirmed  boolean not null default false
);

create table if not exists ripples.rate_limits (
  bucket text not null,
  day    date not null,
  count  int  not null default 0,
  primary key (bucket, day)
);

create table if not exists ripples.salts (
  day     date primary key,
  salt    text not null,   -- client salt (client_hash for puzzles dated `day`); deleted after ~9 days
  ip_salt text             -- IP salt for UTC day `day`; nulled once the day is over (ripples._purge_salts)
);
alter table ripples.salts add column if not exists ip_salt text;

create table if not exists ripples.copy (
  n          int  not null,
  i          int,
  kind       text not null check (kind in ('headline','caption','social','brief_intro')),
  text       text not null,
  source     text not null check (source in ('ai','template','wikipedia')),
  created_at timestamptz not null default now()
);
create unique index if not exists copy_pk on ripples.copy (n, coalesce(i, 0), kind);

create table if not exists ripples.ledger (
  n            int primary key,
  day          date not null,
  payload_hash text not null,
  prev_hash    text not null,
  chain_hash   text not null,
  created_at   timestamptz not null default now(),
  seq          bigint generated always as identity   -- write order; the chain follows seq, not n
);
alter table ripples.ledger add column if not exists seq bigint generated always as identity;
create unique index if not exists ledger_seq on ripples.ledger (seq);

-- RLS on, no policies; nothing for anon/authenticated/public
alter table ripples.config      enable row level security;
alter table ripples.puzzles     enable row level security;
alter table ripples.callit      enable row level security;
alter table ripples.plays       enable row level security;
alter table ripples.calls       enable row level security;
alter table ripples.waitlist    enable row level security;
alter table ripples.rate_limits enable row level security;
alter table ripples.salts       enable row level security;
alter table ripples.copy        enable row level security;
alter table ripples.ledger      enable row level security;
revoke all on all tables    in schema ripples from anon, authenticated, public;
revoke all on all sequences in schema ripples from anon, authenticated, public;

insert into ripples.config (key, value) values
  ('epoch',          '"2026-09-25"'),
  ('min_players',    '30'),
  ('method_version', '"5.0"'),
  ('wm_daily_cap',   '6000')
on conflict (key) do nothing;

-- ---------- internal helpers (schema ripples, not callable by anon: no schema usage) ----------
create or replace function ripples._cfg(p_key text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select value from ripples.config where key = p_key
$$;

create or replace function ripples._epoch() returns date
language sql stable security definer set search_path = '' as $$
  select coalesce((select value #>> '{}' from ripples.config where key = 'epoch'), '2026-09-25')::date
$$;

-- The live puzzle date that is "current" now: puzzle #N goes live 07:30 UTC on its date.
create or replace function ripples._current_date() returns date
language sql stable security definer set search_path = '' as $$
  select ((now() at time zone 'utc') - interval '7 hours 30 minutes')::date
$$;

create or replace function ripples._current_n() returns int
language sql stable security definer set search_path = '' as $$
  select (ripples._current_date() - ripples._epoch())::int
$$;

-- Daily salt, created lazily (volatile: may insert). Used for client_hash (salted by puzzle date).
-- Creating a new day's row also runs the salt retention purge.
create or replace function ripples._salt(p_day date default null) returns text
language plpgsql volatile security definer set search_path = '' as $$
declare d date := coalesce(p_day, (now() at time zone 'utc')::date); s text;
begin
  select salt into s from ripples.salts where day = d;
  if s is null then
    insert into ripples.salts(day, salt)
    values (d, encode(extensions.gen_random_bytes(16), 'hex'))
    on conflict (day) do nothing;
    perform ripples._purge_salts();
    select salt into s from ripples.salts where day = d;
  end if;
  return s;
end $$;

-- Salt retention (SPEC 12.12): the IP salt lives for its UTC day only; the puzzle-date (client) salt
-- is kept while plays for that puzzle can still arrive (current-7 .. current, plus a day of margin).
create or replace function ripples._purge_salts() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare today date := (now() at time zone 'utc')::date;
begin
  update ripples.salts set ip_salt = null where ip_salt is not null and day < today;
  delete from ripples.salts where day < today - 9;
end $$;

-- sha256(today's IP salt || '|' || client IP). The IP salt is separate from the client salt and is
-- nulled by _purge_salts() once its UTC day is over, so stored ip_hash values cannot be reversed later.
create or replace function ripples._ip_hash() returns text
language plpgsql volatile security definer set search_path = '' as $$
declare d date := (now() at time zone 'utc')::date; s text;
begin
  select ip_salt into s from ripples.salts where day = d;
  if s is null then
    insert into ripples.salts(day, salt, ip_salt)
    values (d, encode(extensions.gen_random_bytes(16), 'hex'), encode(extensions.gen_random_bytes(16), 'hex'))
    on conflict (day) do update set ip_salt = coalesce(ripples.salts.ip_salt, excluded.ip_salt);
    perform ripples._purge_salts();
    select ip_salt into s from ripples.salts where day = d;
  end if;
  return encode(extensions.digest(s || '|' || ripples._ip(), 'sha256'), 'hex');
end $$;

-- client_hash only (salted with the puzzle date). IP hashes use ripples._ip_hash().
create or replace function ripples._hash(p text, p_day date default null) returns text
language sql volatile security definer set search_path = '' as $$
  select encode(extensions.digest(ripples._salt(p_day) || '|' || coalesce(p, ''), 'sha256'), 'hex')
$$;

create or replace function ripples._ip() returns text
language plpgsql stable security definer set search_path = '' as $$
declare h json; ip text;
begin
  begin
    h := nullif(current_setting('request.headers', true), '')::json;
  exception when others then h := null;
  end;
  ip := nullif(trim(h->>'cf-connecting-ip'), '');
  if ip is null then
    ip := nullif(trim(split_part(coalesce(h->>'x-forwarded-for', ''), ',', 1)), '');
  end if;
  return coalesce(ip, 'none');
end $$;

create or replace function ripples._country() returns text
language plpgsql stable security definer set search_path = '' as $$
declare h json; c text;
begin
  begin
    h := nullif(current_setting('request.headers', true), '')::json;
  exception when others then h := null;
  end;
  c := upper(nullif(trim(h->>'cf-ipcountry'), ''));
  if c is null or c !~ '^[A-Z]{2}$' then return null; end if;
  return c;
end $$;

-- Increment the per-day counter for bucket; true while count <= limit.
create or replace function ripples._rate(p_bucket text, p_limit int) returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare c int;
begin
  insert into ripples.rate_limits(bucket, day, count)
  values (p_bucket, (now() at time zone 'utc')::date, 1)
  on conflict (bucket, day) do update set count = ripples.rate_limits.count + 1
  returning count into c;
  return c <= p_limit;
end $$;

-- Storage bucket (public)
insert into storage.buckets (id, name, public) values ('ripples', 'ripples', true)
on conflict (id) do nothing;

revoke execute on all functions in schema ripples from public, anon, authenticated;
notify pgrst, 'reload schema';
