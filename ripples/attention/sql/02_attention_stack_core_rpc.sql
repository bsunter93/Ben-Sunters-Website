-- Migration: attention_stack_core_rpc  (W7 att-core, 2026-09-25)
-- ATTENTION_STACK §7.2 core RPCs: ingest, budget, state, registry/key generation, job queue, tick, run log.
-- All: SECURITY DEFINER, search_path = '', EXECUTE for service_role only.
-- Edge functions reach them through thin public.att_* wrappers (the ripples schema is not exposed to PostgREST).

-- ---------- helpers ----------
create or replace function ripples._att_cfg(p_key text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select value from ripples.att_config where key = p_key
$$;

create or replace function ripples.att_config_get(p_key text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select value from ripples.att_config where key = p_key
$$;

create or replace function ripples.att_norm_term(p text) returns text
language sql immutable set search_path = '' as $$
  select nullif(lower(btrim(regexp_replace(regexp_replace(replace(coalesce(p,''), '_', ' '),
         '\s*\([^)]*\)\s*$', ''), '\s+', ' ', 'g'))), '')
$$;

create or replace function ripples.att_is_stopword(p text) returns boolean
language sql immutable set search_path = '' as $$
  select lower(coalesce(p,'')) = any (array[
    'a','about','above','after','again','against','all','also','an','and','any','are','as','at','be','because','been',
    'before','being','below','between','both','but','by','can','could','did','do','does','doing','down','during','each',
    'even','ever','every','few','for','from','further','had','has','have','having','he','her','here','hers','herself',
    'him','himself','his','how','however','into','is','it','its','itself','just','like','made','make','many','may','me',
    'might','more','most','much','must','my','myself','never','new','next','nor','not','now','of','off','often','on',
    'once','only','or','other','our','ours','out','over','own','same','she','should','since','some','still','such',
    'than','that','the','their','theirs','them','then','there','these','they','this','those','through','thus','to',
    'too','under','until','upon','very','was','we','well','were','what','when','where','which','while','who','whom',
    'whose','why','will','with','within','without','would','yet','you','your','yours','none','null','undefined',
    'people','thing','things','today','news','video','world','first','last','year','years','time','home','page'])
$$;

-- SKIP rules for Wikipedia titles (namespaces in the 10 tracked languages, main pages, lists, dates, bot artifacts)
create or replace function ripples.att_skip_title(p_title text) returns boolean
language sql immutable set search_path = '' as $$
  select p_title is null or btrim(p_title) in ('', '-')
   or p_title ~* ('^(Special|Spezial|Especial|Spécial|Speciale|特別|特殊|Служебная|विशेष|Wikipedia|Wikipédia|Википедия|विकिपीडिया|ウィキペディア|Project|'
       || 'Portal|Portail|Портал|Progetto|Talk|Discussion|Diskussion|Discusión|Discussione|Обсуждение|File|Datei|Fichier|Archivo|Ficheiro|Файл|ファイル|文件|चित्र|Image|'
       || 'Help|Hilfe|Aide|Ayuda|Aiuto|Ajuda|Справка|ヘルプ|帮助|सहायता|Template|Vorlage|Modèle|Plantilla|Predefinição|Шаблон|テンプレート|साँचा|'
       || 'Category|Kategorie|Catégorie|Categoría|Categoria|Категория|カテゴリ|分类|श्रेणी|User|Benutzer|Utilisateur|Usuario|Usuário|Utente|Участник|利用者|用户|सदस्य|'
       || 'MediaWiki|Module|Modul|Módulo|Модуль|モジュール|Draft|Brouillon|Entwurf|Media|Медиа|Anexo)(_talk|_Diskussion)?:')
   or p_title ~* '^(Main_Page|Hauptseite|Página_principal|Pagina_principale|Portada|Accueil_principal|メインページ|Заглавная_страница|मुखपृष्ठ|首页|Wikipedia)$'
   or p_title ~* '^(List_of_|Lists_of_|Liste_d|Liste_der_|Lista_d|Список_|Deaths_in_|Décès_en_|Todesfälle_)'
   or p_title ~* '\((disambiguation|homonymie|Begriffsklärung|desambiguación|desambiguação|disambigua)\)$'
   or p_title ~ '^[0-9]{1,4}(_(BC|AD|in_[A-Za-z_]+))?$'
   or p_title ~* '^(January|February|March|April|May|June|July|August|September|October|November|December)_[0-9]{1,2}$'
   or p_title ~* '^(XXX|Pornhub|XVideos|XHamster|XNXX|Xvideos|OnlyFans_leak|Undefined|Null|Cleopatra_\(XXX\))$'
$$;

-- ---------- state ----------
create or replace function ripples.att_state_get(p_k text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select v from ripples.att_state where k = p_k
$$;

create or replace function ripples.att_state_set(p_k text, p_v jsonb) returns void
language sql security definer set search_path = '' as $$
  insert into ripples.att_state(k, v, updated_at) values (p_k, coalesce(p_v, 'null'::jsonb), now())
  on conflict (k) do update set v = excluded.v, updated_at = now()
$$;

-- ---------- budget ----------
create or replace function ripples._att_bucket(p_bucket text, out bucket text, out cap int, out enabled boolean)
language plpgsql stable security definer set search_path = '' as $$
declare s record;
begin
  bucket := p_bucket; enabled := true;
  select * into s from ripples.att_sources where source = p_bucket;
  if found then
    enabled := s.enabled;
    if s.budget_bucket is not null then bucket := s.budget_bucket; else cap := s.per_day_cap; end if;
  end if;
  if cap is null then
    cap := (ripples._att_cfg('budgets') ->> bucket)::int;
  end if;
end $$;

create or replace function ripples.att_take_budget(p_bucket text, p_n int) returns int
language plpgsql security definer set search_path = '' as $$
declare b record; v_used int; v_cap int; v_grant int; v_q jsonb; v_t time; v_day date := (now() at time zone 'utc')::date;
begin
  if p_n is null or p_n <= 0 or p_bucket is null then return 0; end if;
  select * into b from ripples._att_bucket(p_bucket);
  if not b.enabled or b.cap is null then return 0; end if;
  if b.bucket = 'wikimedia' then            -- no attention Wikimedia calls while the puzzle build runs
    v_q := ripples._att_cfg('wm_quiet_utc');
    v_t := (now() at time zone 'utc')::time;
    if v_q is not null and v_t >= (v_q->>'from')::time and v_t < (v_q->>'to')::time then return 0; end if;
  end if;
  insert into ripples.att_budget(bucket, day, used, cap) values (b.bucket, v_day, 0, b.cap)
  on conflict (bucket, day) do nothing;
  select used, cap into v_used, v_cap from ripples.att_budget where bucket = b.bucket and day = v_day for update;
  v_grant := greatest(0, least(p_n, v_cap - v_used));
  if v_grant > 0 then
    update ripples.att_budget set used = used + v_grant where bucket = b.bucket and day = v_day;
  end if;
  return v_grant;
end $$;

-- 429/503/403 kill switch: host stopped until next UTC midnight; the source's budget is spent for today
-- and tomorrow's cap is halved ("resume next day at half the rate").
create or replace function ripples.att_host_kill(p_host text, p_status int, p_source text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare b record; v_day date := (now() at time zone 'utc')::date; v_until timestamptz;
begin
  v_until := (v_day + 1)::timestamp at time zone 'utc';
  perform ripples.att_state_set('kill:' || lower(p_host),
    jsonb_build_object('status', p_status, 'at', now(), 'until', v_until, 'source', p_source));
  if p_source is not null then
    select * into b from ripples._att_bucket(p_source);
    if b.cap is not null then
      insert into ripples.att_budget(bucket, day, used, cap) values (b.bucket, v_day, b.cap, b.cap)
      on conflict (bucket, day) do update set used = ripples.att_budget.cap;
      if p_status in (429, 503) then
        insert into ripples.att_budget(bucket, day, used, cap) values (b.bucket, v_day + 1, 0, greatest(1, b.cap / 2))
        on conflict (bucket, day) do update set cap = least(ripples.att_budget.cap, excluded.cap);
      end if;
    end if;
  end if;
  return jsonb_build_object('host', p_host, 'until', v_until);
end $$;

-- ---------- run log ----------
create or replace function ripples.att_run_start(p_fn text, p_mode text, p_detail jsonb default null) returns bigint
language sql security definer set search_path = '' as $$
  insert into ripples.att_runs(fn, mode, detail) values (p_fn, coalesce(p_mode, '?'), p_detail) returning run_id
$$;

create or replace function ripples.att_run_finish(p_run bigint, p_result jsonb) returns void
language sql security definer set search_path = '' as $$
  update ripples.att_runs set
    finished_at   = now(),
    ok            = coalesce((p_result->>'ok')::boolean, false),
    partial       = coalesce((p_result->>'partial')::boolean, false),
    requests      = (p_result->'requests'->>'made')::int,
    rows_upserted = coalesce((p_result->'rows'->>'obs')::int, 0) + coalesce((p_result->'rows'->>'obs_hourly')::int, 0)
                  + coalesce((p_result->'rows'->>'edges')::int, 0) + coalesce((p_result->'rows'->>'candidates')::int, 0),
    http          = p_result->'requests'->'by_host',
    error         = nullif(left(coalesce(p_result->'errors', '[]'::jsonb)::text, 4000), '[]'),
    detail        = coalesce(detail, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
                      'sources', p_result->'sources', 'skipped', p_result->'skipped',
                      'next_cursor', p_result->'next_cursor', 'extra', p_result->'extra'))
  where run_id = p_run
$$;

-- ---------- ingest ----------
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
         case when jsonb_typeof(e.r->'meta') = 'object' then e.r->'meta' end as meta,
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

-- spec form (§7.2): p_run = {"run_id":…} adds the upserted row count to att_runs
create or replace function ripples.att_ingest(p_run jsonb, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r jsonb;
begin
  r := ripples.att_ingest(p_rows);
  if p_run ? 'run_id' and (p_run->>'run_id') ~ '^\d+$' then
    update ripples.att_runs set rows_upserted = coalesce(rows_upserted, 0) + (r->>'rows')::int
     where run_id = (p_run->>'run_id')::bigint;
  end if;
  return r;
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
      and x.grain in ('day','month')),
  up as (
    insert into ripples.att_edges(source, geo, from_key, to_key, period, grain, n, lift, pmi, from_topic, to_topic, meta)
    select source, coalesce(geo,'ALL'), from_key, to_key, period, grain, n, lift, pmi, from_topic, to_topic, meta from e
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
    where x.day is not null and x.label is not null and x.evidence between 0 and 1),
  up as (
    insert into ripples.att_trend_candidates(day, source, geo, label, rank, value, evidence, qid, topic_id, meta)
    select day, source, coalesce(geo,'ALL'), left(label, 300), rank, value, evidence, qid, topic_id, meta from c
    on conflict (day, source, geo, label) do update
      set rank = excluded.rank, value = excluded.value, evidence = excluded.evidence,
          qid = coalesce(excluded.qid, ripples.att_trend_candidates.qid),
          topic_id = coalesce(excluded.topic_id, ripples.att_trend_candidates.topic_id),
          meta = excluded.meta, observed_at = now()
    returning 1)
  select count(*) into v from up;
  return jsonb_build_object('rows', v, 'rejected', jsonb_array_length(p_rows) - v);
end $$;

create or replace function ripples.att_load_qid_map(p_rows jsonb) returns int
language sql security definer set search_path = '' as $$
  with up as (
    insert into ripples.att_qid_map(wiki, title, qid)
    select distinct on (wiki, title) wiki, title, qid
    from jsonb_to_recordset(p_rows) as x(wiki text, title text, qid text)
    where wiki is not null and title is not null and qid ~ '^Q\d+$'
    on conflict (wiki, title) do update set qid = excluded.qid
    returning 1)
  select count(*)::int from up
$$;

-- ---------- job queue ----------
create or replace function ripples.att_job_enqueue(
  p_kind text, p_fn text, p_payload jsonb, p_priority int default 5,
  p_dedupe text default null, p_batch_key text default null, p_not_before timestamptz default null) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  insert into ripples.att_jobs(kind, fn, payload, priority, dedupe_key, batch_key, not_before)
  values (p_kind, p_fn, coalesce(p_payload, '{}'::jsonb), coalesce(p_priority, 5), p_dedupe, p_batch_key, coalesce(p_not_before, now()))
  on conflict (dedupe_key) where status in ('queued','running') and dedupe_key is not null do nothing
  returning id into v_id;
  if v_id is null and p_dedupe is not null then     -- already queued: keep the higher priority
    update ripples.att_jobs set priority = least(priority, coalesce(p_priority, 5))
     where dedupe_key = p_dedupe and status in ('queued','running') returning id into v_id;
  end if;
  return v_id;
end $$;

-- p_status: 'done' | 'failed' | 'skipped' | 'requeue' (budget exhausted: back to the queue without using an attempt)
create or replace function ripples.att_jobs_done(p_jobs bigint[], p_status text, p_error text default null,
                                                  p_not_before timestamptz default null) returns int
language plpgsql security definer set search_path = '' as $$
declare v int;
begin
  if p_status = 'requeue' then
    update ripples.att_jobs set status = 'queued', attempts = greatest(0, attempts - 1), http_req = null,
           not_before = coalesce(p_not_before, now() + interval '1 hour'), error = left(p_error, 2000)
     where id = any(p_jobs) and status in ('running','queued');
  elsif p_status in ('done','failed','skipped') then
    update ripples.att_jobs set status = p_status, finished_at = now(), error = left(p_error, 2000)
     where id = any(p_jobs) and status in ('running','queued');
  else
    raise exception 'att_jobs_done: bad status %', p_status;
  end if;
  get diagnostics v = row_count;
  return v;
end $$;

create or replace function ripples.att_fn_live(p_fn text, p_on boolean default true) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v jsonb;
begin
  select coalesce(jsonb_agg(distinct f), '[]'::jsonb) into v from (
    select jsonb_array_elements_text(coalesce(ripples._att_cfg('live_fns'), '[]'::jsonb)) f
    union select p_fn where p_on) z
  where p_on or f <> p_fn;
  insert into ripples.att_config(key, value) values ('live_fns', v)
  on conflict (key) do update set value = excluded.value, updated_at = now();
  return v;
end $$;

create or replace function ripples.att_set_profile(p_profile text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if p_profile not in ('free','pro') then raise exception 'profile must be free or pro'; end if;
  insert into ripples.att_config(key, value) values
    ('profile', to_jsonb(p_profile)),
    ('panel_size', case when p_profile = 'pro' then '1000' else '300' end::jsonb),
    ('hourly_active_only', case when p_profile = 'pro' then 'false' else 'true' end::jsonb),
    ('db_cap_mb', case when p_profile = 'pro' then '7000' else '400' end::jsonb)
  on conflict (key) do update set value = excluded.value, updated_at = now();
  return (select jsonb_object_agg(key, value) from ripples.att_config
          where key in ('profile','panel_size','hourly_active_only','db_cap_mb'));
end $$;

-- att_tick: reconcile finished HTTP calls, requeue stuck jobs, dispatch <= max_edge_inflight edge jobs through
-- public.call_collector (backfill jobs sharing fn+batch_key are merged, up to backfill_batch keys), run <= max_sql SQL jobs.
-- p_mode: 'collect' (all kinds), 'hops' (ensure_series/test/placebo), 'backfill' (backfill/resolve).
create or replace function ripples.att_tick(p_mode text default 'collect') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  cfg jsonb := coalesce(ripples._att_cfg('tick'), '{}'::jsonb);
  v_live text[]; v_kinds text[]; v_max int; v_batch int; v_stuck int; v_maxsql int;
  v_inflight int; v_slots int; j record; r record;
  v_ids bigint[]; v_keys jsonb; v_payload jsonb; v_req bigint; v_rpc text;
  n_disp int := 0; n_done int := 0; n_fail int := 0; n_requeue int := 0; n_sql int := 0;
begin
  v_max    := coalesce((cfg->>'max_edge_inflight')::int, 6);
  v_batch  := coalesce((cfg->>'backfill_batch')::int, 25);
  v_stuck  := coalesce((cfg->>'stuck_min')::int, 5);
  v_maxsql := coalesce((cfg->>'max_sql')::int, 40);
  select coalesce(array_agg(x), '{}') into v_live
    from jsonb_array_elements_text(coalesce(ripples._att_cfg('live_fns'), '[]'::jsonb)) x;
  v_kinds := case p_mode
    when 'hops' then array['ensure_series','test','placebo']
    when 'backfill' then array['backfill','resolve']
    else array['backfill','ensure_series','test','placebo','resolve'] end;

  -- 1. reconcile pg_net responses for running jobs
  for r in
    select a.id, a.attempts, h.status_code, h.timed_out, h.error_msg
    from ripples.att_jobs a join net._http_response h on h.id = a.http_req
    where a.status = 'running'
  loop
    if r.status_code between 200 and 299 then
      update ripples.att_jobs set status = 'done', finished_at = now() where id = r.id; n_done := n_done + 1;
    elsif r.attempts >= 3 then
      update ripples.att_jobs set status = 'failed', finished_at = now(),
             error = coalesce(r.error_msg, 'http ' || coalesce(r.status_code::text, 'timeout')) where id = r.id;
      n_fail := n_fail + 1;
    else
      update ripples.att_jobs set status = 'queued', http_req = null, not_before = now() + interval '10 minutes',
             error = coalesce(r.error_msg, 'http ' || coalesce(r.status_code::text, 'timeout')) where id = r.id;
      n_requeue := n_requeue + 1;
    end if;
  end loop;

  -- 2. stuck jobs (no response after stuck_min)
  with s as (
    update ripples.att_jobs set
      status = case when attempts >= 3 then 'failed' else 'queued' end,
      finished_at = case when attempts >= 3 then now() end,
      http_req = null, error = 'stuck > ' || v_stuck || ' min'
    where status = 'running' and started_at < now() - make_interval(mins => v_stuck)
    returning 1)
  select n_requeue + count(*) into n_requeue from s;

  -- 3. dispatch edge jobs
  select count(*) into v_inflight from ripples.att_jobs where status = 'running' and fn is not null;
  v_slots := greatest(0, v_max - v_inflight);
  while v_slots > 0 loop
    select * into j from ripples.att_jobs
     where status = 'queued' and not_before <= now() and fn is not null and fn = any(v_live) and kind = any(v_kinds)
     order by priority, id limit 1 for update skip locked;
    exit when not found;
    if j.kind in ('backfill','resolve') and j.batch_key is not null then
      -- merge queued jobs with the same fn + batch_key: their 'keys' (backfill) or 'items' (resolve) arrays are concatenated
      with b as (
        select id, payload from ripples.att_jobs
         where (id = j.id) or (status = 'queued' and not_before <= now() and fn = j.fn and batch_key = j.batch_key)
         order by (id = j.id) desc, priority, id limit v_batch for update skip locked)
      select array_agg(b.id),
             coalesce((select jsonb_agg(k.v) from b b2, jsonb_array_elements(coalesce(b2.payload->(case when j.kind = 'resolve' then 'items' else 'keys' end), '[]'::jsonb)) k(v)), '[]'::jsonb)
        into v_ids, v_keys
        from b;
      v_payload := j.payload || jsonb_build_object(case when j.kind = 'resolve' then 'items' else 'keys' end, v_keys,
                                                   'job_id', j.id, 'job_ids', to_jsonb(v_ids));
    else
      v_ids := array[j.id];
      v_payload := j.payload || jsonb_build_object('job_id', j.id, 'job_ids', to_jsonb(v_ids));
    end if;
    v_req := public.call_collector(j.fn, v_payload);
    update ripples.att_jobs set status = 'running', started_at = now(), attempts = attempts + 1, http_req = v_req, error = null
     where id = any(v_ids);
    n_disp := n_disp + 1; v_slots := v_slots - 1;
  end loop;

  -- 4. SQL jobs (fn null): payload {"rpc":"att_xxx","args":{...}} -> select ripples.att_xxx(args::jsonb)
  for j in
    select * from ripples.att_jobs
     where status = 'queued' and fn is null and not_before <= now() and kind = any(v_kinds)
     order by priority, id limit v_maxsql for update skip locked
  loop
    v_rpc := j.payload->>'rpc';
    if v_rpc is null or v_rpc !~ '^att_[a-z0-9_]+$' or to_regprocedure('ripples.' || v_rpc || '(jsonb)') is null then
      update ripples.att_jobs set status = 'failed', finished_at = now(), error = 'unknown rpc ' || coalesce(v_rpc, 'null')
       where id = j.id;
      continue;
    end if;
    begin
      execute format('select ripples.%I($1)', v_rpc) using coalesce(j.payload->'args', '{}'::jsonb);
      update ripples.att_jobs set status = 'done', attempts = attempts + 1, started_at = now(), finished_at = now() where id = j.id;
    exception when others then
      update ripples.att_jobs set attempts = attempts + 1, error = left(sqlerrm, 2000),
             status = case when attempts + 1 >= 3 then 'failed' else 'queued' end,
             not_before = now() + interval '5 minutes' where id = j.id;
    end;
    n_sql := n_sql + 1;
  end loop;

  return jsonb_build_object('mode', p_mode, 'dispatched', n_disp, 'reconciled_done', n_done, 'failed', n_fail,
                            'requeued', n_requeue, 'sql_jobs', n_sql,
                            'queued', (select count(*) from ripples.att_jobs where status = 'queued'),
                            'running', (select count(*) from ripples.att_jobs where status = 'running'));
end $$;

-- ---------- topic registry ----------
-- p_facts: {"label","label_en","title","title_en","lang","aliases":[...],"tickers":[...],"repos":[...],"npm":[...],
--           "pypi":[...],"domains":[...],"steam":[...],"anilist":[...],"apple":[...]}
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
    where a is not null and a is distinct from v_term and char_length(a) > 3 and not ripples.att_is_stopword(a)
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

-- Upsert a topic (by QID, else by 'lang:Title'), generate keys (§3.2) and enqueue backfill (via att_keys trigger).
-- p_keys: null -> term keys from the label + a 'resolve' job to att-registry for Wikidata aliases/properties;
--         json object -> facts for att_gen_keys; json array -> explicit keys [{source,key,key_type,metric?,geo?,match?}].
create or replace function ripples.att_register_topic(
  p_qid text, p_label text, p_origin text, p_category text default null, p_keys jsonb default null,
  p_status text default null, p_lang text default 'en', p_title text default null,
  p_in_panel boolean default false, p_meta jsonb default null) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint; v_qid text; v_lang text; v_title text; v_lk text; v_status text; v_title_en text; v_old record;
  v_facts jsonb;
begin
  if coalesce(btrim(p_label), '') = '' then raise exception 'att_register_topic: label required'; end if;
  if p_origin not in ('trend','hop','panel','manual','cascade') then raise exception 'att_register_topic: bad origin %', p_origin; end if;
  if p_status is not null and p_status not in ('active','panel','dormant','retired') then raise exception 'bad status %', p_status; end if;
  v_qid := nullif(upper(btrim(coalesce(p_qid, ''))), '');
  if v_qid is not null and v_qid !~ '^Q[0-9]+$' then raise exception 'att_register_topic: bad qid %', p_qid; end if;
  v_lang := coalesce(nullif(p_lang, ''), 'en');
  v_title := replace(btrim(coalesce(nullif(p_title, ''), p_label)), ' ', '_');
  v_lk := v_lang || ':' || v_title;
  v_title_en := coalesce(nullif(replace(coalesce(p_keys->>'title_en', p_meta->>'title_en'), ' ', '_'), ''),
                         case when v_lang = 'en' then v_title end);
  v_status := coalesce(p_status, case when p_origin = 'panel' then 'panel' else 'active' end);

  if v_qid is not null then select topic_id into v_id from ripples.att_topics where qid = v_qid; end if;
  if v_id is null then select topic_id into v_id from ripples.att_topics where label_key = v_lk; end if;

  if v_id is null then
    insert into ripples.att_topics(qid, label_key, label, title_en, lang, category, status, in_panel, origin, last_active, meta)
    values (v_qid, v_lk, p_label, v_title_en, v_lang, p_category, v_status, coalesce(p_in_panel, false), p_origin,
            case when v_status = 'active' then current_date end, coalesce(p_meta, '{}'::jsonb))
    on conflict do nothing
    returning topic_id into v_id;
    if v_id is null then
      select topic_id into v_id from ripples.att_topics where qid = v_qid or label_key = v_lk limit 1;
    end if;
  else
    select * into v_old from ripples.att_topics where topic_id = v_id;
    update ripples.att_topics t set
      qid = coalesce(t.qid, case when v_qid is not null and not exists
                                   (select 1 from ripples.att_topics x where x.qid = v_qid) then v_qid end),
      label = case when v_qid is not null and p_keys is not null then p_label else t.label end,
      title_en = coalesce(t.title_en, v_title_en),
      category = coalesce(p_category, t.category),
      status = case
        when p_status is not null and not (t.status = 'active' and p_status = 'panel') then p_status
        when p_status is null and v_status = 'active' then 'active'
        when p_status is null and t.status in ('dormant','retired') and v_status = 'panel' then 'panel'
        else t.status end,
      in_panel = t.in_panel or coalesce(p_in_panel, false),
      last_active = case when v_status = 'active' then current_date else t.last_active end,
      meta = t.meta || coalesce(p_meta, '{}'::jsonb)
    where t.topic_id = v_id;
  end if;

  insert into ripples.att_label_cache(label_norm, lang, qid, label_key, method, confidence)
  values (lower(v_title), v_lang, v_qid, v_lk, case when v_qid is null then 'miss' else 'wikidata' end,
          case when v_qid is null then 0 else 1 end)
  on conflict (label_norm, lang) do update set qid = coalesce(excluded.qid, ripples.att_label_cache.qid),
    label_key = excluded.label_key, method = case when excluded.qid is not null then excluded.method else ripples.att_label_cache.method end,
    resolved_at = now();

  if p_keys is not null and jsonb_typeof(p_keys) = 'array' then
    insert into ripples.att_keys(topic_id, source, metric, geo, key, key_type, match, weight, created_by)
    select v_id, x.source, coalesce(x.metric, 'n'), coalesce(x.geo, 'ALL'), x.key, x.key_type,
           coalesce(x.match, '{}'::jsonb), coalesce(x.weight, 1), coalesce(x.created_by, 'manual')
    from jsonb_to_recordset(p_keys) as x(source text, metric text, geo text, key text, key_type text, match jsonb,
                                          weight real, created_by text)
    join ripples.att_sources s on s.source = x.source
    where x.key is not null and x.key_type is not null
    on conflict do nothing;
    perform ripples.att_gen_keys(v_id, jsonb_build_object('label', p_label, 'lang', v_lang, 'title', v_title, 'title_en', v_title_en));
  else
    v_facts := coalesce(case when jsonb_typeof(p_keys) = 'object' then p_keys end, '{}'::jsonb)
               || jsonb_build_object('label', p_label, 'lang', v_lang, 'title', v_title, 'title_en', v_title_en);
    perform ripples.att_gen_keys(v_id, v_facts);
  end if;

  if p_keys is null and coalesce(p_meta->>'resolved', '') = ''
     and coalesce((select meta->>'resolved' from ripples.att_topics where topic_id = v_id), '') = '' then
    perform ripples.att_job_enqueue('resolve', 'att-registry',
      jsonb_build_object('mode', 'resolve', 'items', jsonb_build_array(jsonb_build_object(
        'qid', v_qid, 'title', v_title, 'lang', v_lang, 'origin', p_origin, 'status', p_status, 'category', p_category))),
      case when p_origin = 'hop' then 1 else 5 end, 'resolve:' || coalesce(v_qid, v_lk), 'resolve');
  end if;
  return v_id;
end $$;

-- batch form used by att-registry: items [{qid,label,origin,category,keys|facts,status,lang,title,in_panel,meta}]
create or replace function ripples.att_register_topics(p_items jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare it jsonb; v_ids jsonb := '[]'::jsonb; v_err jsonb := '[]'::jsonb; v_id bigint; n int := 0;
begin
  for it in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    begin
      v_id := ripples.att_register_topic(it->>'qid', it->>'label', coalesce(it->>'origin', 'manual'), it->>'category',
                coalesce(it->'keys', it->'facts'), it->>'status', coalesce(it->>'lang', 'en'), it->>'title',
                coalesce((it->>'in_panel')::boolean, false), it->'meta');
      v_ids := v_ids || to_jsonb(v_id);
    exception when others then
      v_err := v_err || jsonb_build_object('i', n, 'error', sqlerrm);
    end;
    n := n + 1;
  end loop;
  return jsonb_build_object('registered', jsonb_array_length(v_ids), 'topic_ids', v_ids, 'errors', v_err);
end $$;

-- keys a collector must query this run: active first, then the frozen panel; optional rotation slice
create or replace function ripples.att_watchlist(p_source text, p_limit int default 5000, p_slice int default null,
                                                  p_nslices int default 3)
returns table(key text, geo text, metric text, match jsonb, series_id bigint, topic_id bigint, key_type text)
language sql stable security definer set search_path = '' as $$
  select w.key, w.geo, w.metric, w.match, w.series_id, w.topic_id, w.key_type from (
    select distinct on (k.key, k.geo, k.metric) k.key, k.geo, k.metric, k.match, k.series_id, k.topic_id, k.key_type,
           (t.status = 'active') as act, t.last_active
    from ripples.att_keys k join ripples.att_topics t on t.topic_id = k.topic_id
    where k.source = p_source and k.enabled and (t.status = 'active' or t.in_panel)
      and (p_slice is null or mod(abs(hashtext(k.key)), greatest(p_nslices, 1)) = mod(p_slice - 1, greatest(p_nslices, 1)))
    order by k.key, k.geo, k.metric, (t.status = 'active') desc, k.topic_id) w
  order by w.act desc, w.last_active desc nulls last, w.topic_id
  limit greatest(p_limit, 0)
$$;

-- backfill jobs for history-capable sources whenever a key is added (§3.6 step 2)
create or replace function ripples._att_keys_backfill() returns trigger
language plpgsql security definer set search_path = '' as $$
declare s record; t record;
begin
  select * into s from ripples.att_sources where source = new.source and enabled and backfill_fn is not null;
  if not found then return null; end if;
  select * into t from ripples.att_topics where topic_id = new.topic_id;
  if not found or not (t.status = 'active' or t.in_panel) then return null; end if;
  if exists (select 1 from ripples.att_series x where x.source = new.source and x.metric = new.metric
             and x.geo = new.geo and x.key = new.key and x.last_day >= current_date - 3) then
    return null;                                   -- already fresh (e.g. ingested during the panel build)
  end if;
  perform ripples.att_job_enqueue('backfill', s.backfill_fn,
    jsonb_build_object('mode', 'backfill', 'params', jsonb_build_object('source', new.source),
      'keys', jsonb_build_array(jsonb_build_object('key', new.key, 'geo', new.geo, 'metric', new.metric,
                                                   'match', new.match, 'topic_id', new.topic_id)),
      'backfill', jsonb_build_object('from', current_date - 400, 'to', current_date - 1)),
    case when t.origin = 'hop' then 1 else 5 end,
    'backfill:' || new.source || ':' || new.metric || ':' || new.geo || ':' || new.key,
    'backfill:' || new.source);
  return null;
end $$;
drop trigger if exists att_keys_backfill on ripples.att_keys;
create trigger att_keys_backfill after insert on ripples.att_keys
  for each row execute function ripples._att_keys_backfill();

-- bootstrap candidates from the v4 tables (SKIP-filtered, not yet registered or already tried)
--   'active': public.signals articles (hop-0/hop) + public.wiki_top last 3 days (top 50 en, top 20 other langs)
--   'panel' : en titles from public.wiki_top history + en signals with their signal_obs baseline median in rnk
create or replace function ripples.att_bootstrap_candidates(p_what text default 'active', p_limit int default 2000)
returns table(lang text, title text, origin text, rnk int)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
begin
  if p_what = 'active' then
    return query
    with maxd as (select max(w.day) d from public.wiki_top w),
    c as (
      select split_part(s.project, '.', 1) lang, s.article title, 'cascade'::text origin, 0 rnk
      from public.signals s where s.kind = 'wikipedia_pageviews'
      union all
      select split_part(w.project, '.', 1), w.article, 'trend', min(w.rank)
      from public.wiki_top w, maxd
      where w.day > maxd.d - 3 and w.rank <= case when w.project = 'en.wikipedia' then 50 else 20 end
      group by 1, 2)
    select distinct on (c.lang, c.title) c.lang, c.title, c.origin, c.rnk from c
    where not ripples.att_skip_title(c.title)
      and not exists (select 1 from ripples.att_topics t where t.label_key = c.lang || ':' || c.title)
      and not exists (select 1 from ripples.att_label_cache l where l.label_norm = lower(c.title) and l.lang = c.lang)
    order by c.lang, c.title, (c.origin = 'cascade') desc, c.rnk
    limit p_limit;
  elsif p_what = 'panel' then
    return query
    with sig as (
      select s.article title,
             (percentile_cont(0.5) within group (order by o.value))::int med
      from public.signals s join public.signal_obs o on o.signal_id = s.id
      where s.project = 'en.wikipedia' and o.day between current_date - 112 and current_date - 22
      group by s.article having count(*) >= 28),
    c as (
      select 'en'::text lang, sig.title, 'signal'::text origin, sig.med rnk from sig
      union all
      select distinct 'en', w.article, 'wiki_top', null::int from public.wiki_top w where w.project = 'en.wikipedia')
    select distinct on (c.title) c.lang, c.title, c.origin, c.rnk from c
    where not ripples.att_skip_title(c.title)
    order by c.title, (c.origin = 'signal') desc
    limit p_limit;
  else
    raise exception 'att_bootstrap_candidates: unknown %', p_what;
  end if;
end $$;

-- delete wiki.pv series fetched while sizing the panel that did not make it into any topic
create or replace function ripples.att_panel_cleanup() returns int
language sql security definer set search_path = '' as $$
  with d as (
    delete from ripples.att_series s
    where s.source = 'wiki.pv' and s.topic_id is null
      and not exists (select 1 from ripples.att_keys k where k.series_id = s.series_id)
    returning 1)
  select count(*)::int from d
$$;

-- daily registry upkeep: active trend topics idle for 30 days -> dormant
create or replace function ripples.att_registry_maintain() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v int;
begin
  update ripples.att_topics set status = 'dormant'
   where status = 'active' and origin in ('trend','hop') and coalesce(last_active, first_seen) < current_date - 30;
  get diagnostics v = row_count;
  return jsonb_build_object('dormant', v);
end $$;

-- ---------- public wrappers (PostgREST path for edge functions; service_role only) ----------
create or replace function public.att_ingest(p_rows jsonb) returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_ingest(p_rows) $$;
create or replace function public.att_ingest(p_run jsonb, p_rows jsonb) returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_ingest(p_run, p_rows) $$;
create or replace function public.att_ingest_edges(p_rows jsonb) returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_ingest_edges(p_rows) $$;
create or replace function public.att_ingest_candidates(p_rows jsonb) returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_ingest_candidates(p_rows) $$;
create or replace function public.att_load_qid_map(p_rows jsonb) returns int
language sql security definer set search_path = '' as $$ select ripples.att_load_qid_map(p_rows) $$;
create or replace function public.att_take_budget(p_bucket text, p_n int) returns int
language sql security definer set search_path = '' as $$ select ripples.att_take_budget(p_bucket, p_n) $$;
create or replace function public.att_host_kill(p_host text, p_status int, p_source text default null) returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_host_kill(p_host, p_status, p_source) $$;
create or replace function public.att_state_get(p_k text) returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_state_get(p_k) $$;
create or replace function public.att_state_set(p_k text, p_v jsonb) returns void
language sql security definer set search_path = '' as $$ select ripples.att_state_set(p_k, p_v) $$;
create or replace function public.att_config_get(p_key text) returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_config_get(p_key) $$;
create or replace function public.att_run_start(p_fn text, p_mode text, p_detail jsonb default null) returns bigint
language sql security definer set search_path = '' as $$ select ripples.att_run_start(p_fn, p_mode, p_detail) $$;
create or replace function public.att_run_finish(p_run bigint, p_result jsonb) returns void
language sql security definer set search_path = '' as $$ select ripples.att_run_finish(p_run, p_result) $$;
create or replace function public.att_job_enqueue(p_kind text, p_fn text, p_payload jsonb, p_priority int default 5,
  p_dedupe text default null, p_batch_key text default null, p_not_before timestamptz default null) returns bigint
language sql security definer set search_path = '' as $$
  select ripples.att_job_enqueue(p_kind, p_fn, p_payload, p_priority, p_dedupe, p_batch_key, p_not_before) $$;
create or replace function public.att_jobs_done(p_jobs bigint[], p_status text, p_error text default null,
  p_not_before timestamptz default null) returns int
language sql security definer set search_path = '' as $$ select ripples.att_jobs_done(p_jobs, p_status, p_error, p_not_before) $$;
create or replace function public.att_register_topic(p_qid text, p_label text, p_origin text, p_category text default null,
  p_keys jsonb default null, p_status text default null, p_lang text default 'en', p_title text default null,
  p_in_panel boolean default false, p_meta jsonb default null) returns bigint
language sql security definer set search_path = '' as $$
  select ripples.att_register_topic(p_qid, p_label, p_origin, p_category, p_keys, p_status, p_lang, p_title, p_in_panel, p_meta) $$;
create or replace function public.att_register_topics(p_items jsonb) returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_register_topics(p_items) $$;
create or replace function public.att_watchlist(p_source text, p_limit int default 5000, p_slice int default null,
  p_nslices int default 3)
returns table(key text, geo text, metric text, match jsonb, series_id bigint, topic_id bigint, key_type text)
language sql security definer set search_path = '' as $$
  select * from ripples.att_watchlist(p_source, p_limit, p_slice, p_nslices) $$;
create or replace function public.att_bootstrap_candidates(p_what text default 'active', p_limit int default 2000)
returns table(lang text, title text, origin text, rnk int)
language sql security definer set search_path = '' as $$ select * from ripples.att_bootstrap_candidates(p_what, p_limit) $$;
create or replace function public.att_panel_cleanup() returns int
language sql security definer set search_path = '' as $$ select ripples.att_panel_cleanup() $$;

-- ---------- grants: service_role only ----------
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
