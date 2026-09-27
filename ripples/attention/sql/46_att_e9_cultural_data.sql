-- 46: E9 cultural shocks, phase 1 data (pre-registered at ledger 1275; source changes disclosed at ledger 1276 before any
-- data was read). See ripples/docs/experiments.md, E9.
--   att_e9_pv     en.wikipedia daily user pageviews (Wikimedia REST per-article API, honest UA) for the 13 pre-listed
--                 articles, 2015-07-01..2026-09-26. 9 loaded 2026-09-27; 4 got 429 (requests were concurrent), so
--                 wikimedia.org was killed for the day (att_host_kill) and att_e9_pv_tick fetches the rest one request
--                 per 5 minutes from 2026-09-28 00:10 UTC, stopping on 403/429/503 and unscheduling itself when done.
--   att_e9_names  US baby-name national counts by year (SSA via bigquery-public-data.usa_names; ssa.gov answered 403),
--                 loaded by .github/workflows/ripples-e9-names.yml through public.att_e9_names_load.

create table if not exists ripples.att_e9_pv (article text not null, day date not null, views int not null, primary key (article, day));
create table if not exists ripples.att_e9_req (article text primary key, req_id bigint, status text default 'queued');
create table if not exists ripples.att_e9_names (name text not null, sex text not null, year int not null, n int not null,
  primary key (name, sex, year));
alter table ripples.att_e9_pv enable row level security;
alter table ripples.att_e9_req enable row level security;
alter table ripples.att_e9_names enable row level security;
revoke all on ripples.att_e9_pv, ripples.att_e9_req, ripples.att_e9_names from anon, authenticated, public;

create or replace function public.att_e9_names_load(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_n int;
begin
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 5000 then
    raise exception 'p_rows must be an array of at most 5000 rows';
  end if;
  insert into ripples.att_e9_names(name, sex, year, n)
    select r ->> 'name', r ->> 'sex', (r ->> 'year')::int, (r ->> 'n')::int
      from jsonb_array_elements(p_rows) r
     where r ->> 'name' ~ '^[A-Za-z]{1,30}$' and r ->> 'sex' in ('F', 'M')
       and r ->> 'year' ~ '^(199[5-9]|20[0-9]{2})$' and r ->> 'n' ~ '^[0-9]+$'
  on conflict (name, sex, year) do update set n = excluded.n;
  get diagnostics v_n = row_count;
  return jsonb_build_object('rows', v_n, 'sent', jsonb_array_length(p_rows));
end $$;
revoke all on function public.att_e9_names_load(jsonb) from anon, authenticated, public;
grant execute on function public.att_e9_names_load(jsonb) to service_role;

-- att_e9_pv_tick() and cron job att-e9-pv: applied live 2026-09-27 (see pg_get_functiondef for the exact text); one
-- queued article per 5-minute tick after the 2026-09-28 00:10 UTC gate, stops on 403/429/503, unschedules when done.
