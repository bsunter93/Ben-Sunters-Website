-- Migration: attention_stack_core_fixes2  (W7 att-core, 2026-09-25, second verification round)
-- * wikidata.api source row: every politeFetch now needs a registered source (Wikidata wbgetentities, DEMARCATION §7.1)
-- * att_budget_refund: politeFetch charges the per-day budget itself, in chunks; unspent units are given back
-- * att_config.contact_gate: Wikimedia requests wait until the UA contact page answers 2xx (§7.1 "UA that includes a contact")
-- * _att_ident_like: att_ingest keys + edge keys + candidate labels screened for handles/DIDs/e-mails/URLs (bare-domain
--   Bluesky handles included for social sources)
-- * att_skip_title: localized date pages, necrology pages, zh/ja list pages, evergreen reference page; maintain demotes
-- * _att_alias_ok: no single-word aliases for multi-word topics, none of 4 chars or fewer (e.g. 'cookie' for HTTP cookie)

-- ---------- registry source for Wikidata lookups ----------
insert into ripples.att_sources(source, family, channel, grade, value_kind, grain, enabled, reason, tier, attribution,
                                license_note, per_run_cap, per_day_cap, spacing_ms, budget_bucket, hosts, robots_required)
values ('wikidata.api', 'wikimedia', 'reading', 'green', 'count', 'day', true,
        'Registry lookups only (wbgetentities, labels/aliases/identifier properties); no observations. DEMARCATION §7.1: '
        || 'Action API under the bot policy, maxlag=5, serial >= 1.1 s; shared bucket wikidata', 'ship',
        'Wikidata (CC0)', 'CC0', 150, null, 1100, 'wikidata', array['www.wikidata.org'], false)
on conflict (source) do update set enabled = excluded.enabled, per_run_cap = excluded.per_run_cap,
  spacing_ms = excluded.spacing_ms, budget_bucket = excluded.budget_bucket, hosts = excluded.hosts,
  robots_required = excluded.robots_required, reason = excluded.reason;

-- ---------- budget refund ----------
create or replace function ripples.att_budget_refund(p_bucket text, p_n int) returns int
language plpgsql security definer set search_path = '' as $$
declare b record; v int; v_day date := (now() at time zone 'utc')::date;
begin
  if p_n is null or p_n <= 0 or p_bucket is null then return 0; end if;
  select * into b from ripples._att_bucket(p_bucket);
  update ripples.att_budget set used = greatest(0, used - p_n) where bucket = b.bucket and day = v_day and used < cap
  returning used into v;               -- a bucket spent by a kill (used = cap) stays spent
  return coalesce(p_n, 0) * (case when v is null then 0 else 1 end);
end $$;
create or replace function public.att_budget_refund(p_bucket text, p_n int) returns int
language sql security definer set search_path = '' as $$ select ripples.att_budget_refund(p_bucket, p_n) $$;

-- ---------- UA contact gate ----------
insert into ripples.att_config(key, value) values
  ('contact_gate', '{"enabled": true, "url": "https://bensunter.com/ripples/methods/", "scope": "wikimedia", "ttl_ok_h": 24, "ttl_fail_h": 1}'::jsonb)
on conflict (key) do update set value = excluded.value;

-- ---------- identifier screen (hard rule 4) ----------
-- true = looks like a personal identifier: URL, DID, e-mail / fediverse handle (user@host), *.bsky.social|app,
-- a leading-@ handle (except Wikipedia titles such as '@'), and with p_strict for bsky.*/masto.* labels: bare domains
create or replace function ripples._att_ident_like(p text, p_source text, p_strict boolean default false) returns boolean
language sql immutable security definer set search_path = '' as $$
  select p is not null and (
       p ~* '(https?://|\mdid:(plc|web):|\mwww\.[a-z0-9-]+\.)'
    or p ~* '[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)+'
    or p ~* '\.bsky\.(social|app)$'
    or (p ~ '^@[[:alnum:]_]' and coalesce(p_source, '') !~ '^wiki\.')
    or (p_strict and coalesce(p_source, '') ~ '^(bsky|masto)\.'
        and p !~ '\s' and (p ~* '^[a-z0-9-]+(\.[a-z0-9-]+){2,}$'
             or p ~* '^[a-z0-9-]+\.(com|net|org|io|dev|me|xyz|social|app|co|ai|blog|online|site|page|lol|art|us|uk|ca|de|fr|jp|eu|info|tv|fm|pub|world|zone|cafe|club|space|tech)$')))
