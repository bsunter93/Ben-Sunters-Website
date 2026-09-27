-- 15_att_charts (W7 att-charts, 2026-09-25, applied as migration att_charts_collector)
-- Support objects for the att-charts edge function (apple, steamspy, github, hf, anilist, openlibrary, tranco, npm,
-- pypi, backfill). Everything is service_role only: SECURITY DEFINER, search_path '', revoked from PUBLIC/anon/authenticated.
--
-- 1) att_config 'charts': per-mode settings with free/pro list sizes (the profile switch is att_config.profile, set by
--    ripples.att_set_profile). Free tier keeps the top 50 of each chart; pro keeps the full 100.
--    npm/pypi 'reference' = the builder-channel reference panel (normalisers for the share transform, collected like
--    '__total__'; no topic link).
-- 2) meta_allow gains 'kind', 'feed', 'score', 'n_geos', 'list' (candidate meta: new entry / rank jump / top).
-- 3) ripples.att_charts_prev(source, day, metrics, lookback): the latest earlier snapshot per (metric, geo) within the
--    lookback, used for new-entry / rank-jump discovery and for star deltas.
-- 4) ripples.att_charts_series_info(source, metric, keys): days of history per key (decides whether a key still needs
--    its 400-day backfill).

insert into ripples.att_config(key, value) values ('charts', jsonb_build_object(
  'apple', jsonb_build_object(
     'geos', jsonb_build_array('us','gb','in','br','jp'),
     'feeds', jsonb_build_array(
        jsonb_build_object('code','apps-free', 'path','apps/top-free',     'type','apps'),
        jsonb_build_object('code','apps-paid', 'path','apps/top-paid',     'type','apps'),
        jsonb_build_object('code','songs',     'path','music/most-played', 'type','songs'),
        jsonb_build_object('code','podcasts',  'path','podcasts/top',      'type','podcasts'),
        jsonb_build_object('code','books-free','path','books/top-free',    'type','books')),
     'limit', jsonb_build_object('free', 50, 'pro', 100)),
  'steamspy', jsonb_build_object('limit', jsonb_build_object('free', 100, 'pro', 100)),
  'hf', jsonb_build_object('lists', jsonb_build_array('models','spaces','datasets'),
                           'limit', jsonb_build_object('free', 50, 'pro', 100)),
  'github', jsonb_build_object('window_days', 7, 'limit', jsonb_build_object('free', 50, 'pro', 100),
                               'max_backfill_stars', 2000),
  'anilist', jsonb_build_object('limit', jsonb_build_object('free', 50, 'pro', 50), 'trend_batch', 8,
                                'backfill_pages', 8),
  'openlibrary', jsonb_build_object('limit', jsonb_build_object('free', 50, 'pro', 100)),
  'tranco', jsonb_build_object('top', 1000, 'jump_min', 20, 'jump_frac', 0.25, 'max_movers', 100),
  'discovery', jsonb_build_object('jump_min', 20, 'top_k', 10, 'star_farm_ratio', 50),
  'npm', jsonb_build_object('days', 7, 'backfill_days', 400, 'bulk', 128,
     'reference', jsonb_build_array('react','vue','svelte','next','typescript','express','axios','openai',
                                    '@anthropic-ai/sdk','langchain','ollama','@modelcontextprotocol/sdk')),
  'pypi', jsonb_build_object('days', 7,
     'reference', jsonb_build_array('openai','anthropic','torch','transformers','numpy','requests','fastapi','langchain'))
))
on conflict (key) do update set value = excluded.value;

update ripples.att_config
   set value = (select jsonb_agg(distinct x) from jsonb_array_elements(value || '["kind","feed","score","n_geos","list"]'::jsonb) x)
 where key = 'meta_allow';

create or replace function ripples.att_charts_prev(p_source text, p_day date, p_metrics text[] default null,
                                                   p_lookback int default 7)
returns table(metric text, geo text, key text, day date, value double precision, aux real)
language sql stable security definer set search_path = '' as $$
  with s as (
    select s.series_id, s.metric, s.geo, s.key from ripples.att_series s
    where s.source = p_source and (p_metrics is null or s.metric = any(p_metrics))),
  d as (
    select s.metric, s.geo, max(o.day) as md
    from s join ripples.attention_obs o on o.series_id = s.series_id
    where o.day < p_day and o.day >= p_day - greatest(coalesce(p_lookback, 7), 1)
    group by s.metric, s.geo)
  select s.metric, s.geo, s.key, o.day, o.value, o.aux
  from s join d on d.metric = s.metric and d.geo = s.geo
  join ripples.attention_obs o on o.series_id = s.series_id and o.day = d.md
$$;

create or replace function ripples.att_charts_series_info(p_source text, p_metric text, p_keys text[])
returns table(key text, geo text, n_days int, first_day date, last_day date)
language sql stable security definer set search_path = '' as $$
  select s.key, s.geo, count(o.day)::int, min(o.day), max(o.day)
  from ripples.att_series s left join ripples.attention_obs o on o.series_id = s.series_id
  where s.source = p_source and s.metric = coalesce(p_metric, 'n') and s.key = any(coalesce(p_keys, '{}'))
  group by s.key, s.geo
$$;

-- public wrappers (the ripples schema is not exposed to PostgREST); service_role only
create or replace function public.att_charts_prev(p_source text, p_day date, p_metrics text[] default null,
                                                  p_lookback int default 7)
returns table(metric text, geo text, key text, day date, value double precision, aux real)
language sql stable security definer set search_path = '' as $$
  select * from ripples.att_charts_prev(p_source, p_day, p_metrics, p_lookback) $$;
create or replace function public.att_charts_series_info(p_source text, p_metric text, p_keys text[])
returns table(key text, geo text, n_days int, first_day date, last_day date)
language sql stable security definer set search_path = '' as $$
  select * from ripples.att_charts_series_info(p_source, p_metric, p_keys) $$;

do $$
declare f text;
begin
  foreach f in array array[
    'ripples.att_charts_prev(text, date, text[], int)', 'ripples.att_charts_series_info(text, text, text[])',
    'public.att_charts_prev(text, date, text[], int)', 'public.att_charts_series_info(text, text, text[])'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
