-- 27_att_keys_privacy_2026-09-25.sql
-- (1) Keyed sources (OWNER D-5 / D-10). Keys and the SEC contact email live only in Vault and are read at run time
--     through public.att_secret (service_role); nothing secret is written here.
--     sec.efts: enabled (att.ts adds the contact email to the UA for sec.gov hosts only; 500 ms spacing = 2 req/s
--               against SEC's published 10 req/s; existing 200/run, 200/day caps kept).
--     se.api:   app key 'stackexchange_key' (10,000/day keyed quota) -> 9000/day, 2000/run; spacing unchanged (5/s).
--     gh.*:     PAT 'github_token' (5000/h core, 30/min search) -> search 25/min (2400 ms), core ~4000/h (900 ms).
-- (2) att-news n10 privacy: public.att_news_qid_names() for the GKG readable-name test, and a purge of GKG discovery
--     candidates that are unresolved person-like names or junk (date fragments, quote-edged labels). The gkg.ewma
--     baseline is converted by att-news itself (unresolved keys -> salted digests) on its first n10 run.

-- ---------------------------------------------------------------- (1) keyed sources
update ripples.att_sources set enabled = true, reason = null, needs_secret = 'sec_contact_email'
 where source = 'sec.efts';

update ripples.att_sources set per_day_cap = 9000, per_run_cap = 2000, needs_secret = 'stackexchange_key',
       reason = 'keyed quota 10,000/day (app key from Vault) -> 9000/day, 2000/run; 30 req/s -> 5/s; honours backoff'
 where source = 'se.api';

update ripples.att_sources set spacing_ms = 2400, per_run_cap = 25, per_day_cap = 2000, needs_secret = 'github_token',
       reason = 'authenticated (PAT from Vault, api.github.com only): search 30/min -> 25/min'
 where source = 'gh.search';

update ripples.att_sources set spacing_ms = 900, per_run_cap = 4000, per_day_cap = 40000, needs_secret = 'github_token',
       reason = 'authenticated (PAT from Vault, api.github.com only): core 5000/h -> ~4000/h (900 ms spacing, one run per host)'
 where source = 'gh.stars';

-- today's budget rows were created with the old caps
update ripples.att_budget b set cap = s.per_day_cap
  from ripples.att_sources s
 where s.source = b.bucket and b.bucket in ('se.api', 'gh.search', 'gh.stars', 'sec.efts')
   and b.day = (now() at time zone 'utc')::date and not b.killed;

-- stackex mode's own per-run request cap (att_config social.se_daily_cap) follows the new per-run cap
update ripples.att_config set value = jsonb_set(value, '{se_daily_cap}', '2000'::jsonb) where key = 'social';

-- ---------------------------------------------------------------- (2) readable-name test for att-news GKG
-- Labels and titles with a Wikidata QID: registry topics and the resolve path's title map. att-news normalises them.
create or replace function public.att_news_qid_names()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_array(x, qid)), '[]'::jsonb) from (
    select distinct on (x) x, qid from (
      select label x, qid from ripples.att_topics where qid is not null and label is not null
      union all select replace(title_en, '_', ' '), qid from ripples.att_topics where qid is not null and title_en is not null
      union all select replace(title, '_', ' '), qid from ripples.title_map where qid is not null and title is not null
      union all select replace(title_en, '_', ' '), qid from ripples.title_map where qid is not null and title_en is not null
    ) z where length(x) between 3 and 200 order by x, qid) d;
$$;
revoke all on function public.att_news_qid_names() from public, anon, authenticated;
grant execute on function public.att_news_qid_names() to service_role;

-- SQL approximation of att-news norm() (lower case, non letter/digit runs -> one space)
create or replace function ripples._att_name_norm(p text)
returns text language sql immutable set search_path = '' as $$
  select btrim(regexp_replace(lower(p), '[^[:alnum:]]+', ' ', 'g'));
$$;

-- purge: unresolved person-like GKG candidates, date fragments and quote-edged labels
with q as (
  select ripples._att_name_norm(x) k from (
    select label x from ripples.att_topics where qid is not null
    union select replace(title_en, '_', ' ') from ripples.att_topics where qid is not null and title_en is not null
    union select replace(title, '_', ' ') from ripples.title_map where qid is not null
    union select replace(title_en, '_', ' ') from ripples.title_map where qid is not null and title_en is not null) z)
delete from ripples.att_trend_candidates c
 where c.source = 'gdelt.gkg'
   and ((coalesce(c.meta->>'k', 'name') in ('person', 'name') and ripples._att_name_norm(c.label) not in (select k from q))
     or ripples._att_name_norm(c.label) ~ '^((monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec|mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|today|yesterday|tomorrow|tonight|morning|afternoon|evening|night|week|weekend|last|next|this|early|late|mid|of|the|on|st|nd|rd|th|[0-9]{1,4}(st|nd|rd|th)?)( |$))+$'
        and ripples._att_name_norm(c.label) ~ '(^| )(monday|tuesday|wednesday|thursday|friday|saturday|sunday|january|february|march|april|may|june|july|august|september|october|november|december)( |$)'
     or btrim(c.label) ~ '^[''"‘’‚‛“”„«»`´]|[''"‘’‚‛“”„«»`´]$');

-- (3) att_news_candidates_merge: keep the QID att-news now sends (n10) on re-merge of an existing candidate row
create or replace function ripples.att_news_candidates_merge(p_rows jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v int; v_stop text[]; v_re text[];
begin
  select coalesce(array_agg(lower(x)), '{}') into v_stop
    from jsonb_array_elements_text(coalesce(ripples._att_cfg('news_candidate_stoplist'), '[]'::jsonb)) x;
  select coalesce(array_agg(x), '{}') into v_re
    from jsonb_array_elements_text(coalesce(ripples._att_cfg('news_entity_stop_regex'), '[]'::jsonb)) x;
  with c as (
    select distinct on (x.day, x.source, coalesce(x.geo, 'ALL'), x.label) x.*
    from jsonb_to_recordset(p_rows) as x(day date, source text, geo text, label text, rank int, value double precision,
                                          evidence real, qid text, topic_id bigint, meta jsonb)
    join ripples.att_sources s on s.source = x.source and s.enabled
    where x.day is not null and x.label is not null and x.evidence between 0 and 1 and length(x.label) <= 200
      and not ripples._att_ident_like(x.label, x.source, true)
      and not ripples._att_news_stop(x.label, v_stop, v_re)
    order by x.day, x.source, coalesce(x.geo, 'ALL'), x.label, x.evidence desc),
  up as (
    insert into ripples.att_trend_candidates as t (day, source, geo, label, rank, value, evidence, qid, topic_id, meta)
    select day, source, coalesce(geo, 'ALL'), label, rank, value, evidence, qid, topic_id, ripples._att_clean_meta(meta) from c
    on conflict (day, source, geo, label) do update
      set evidence = greatest(t.evidence, excluded.evidence),
          value = greatest(t.value, excluded.value),
          rank = least(t.rank, excluded.rank),
          qid = coalesce(excluded.qid, t.qid),
          topic_id = coalesce(excluded.topic_id, t.topic_id),
          meta = case when excluded.evidence >= t.evidence then excluded.meta else t.meta end,
          observed_at = now()
    returning 1)
  select count(*) into v from up;
  return jsonb_build_object('rows', v, 'rejected', jsonb_array_length(p_rows) - v);
end $function$;