$$;

-- ---------- aliases: generic single words are not used for strict matching ----------
create or replace function ripples._att_alias_ok(p_term text, p_alias text) returns boolean
language sql immutable security definer set search_path = '' as $$
  select p_alias is not null and char_length(p_alias) > 4
     and (coalesce(p_term, '') !~ ' ' or p_alias ~ ' ' or p_alias ~ '[0-9]')
$$;

create or replace function ripples.att_ingest(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_new int := 0; v_daily int := 0; v_hourly int := 0; v_rej jsonb; v_cap numeric;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    return jsonb_build_object('series_new', 0, 'rows', 0,
      'rejected', jsonb_build_array(jsonb_build_object('i', -1, 'reason', 'p_rows must be a JSON array')));
  end if;
  v_cap := coalesce((ripples._att_cfg('db_cap_mb'))::text::numeric, 400);
  if pg_database_size(current_database()) > (v_cap - 10) * 1048576 then
    return jsonb_build_object('series_new', 0, 'rows', 0,
      'rejected', jsonb_build_array(jsonb_build_object('i', -1, 'reason', 'db_size_cap')));
  end if;

  drop table if exists pg_temp._att_in;
  create temp table _att_in on commit drop as
  select (e.ord - 1)::int                                   as i,
         e.r->>'source'                                     as source,
         coalesce(nullif(e.r->>'metric', ''), 'n')          as metric,
         coalesce(nullif(e.r->>'geo', ''), 'ALL')           as geo,
         nullif(e.r->>'key', '')                            as key,
         case when e.r->>'day' ~ '^\d{4}-\d{2}-\d{2}$' then (e.r->>'day')::date end as day,
         case when e.r->>'ts' ~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}'
              then date_trunc('hour', (e.r->>'ts')::timestamptz) end as ts,
         (e.r ? 'day') as has_day, (e.r ? 'ts') as has_ts,
         case when jsonb_typeof(e.r->'value') = 'number' then (e.r->>'value')::double precision
              when e.r->>'value' ~ '^-?\d+(\.\d+)?([eE][-+]?\d+)?$' then (e.r->>'value')::double precision end as value,
         case when jsonb_typeof(e.r->'aux') = 'number' then (e.r->>'aux')::real end as aux,
         ripples._att_clean_meta(case when jsonb_typeof(e.r->'meta') = 'object' then e.r->'meta' end) as meta,
         case when e.r->>'topic_id' ~ '^\d+$' then (e.r->>'topic_id')::bigint end as topic_id,
         null::bigint as series_id,
         null::text   as reason
  from jsonb_array_elements(p_rows) with ordinality e(r, ord);

  update pg_temp._att_in set reason = 'missing_source_or_key' where source is null or key is null;
  update pg_temp._att_in i set reason = 'unknown_source'
   where reason is null and not exists (select 1 from ripples.att_sources s where s.source = i.source);
  update pg_temp._att_in i set reason = 'disabled_source'
   where reason is null and exists (select 1 from ripples.att_sources s where s.source = i.source and not s.enabled);
  update pg_temp._att_in set reason = 'need_exactly_one_of_day_ts'
   where reason is null and ((has_day and has_ts) or (not has_day and not has_ts));
  update pg_temp._att_in set reason = 'bad_time'
   where reason is null and ((has_day and day is null) or (has_ts and ts is null)
         or day > (now() at time zone 'utc')::date + 1 or ts > now() + interval '1 hour');
  update pg_temp._att_in set reason = 'bad_value'
   where reason is null and (value is null or value = 'NaN'::double precision
         or value in ('Infinity'::double precision, '-Infinity'::double precision));
  -- hard rule 4 (defense in depth): series keys must not look like handles, DIDs, e-mail addresses or URLs
  update pg_temp._att_in set reason = 'identifier_like_key'
   where reason is null and ripples._att_ident_like(key, source);

  with ins as (
    insert into ripples.att_series(source, metric, geo, key, topic_id)
    select distinct on (i.source, i.metric, i.geo, i.key) i.source, i.metric, i.geo, i.key,
           coalesce(i.topic_id, (select k.topic_id from ripples.att_keys k
                                 where k.source = i.source and k.key = i.key
                                 order by (k.metric = i.metric and k.geo = i.geo) desc, k.topic_id limit 1))
    from pg_temp._att_in i where i.reason is null
    order by i.source, i.metric, i.geo, i.key, i.topic_id nulls last
    on conflict (source, metric, geo, key) do nothing
    returning 1)
  select count(*) into v_new from ins;

  update pg_temp._att_in i set series_id = s.series_id
    from ripples.att_series s
   where i.reason is null and s.source = i.source and s.metric = i.metric and s.geo = i.geo and s.key = i.key;

  update ripples.att_keys k set series_id = s.series_id
    from ripples.att_series s
   where k.series_id is null and s.source = k.source and s.metric = k.metric and s.geo = k.geo and s.key = k.key
     and s.series_id in (select series_id from pg_temp._att_in where series_id is not null);

  -- free-tier profile: hourly series only for active topics (source totals / unlinked keys are allowed)
  if coalesce((ripples._att_cfg('hourly_active_only'))::text::boolean, true) then
    update pg_temp._att_in i set reason = 'hourly_active_only'
      from ripples.att_series s join ripples.att_topics t on t.topic_id = s.topic_id
     where i.reason is null and i.ts is not null and s.series_id = i.series_id and t.status <> 'active';
  end if;

  with d as (
    select distinct on (series_id, day) series_id, day, value, aux, meta
    from pg_temp._att_in where reason is null and day is not null
    order by series_id, day, i desc),
  up as (
    insert into ripples.attention_obs(series_id, day, value, aux, meta)
    select series_id, day, value, aux, meta from d
    on conflict (series_id, day) do update set value = excluded.value, aux = excluded.aux, meta = excluded.meta
    returning 1)
  select count(*) into v_daily from up;

  with h as (
    select distinct on (series_id, ts) series_id, ts, value, aux
    from pg_temp._att_in where reason is null and ts is not null
    order by series_id, ts, i desc),
  up as (
    insert into ripples.attention_obs_hourly(series_id, ts, value, aux)
    select series_id, ts, value, aux from h
    on conflict (series_id, ts) do update set value = excluded.value, aux = excluded.aux
    returning 1)
  select count(*) into v_hourly from up;

  update ripples.att_series s set last_day = greatest(coalesce(s.last_day, x.d), x.d)
    from (select series_id, max(coalesce(day, (ts at time zone 'utc')::date)) d
          from pg_temp._att_in where reason is null group by series_id) x
   where s.series_id = x.series_id;

  select coalesce(jsonb_agg(jsonb_build_object('i', i, 'reason', reason) order by i), '[]'::jsonb) into v_rej
  from (select i, reason from pg_temp._att_in where reason is not null order by i limit 200) r;

  drop table if exists pg_temp._att_in;
  return jsonb_build_object('series_new', v_new, 'rows', v_daily + v_hourly, 'daily', v_daily, 'hourly', v_hourly, 'rejected', v_rej);
