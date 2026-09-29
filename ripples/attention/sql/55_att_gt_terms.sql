-- Google Trends archive (BigQuery public dataset google_trends keeps only ~30 days of refresh dates, so we keep our own
-- copy, collected daily by ripples/tools/bq/gt_archive.py). Aggregates of public trending-search lists only.
-- scope 'us': the 210 US DMA lists aggregated to national (n_regions = DMAs listing the term); geo = 'US'.
-- scope 'intl': per country (geo = ISO country code), regions aggregated.
create table if not exists ripples.att_gt_terms (
  refresh_date date not null,
  scope text not null check (scope in ('us', 'intl')),
  geo text not null,
  kind text not null check (kind in ('top', 'rising')),
  term text not null,
  week date not null,
  n_regions int not null,
  best_rank int,
  mean_score real,
  max_gain int,
  primary key (refresh_date, scope, geo, kind, term, week)
);
alter table ripples.att_gt_terms enable row level security;
create index if not exists att_gt_terms_term on ripples.att_gt_terms (term, week);

create or replace function public.att_gt_load(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_n int;
begin
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 5000 then raise exception 'bad p_rows'; end if;
  insert into ripples.att_gt_terms(refresh_date, scope, geo, kind, term, week, n_regions, best_rank, mean_score, max_gain)
    select (r->>'rd')::date, r->>'scope', r->>'geo', r->>'kind', left(r->>'term', 300), (r->>'week')::date,
           (r->>'n')::int, nullif(r->>'rank', '')::int, nullif(r->>'score', '')::real, nullif(r->>'gain', '')::int
      from jsonb_array_elements(p_rows) r
     where r->>'rd' ~ '^\d{4}-\d{2}-\d{2}$' and r->>'week' ~ '^\d{4}-\d{2}-\d{2}$' and r->>'n' ~ '^\d+$'
  on conflict (refresh_date, scope, geo, kind, term, week) do update
    set n_regions = excluded.n_regions, best_rank = excluded.best_rank, mean_score = excluded.mean_score,
        max_gain = excluded.max_gain;
  get diagnostics v_n = row_count;
  return jsonb_build_object('rows', v_n);
end $$;
revoke all on function public.att_gt_load(jsonb) from public, anon, authenticated;
grant execute on function public.att_gt_load(jsonb) to service_role;

create or replace function public.att_gt_have()
returns table(scope text, refresh_date date) language sql security definer set search_path to '' as $$
  select distinct t.scope, t.refresh_date from ripples.att_gt_terms t;
$$;
revoke all on function public.att_gt_have() from public, anon, authenticated;
grant execute on function public.att_gt_have() to service_role;