end $$;

create or replace function ripples.att_ingest_edges(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v int; v_bad int;
begin
  with e as (
    select distinct on (x.source, coalesce(x.geo,'ALL'), x.from_key, x.to_key, x.period, x.grain) x.*
    from jsonb_to_recordset(p_rows) as x(source text, geo text, from_key text, to_key text, period date, grain text,
                                          n double precision, lift real, pmi real, from_topic bigint, to_topic bigint, meta jsonb)
    join ripples.att_sources s on s.source = x.source and s.enabled
    where x.from_key is not null and x.to_key is not null and x.period is not null and x.n is not null
      and x.grain in ('day','month')
      and not ripples._att_ident_like(x.from_key, x.source, true) and not ripples._att_ident_like(x.to_key, x.source, true)),
  up as (
    insert into ripples.att_edges(source, geo, from_key, to_key, period, grain, n, lift, pmi, from_topic, to_topic, meta)
    select source, coalesce(geo,'ALL'), from_key, to_key, period, grain, n, lift, pmi, from_topic, to_topic,
           ripples._att_clean_meta(meta) from e
    on conflict (source, geo, from_key, to_key, period, grain) do update
      set n = excluded.n, lift = excluded.lift, pmi = excluded.pmi, meta = excluded.meta,
          from_topic = coalesce(excluded.from_topic, ripples.att_edges.from_topic),
          to_topic = coalesce(excluded.to_topic, ripples.att_edges.to_topic)
    returning 1)
  select count(*) into v from up;
  v_bad := jsonb_array_length(p_rows) - v;
  return jsonb_build_object('rows', v, 'rejected', v_bad);
end $$;

create or replace function ripples.att_ingest_candidates(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v int;
begin
  with c as (
    select distinct on (x.day, x.source, coalesce(x.geo,'ALL'), x.label) x.*
    from jsonb_to_recordset(p_rows) as x(day date, source text, geo text, label text, rank int, value double precision,
                                          evidence real, qid text, topic_id bigint, meta jsonb)
    join ripples.att_sources s on s.source = x.source and s.enabled
    where x.day is not null and x.label is not null and x.evidence between 0 and 1
      and not ripples._att_ident_like(x.label, x.source, true) and length(x.label) <= 200),
  up as (
    insert into ripples.att_trend_candidates(day, source, geo, label, rank, value, evidence, qid, topic_id, meta)
    select day, source, coalesce(geo,'ALL'), left(label, 200), rank, value, evidence, qid, topic_id,
           ripples._att_clean_meta(meta) from c
    on conflict (day, source, geo, label) do update
      set rank = excluded.rank, value = excluded.value, evidence = excluded.evidence,
          qid = coalesce(excluded.qid, ripples.att_trend_candidates.qid),
          topic_id = coalesce(excluded.topic_id, ripples.att_trend_candidates.topic_id),
          meta = excluded.meta, observed_at = now()
    returning 1)
  select count(*) into v from up;
  return jsonb_build_object('rows', v, 'rejected', jsonb_array_length(p_rows) - v);
end $$;

create or replace function ripples.att_gen_keys(p_topic bigint, p_facts jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare
  v_term text; v_aliases text[]; v_tag text; v_lang text; v_title text; v_title_en text; v_n int := 0; v_c int;
begin
  v_lang := coalesce(nullif(p_facts->>'lang', ''), 'en');
  v_title := nullif(replace(p_facts->>'title', ' ', '_'), '');
  v_title_en := nullif(replace(p_facts->>'title_en', ' ', '_'), '');
  v_term := ripples.att_norm_term(coalesce(nullif(p_facts->>'label_en', ''), replace(v_title_en, '_', ' '), p_facts->>'label'));

  select coalesce(array_agg(a order by a), '{}') into v_aliases from (
    select distinct a from (
      select ripples.att_norm_term(x) a from jsonb_array_elements_text(
               case when jsonb_typeof(p_facts->'aliases') = 'array' then p_facts->'aliases' else '[]'::jsonb end) x
      union select ripples.att_norm_term(p_facts->>'label')
      union select ripples.att_norm_term(v_title)
      union select ripples.att_norm_term(v_title_en)) z
    where a is not null and a is distinct from v_term and ripples._att_alias_ok(v_term, a) and not ripples.att_is_stopword(a)
    limit 8) q;

  if v_term is not null and char_length(v_term) >= 2 and not ripples.att_is_stopword(v_term) then
    insert into ripples.att_keys(topic_id, source, metric, geo, key, key_type, match)
    select p_topic, s.source, 'n', 'ALL', v_term, 'term',
           jsonb_build_object('strict', true, 'whole_word', true, 'aliases', to_jsonb(v_aliases))
    from ripples.att_sources s
    where s.enabled and s.source in ('hn.algolia','se.api','bsky.jet','gdelt.gkg','ia.thirdeye')
    on conflict (topic_id, source, metric, geo, key) do update set match = excluded.match
      where ripples.att_keys.created_by = 'auto';
    get diagnostics v_c = row_count; v_n := v_n + v_c;

    v_tag := regexp_replace(v_term, '[^[:alnum:]]', '', 'g');
    if char_length(v_tag) between 4 and 40 then
      insert into ripples.att_keys(topic_id, source, metric, geo, key, key_type, match)
      select p_topic, 'masto.tags', 'n', 'ALL', v_tag, 'hashtag', jsonb_build_object('hashtag', true)
      where exists (select 1 from ripples.att_sources where source = 'masto.tags' and enabled)
      on conflict do nothing;
      get diagnostics v_c = row_count; v_n := v_n + v_c;
    end if;
  end if;

  -- Wikipedia title keys (wiki.pv, per language edition)
  insert into ripples.att_keys(topic_id, source, metric, geo, key, key_type, match)
  select distinct p_topic, 'wiki.pv', 'n', x.g, x.t, 'title', '{}'::jsonb
  from (values ('en.wikipedia', v_title_en), (v_lang || '.wikipedia', v_title)) x(g, t)
  where x.t is not null
  on conflict do nothing;
  get diagnostics v_c = row_count; v_n := v_n + v_c;

  -- structured keys from Wikidata properties
  insert into ripples.att_keys(topic_id, source, metric, geo, key, key_type, match)
  select p_topic, m.source, 'n', 'ALL', m.k, m.kt, '{}'::jsonb
  from (
    select 'finra.shvol' source, upper(x) k, 'ticker' kt from jsonb_array_elements_text(coalesce(p_facts->'tickers','[]')) x
    union all select 'gh.stars', lower(x), 'repo' from jsonb_array_elements_text(coalesce(p_facts->'repos','[]')) x
    union all select 'npm.dl', x, 'package' from jsonb_array_elements_text(coalesce(p_facts->'npm','[]')) x
    union all select 'pypi.dl', lower(x), 'package' from jsonb_array_elements_text(coalesce(p_facts->'pypi','[]')) x
    union all select 'tranco.rank', lower(x), 'domain' from jsonb_array_elements_text(coalesce(p_facts->'domains','[]')) x
    union all select 'steamspy', x, 'appid' from jsonb_array_elements_text(coalesce(p_facts->'steam','[]')) x
    union all select 'anilist', x, 'media' from jsonb_array_elements_text(coalesce(p_facts->'anilist','[]')) x
    union all select 'apple.rss', x, 'appid' from jsonb_array_elements_text(coalesce(p_facts->'apple','[]')) x
  ) m join ripples.att_sources s on s.source = m.source and s.enabled
  where m.k is not null and m.k <> ''
  on conflict do nothing;
  get diagnostics v_c = row_count; v_n := v_n + v_c;

  -- link existing series
  update ripples.att_keys k set series_id = s.series_id
    from ripples.att_series s
   where k.topic_id = p_topic and k.series_id is null
     and s.source = k.source and s.metric = k.metric and s.geo = k.geo and s.key = k.key;
  update ripples.att_series s set topic_id = p_topic
    from ripples.att_keys k
   where k.topic_id = p_topic and k.series_id = s.series_id and s.topic_id is null;
  return v_n;
end $$;

-- existing term keys: drop aliases that fail the new rule
update ripples.att_keys k set match = jsonb_set(k.match, '{aliases}',
  coalesce((select jsonb_agg(a order by a) from jsonb_array_elements_text(k.match->'aliases') a
            where ripples._att_alias_ok(k.key, a)), '[]'::jsonb))
where k.key_type = 'term' and jsonb_typeof(k.match->'aliases') = 'array'
  and exists (select 1 from jsonb_array_elements_text(k.match->'aliases') a where not ripples._att_alias_ok(k.key, a));

-- ---------- SKIP rules: localized dates, necrologies, zh/ja list pages, evergreen reference pages ----------
create or replace function ripples.att_skip_title(p_title text) returns boolean
language sql immutable security definer set search_path = '' as $$
  select p_title is null or btrim(p_title) in ('', '-')
   or p_title ~* ('^(Special|Spezial|Especial|Spécial|Speciale|特別|特殊|Служебная|विशेष|Wikipedia|Wikipédia|Википедия|विकिपीडिया|ウィキペディア|Project|'
       || 'Portal|Portail|Портал|Progetto|Talk|Discussion|Diskussion|Discusión|Discussione|Обсуждение|File|Datei|Fichier|Archivo|Ficheiro|Файл|ファイル|文件|चित्र|Image|'
       || 'Help|Hilfe|Aide|Ayuda|Aiuto|Ajuda|Справка|ヘルプ|帮助|सहायता|Template|Vorlage|Modèle|Plantilla|Predefinição|Шаблон|テンプレート|साँचा|'
       || 'Category|Kategorie|Catégorie|Categoría|Categoria|Категория|カテゴリ|分类|श्रेणी|User|Benutzer|Utilisateur|Usuario|Usuário|Utente|Участник|利用者|用户|सदस्य|'
       || 'MediaWiki|Module|Modul|Módulo|Модуль|モジュール|Draft|Brouillon|Entwurf|Media|Медиа|Anexo)(_talk|_Diskussion)?:')
   or p_title ~* '^(Main_Page|Hauptseite|Página_principal|Pagina_principale|Portada|Accueil_principal|メインページ|Заглавная_страница|मुखपृष्ठ|首页|Wikipedia)$'
   or p_title ~* '^(List_of_|Lists_of_|Liste_d|Liste_der_|Lista_d|Список_|Deaths_in_|Décès_en_|Todesfälle_)'
   or p_title ~* '^(Nekrolog_[0-9]{4}|Morts_en_|Muertes_en_|Fallecidos_en_|Mortes_em_|Morti_nel_|Умершие_в_)'
   or p_title ~ '(列表|一覧|の一覧)$' or p_title ~ '^[0-9]{4}年逝世'
   or p_title ~* '\((disambiguation|homonymie|Begriffsklärung|desambiguación|desambiguação|disambigua)\)$'
   or p_title ~ '^[0-9]{1,4}(_(BC|AD|in_[A-Za-z_]+))?$'
   or p_title ~* '^(January|February|March|April|May|June|July|August|September|October|November|December)_[0-9]{1,2}$'
   or p_title ~* '^(1er|[0-9]{1,2})\.?_(de_)?(January|February|March|April|May|June|July|August|September|October|November|December|Januar|Februar|März|Mai|Juni|Juli|Oktober|Dezember|janvier|février|mars|avril|mai|juin|juillet|août|septembre|octobre|novembre|décembre|enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre|janeiro|fevereiro|março|maio|junho|julho|setembro|outubro|novembro|dezembro|gennaio|febbraio|aprile|maggio|giugno|luglio|settembre|ottobre|dicembre|января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря)$'
   or p_title ~ '^[0-9]{1,2}月[0-9]{1,2}日$'
   or p_title ~* '^(States_and_union_territories_of_India|भारत_के_राज्य_तथा_केन्द्र-शासित_प्रदेश)$'
   or p_title ~* '^(XXX|Pornhub|XVideos|XHamster|XNXX|Xvideos|OnlyFans_leak|Undefined|Null|Cleopatra_\(XXX\))$'
$$;

-- daily maintenance also retires active (non-panel) topics whose title or any wiki.pv key is a SKIP page
create or replace function ripples.att_registry_maintain() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v int; v_skip int;
begin
  update ripples.att_topics set status = 'dormant'
   where status = 'active' and origin in ('trend','hop') and coalesce(last_active, first_seen) < current_date - 30;
  get diagnostics v = row_count;
  update ripples.att_topics t set status = 'retired', meta = t.meta || '{"retired": "skip_rule"}'::jsonb
   where t.status = 'active' and not t.in_panel
     and ((t.title_en is not null and ripples.att_skip_title(t.title_en))
          or exists (select 1 from ripples.att_keys k where k.topic_id = t.topic_id and k.source = 'wiki.pv'
                     and ripples.att_skip_title(k.key)));
  get diagnostics v_skip = row_count;
  return jsonb_build_object('dormant', v, 'retired_skip', v_skip);
end $$;

-- ---------- grants (every att function: service_role only) ----------
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where (n.nspname = 'ripples' and (p.proname like 'att\_%' or p.proname like '\_att\_%'))
              or (n.nspname = 'public' and p.proname like 'att\_%')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;
notify pgrst, 'reload schema';
