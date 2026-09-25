-- Knock-On v5 / W2: migration ripples_v5_pipeline_yield (after the 2026-09-23 / 2026-09-24 practice runs were delayed)
-- 1. Decoy reserve: ripples-expand may test extra median-matched outlinks of a real parent with its leftover budget.
--    They are stored in ripples.candidates with extra = true and are never counted as tested (fluke rates), never a
--    hop, never a beam parent, never in the shared-trigger test and never in the Board's fixed K=20 wake set
--    (set_rank is null). They can only be picked as calm decoys (the §5.2 calm rules are unchanged).
-- 2. Fluke rates: adjacent S-bins that violate monotonicity (a higher-S bin with a higher decoy/real ratio, or a bin
--    with no real passes) are pooled (pool-adjacent-violators on the summed counts). Raw per-bin counts stay stored.
-- 3. Safety: blocklist gains desc_pattern (Wikipedia short description, case-insensitive): people known for killing
--    or violent crime, murder / massacre / terrorism / suicide topics, pornographic performers.
-- 4. Seeds: the baseline median must be >= config.pipeline.seed_min_median (50 views/day); a brand-new page with a
--    zero baseline has no meaningful "x normal" multiple.

alter table ripples.candidates add column if not exists extra boolean not null default false;
alter table ripples.fluke_rates add column if not exists fluke_bins text;
alter table ripples.blocklist add column if not exists desc_pattern text;
alter table ripples.blocklist drop constraint if exists blocklist_check;
alter table ripples.blocklist drop constraint if exists blocklist_target_check;
alter table ripples.blocklist add constraint blocklist_target_check
  check (qid is not null or title_pattern is not null or desc_pattern is not null);
drop index if exists ripples.blocklist_uq;
create unique index blocklist_uq on ripples.blocklist (coalesce(qid, ''), coalesce(title_pattern, ''), coalesce(desc_pattern, ''));

insert into ripples.blocklist (desc_pattern, reason, action) values
  ('(^|[^a-z])(serial killer|spree killer|mass murderer|murderer|mass shooter|gunman|terrorist|rapist|cannibal|sex offender|child molester|war criminal|assassin|body snatcher|hitman|contract killer|cult leader|mobster|gangster|drug lord)s?([^a-z]|$)',
   'violence: person known for killing or violent crime (short description)', 'block'),
  ('(^|[^a-z])(murders?|murdered|killings?|killed|massacres?|homicides?|genocide|terrorism|terrorist attack|mass shooting|school shooting|bombing|suicide|lynching|manslaughter)([^a-z]|$)',
   'violence/suicide topic (short description)', 'block'),
  ('(^|[^a-z])(pornographic|pornography|porn|adult film|adult video|erotic model|onlyfans)([^a-z]|$)',
   'sexual/adult (short description)', 'block')
on conflict do nothing;

update ripples.config set value = value || '{"seed_min_median":50,"extra_decoys":true,"extra_decoys_max":30}'::jsonb
 where key = 'pipeline';

-- ------------------------------------------------------------------ safety
create or replace function ripples._refresh_articles(p_qids text[]) returns int
language plpgsql security definer set search_path = '' as $$
declare r record; k int := 0; c record; tflag text; treason text; bq text; dreason text;
begin
  for r in select * from ripples.articles where qid = any(p_qids) loop
    select * into c from ripples._classify(r.p31, r.short_desc);
    tflag := null; treason := null; bq := null; dreason := null;
    select b.action, b.reason into tflag, treason from ripples.blocklist b
     where b.title_pattern is not null and r.title_en ~* b.title_pattern order by (b.action = 'block') desc limit 1;
    select b.reason into bq from ripples.blocklist b where b.qid = r.qid and b.action = 'block' limit 1;
    select b.reason into dreason from ripples.blocklist b
     where b.desc_pattern is not null and b.action = 'block' and coalesce(r.short_desc, '') ~* b.desc_pattern limit 1;
    update ripples.articles a set
      category    = c.category,
      emoji       = ripples._emoji(c.category),
      is_human    = 'Q5' = any(r.p31),
      is_list     = r.is_list or 'Q13406463' = any(r.p31)
                    or r.title_en ~* '^(lists? of|index of|outline of|timeline of|glossary of|deaths in|bibliography of|discography of) '
                    or r.title_en ~ '^[0-9]{1,4}s?( BC| AD| BCE| CE)?$' or r.title_en ~ '^[0-9]{4}s? in ',
      is_disambig = r.is_disambig or 'Q4167410' = any(r.p31) or r.title_en ~* '\(disambiguation\)$',
      sensitive   = coalesce(c.flag = 'sensitive', false) or coalesce(tflag = 'sensitive', false)
                    or exists (select 1 from ripples.blocklist b where b.qid = r.qid and b.action = 'sensitive'),
      blocked     = coalesce(c.flag = 'block', false) or coalesce(tflag = 'block', false) or bq is not null or dreason is not null,
      block_reason = coalesce(case when bq is not null then 'blocklist: ' || bq end,
                              case when tflag = 'block' then 'title: ' || treason end,
                              case when dreason is not null then 'description: ' || dreason end,
                              case when c.flag = 'block' then c.flag_reason end,
                              case when c.flag = 'sensitive' or tflag = 'sensitive' then 'sensitive: ' || coalesce(c.flag_reason, treason) end)
     where a.qid = r.qid;
    k := k + 1;
  end loop;
  return k;
end $$;

create or replace function ripples._safe(p_qid text, p_as_of date, p_median numeric default null, p_allow_sensitive boolean default false)
returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select not a.blocked and not a.is_disambig and not a.is_list
       and (p_allow_sensitive or not a.sensitive)
       and (a.date_of_death is null or a.date_of_death < p_as_of - 60)
       and not (a.is_human and coalesce(a.sitelinks, 0) <= 1 and coalesce(p_median, 0) < 20)
       and a.category is not null
       and not exists (select 1 from ripples.blocklist b where b.title_pattern is not null and b.action = 'block' and a.title_en ~* b.title_pattern)
       and not exists (select 1 from ripples.blocklist b where b.desc_pattern is not null and b.action = 'block' and coalesce(a.short_desc, '') ~* b.desc_pattern)
       and not exists (select 1 from ripples.blocklist b where b.qid = a.qid and b.action = 'block')
       and (p_allow_sensitive or not exists (select 1 from ripples.blocklist b where b.title_pattern is not null and b.action = 'sensitive' and a.title_en ~* b.title_pattern))
      from ripples.articles a where a.qid = p_qid), false)
$$;

-- ------------------------------------------------------------------ decoy reserve rows are not hops
create or replace function ripples._shared_trigger(c ripples.candidates) returns boolean
language sql stable security definer set search_path = '' as $$
  select c.depth >= 2 and (
    exists (select 1 from ripples.candidates d where d.as_of = c.as_of and d.role = 'real' and d.root_qid = c.root_qid
              and d.depth = 1 and d.qid = c.qid and not d.extra)
    or exists (select 1 from ripples.candidates o
                 join ripples.seeds so on so.as_of = o.as_of and so.qid = o.root_qid and so.role = 'real'
                 join ripples.seeds sc on sc.as_of = c.as_of and sc.qid = c.root_qid and sc.role = 'real'
                where o.as_of = c.as_of and o.role = 'real' and o.root_qid <> c.root_qid and o.qid = c.qid and o.pass_raw
                  and not o.extra and so.onset < sc.onset))
$$;

create or replace function ripples._pre_eligible(c ripples.candidates) returns boolean
language sql stable security definer set search_path = '' as $$
  select c.role = 'real' and not c.extra and c.pass_raw and c.p_time <= 0.05 and c.multiple >= 1.5 and coalesce(c.onset_lag, -1) >= 0
     and not c.main_page and c.linked
     and (select fl.warming or fl.f <= 0.10 from ripples._fluke(c.as_of, c.s_stat) fl)
     and ripples._safe(c.qid, c.as_of, c.median_views, false)
     and (c.depth = 1 or not ripples._shared_trigger(c))
$$;

-- Edge write path for screen / expand / split / refresh jobs (dispatch on the job's kind). expand rows may carry
-- extra = true (decoy reserve).
create or replace function public.ripples_ingest_candidates(p_job bigint, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare j ripples.jobs; k int := 0; need text[];
begin
  select * into j from ripples.jobs where id = p_job;
  if not found then raise exception 'unknown job %', p_job; end if;
  if j.kind = 'screen' then
    insert into ripples.screen (as_of, qid, title, median_views, onset, z_peak, peak_multiple, peak_day, max_abs_z14, base_from, base_to, spark)
    select distinct on (x.qid) j.as_of, x.qid, x.title, x.median_views, x.onset, x.z_peak, x.peak_multiple, x.peak_day, x.max_abs_z14, x.base_from, x.base_to, x.spark
      from jsonb_to_recordset(coalesce(p_rows, '[]')) as x(qid text, title text, median_views numeric, onset date, z_peak numeric,
           peak_multiple numeric, peak_day date, max_abs_z14 numeric, base_from date, base_to date, spark int[])
     where x.qid ~ '^Q[0-9]+$'
    on conflict (as_of, qid) do update set title = excluded.title, median_views = excluded.median_views, onset = excluded.onset,
      z_peak = excluded.z_peak, peak_multiple = excluded.peak_multiple, peak_day = excluded.peak_day,
      max_abs_z14 = excluded.max_abs_z14, base_from = excluded.base_from, base_to = excluded.base_to, spark = excluded.spark;
    get diagnostics k = row_count;
    return jsonb_build_object('inserted', k);
  elsif j.kind = 'expand' then
    insert into ripples.candidates (as_of, role, root_qid, depth, parent_qid, qid, title, cs_rank, cs_clicks, set_rank, linked,
      median_views, s_stat, onset_lag, multiple, p_time, n_placebo, pass_raw, calm, max_abs_z, spark, main_page, category, job_id, extra)
    select distinct on (x.qid) j.as_of, j.role, j.root_qid, j.depth, j.parent_qid, x.qid, x.title, x.cs_rank, x.cs_clicks, x.set_rank, coalesce(x.linked, true),
           x.median_views, x.s_stat, x.onset_lag, x.multiple, x.p_time, x.n_placebo, coalesce(x.pass_raw, false), coalesce(x.calm, false),
           x.max_abs_z, x.spark,
           -- Main Page feature (TFA / DYK / On this day / In the news) within ±1 day of the candidate's onset
           exists (select 1 from ripples.trend_obs t where t.source = 'featured' and t.geo in ('tfa','dyk','onthisday','news')
                     and (t.qid = x.qid or (t.lang = 'en' and t.query = x.title))
                     and t.day between j.parent_onset + coalesce(x.onset_lag, 0) - 1 and j.parent_onset + coalesce(x.onset_lag, 0) + 1),
           (select a.category from ripples.articles a where a.qid = x.qid), j.id,
           coalesce(x.extra, false) and j.role = 'real'
      from jsonb_to_recordset(coalesce(p_rows, '[]')) as x(qid text, title text, cs_rank int, cs_clicks int, set_rank int, linked boolean,
           median_views numeric, s_stat numeric, onset_lag int, multiple numeric, p_time numeric, n_placebo int, pass_raw boolean,
           calm boolean, max_abs_z numeric, spark int[], extra boolean)
     where x.qid ~ '^Q[0-9]+$'
     order by x.qid, coalesce(x.extra, false)          -- a fixed-set row wins over a reserve row for the same page
    on conflict (as_of, role, root_qid, parent_qid, qid) do update set title = excluded.title, cs_rank = excluded.cs_rank,
      cs_clicks = excluded.cs_clicks, set_rank = excluded.set_rank, linked = excluded.linked, median_views = excluded.median_views,
      s_stat = excluded.s_stat, onset_lag = excluded.onset_lag, multiple = excluded.multiple, p_time = excluded.p_time,
      n_placebo = excluded.n_placebo, pass_raw = excluded.pass_raw, calm = excluded.calm, max_abs_z = excluded.max_abs_z,
      spark = excluded.spark, main_page = excluded.main_page, job_id = excluded.job_id, extra = excluded.extra;
    get diagnostics k = row_count;
    select array_agg(distinct c.qid) into need from ripples.candidates c
     where c.job_id = j.id and (c.pass_raw or c.calm)
       and not exists (select 1 from ripples.articles a where a.qid = c.qid and a.updated_at > now() - interval '30 days');
    return jsonb_build_object('inserted', k, 'need_articles', to_jsonb(coalesce(need, '{}')));
  elsif j.kind = 'split' then
    update ripples.candidates c set mult_desktop = x.mult_desktop, mult_mobile = x.mult_mobile,
           split_ok = coalesce(x.mult_desktop >= 1.3 and x.mult_mobile >= 1.3, false)
      from jsonb_to_recordset(coalesce(p_rows, '[]')) as x(parent_qid text, qid text, mult_desktop numeric, mult_mobile numeric)
     where c.as_of = j.as_of and c.role = 'real' and c.root_qid = j.root_qid and c.parent_qid = x.parent_qid and c.qid = x.qid;
    get diagnostics k = row_count;
    return jsonb_build_object('updated', k);
  elsif j.kind = 'refresh' then
    update ripples.callit c set max_z = x.max_z, outcome = case when x.hit then 'hit' else 'miss' end, resolved_at = now()
      from jsonb_to_recordset(coalesce(p_rows, '[]')) as x(n int, qid text, max_z numeric, hit boolean)
     where c.n = x.n and c.qid = x.qid and c.outcome = 'pending' and x.max_z is not null;
    get diagnostics k = row_count;
    return jsonb_build_object('resolved', k);
  end if;
  raise exception 'job kind % has no candidate rows', j.kind;
end $$;

-- ------------------------------------------------------------------ fluke rates (SPEC §5.2, pooled over 90 days)
-- f_b = min(1, (decoy_pass_b / decoy_tested) / (real_pass_b / real_tested)) on the trailing-90-day sums; adjacent bins
-- that violate "a higher S is no more fluky" (or a bin with no real passes) are pooled by summing their counts
-- (pool-adjacent-violators). fluke_bins records the pooled range. Decoy-reserve rows (extra) are never counted.
create or replace function public.ripples_update_fluke(p_as_of date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare rt int; dt int; bins text[] := array['3-4','4-6','6-10','10+']; rp int[] := '{}'; dp int[] := '{}';
        prt int; pdt int; bs int[] := '{}'; be int[] := '{}'; brp int[] := '{}'; bdp int[] := '{}'; nb int; i int; f1 numeric; f0 numeric;
begin
  select count(*) filter (where role = 'real' and not extra), count(*) filter (where role = 'decoy' and not extra) into rt, dt
    from ripples.candidates where as_of = p_as_of;
  insert into ripples.fluke_rates (as_of, sbin, real_tested, real_pass, decoy_tested, decoy_pass, fluke,
                                   d_real_tested, d_real_pass, d_decoy_tested, d_decoy_pass)
  select p_as_of, b.sbin, 0, 0, 0, 0, null, rt,
         (select count(*) from ripples.candidates c where c.as_of = p_as_of and c.role = 'real' and not c.extra and c.pass_raw and ripples._sbin(c.s_stat) = b.sbin),
         dt,
         (select count(*) from ripples.candidates c where c.as_of = p_as_of and c.role = 'decoy' and not c.extra and c.pass_raw and ripples._sbin(c.s_stat) = b.sbin)
    from unnest(bins) b(sbin)
  on conflict (as_of, sbin) do update set d_real_tested = excluded.d_real_tested, d_real_pass = excluded.d_real_pass,
    d_decoy_tested = excluded.d_decoy_tested, d_decoy_pass = excluded.d_decoy_pass;
  -- trailing 90-day sums per bin
  update ripples.fluke_rates f set real_tested = p.rt, real_pass = p.rp, decoy_tested = p.dt, decoy_pass = p.dp
    from (select sbin, sum(d_real_tested)::int rt, sum(d_real_pass)::int rp, sum(d_decoy_tested)::int dt, sum(d_decoy_pass)::int dp
            from ripples.fluke_rates where as_of between p_as_of - 89 and p_as_of group by sbin) p
   where f.as_of = p_as_of and f.sbin = p.sbin;
  select max(real_tested), max(decoy_tested) into prt, pdt from ripples.fluke_rates where as_of = p_as_of;
  for i in 1..4 loop
    rp := rp || coalesce((select real_pass from ripples.fluke_rates where as_of = p_as_of and sbin = bins[i]), 0);
    dp := dp || coalesce((select decoy_pass from ripples.fluke_rates where as_of = p_as_of and sbin = bins[i]), 0);
  end loop;
  -- pool adjacent violators
  for i in 1..4 loop
    bs := bs || i; be := be || i; brp := brp || rp[i]; bdp := bdp || dp[i];
    loop
      nb := cardinality(bs);
      exit when nb < 2;
      f1 := case when brp[nb] > 0 and prt > 0 and pdt > 0 then (bdp[nb]::numeric / pdt) / (brp[nb]::numeric / prt) end;
      f0 := case when brp[nb - 1] > 0 and prt > 0 and pdt > 0 then (bdp[nb - 1]::numeric / pdt) / (brp[nb - 1]::numeric / prt) end;
      exit when f1 is not null and f0 is not null and f1 <= f0;
      exit when pdt is null or pdt = 0;
      be[nb - 1] := be[nb]; brp[nb - 1] := brp[nb - 1] + brp[nb]; bdp[nb - 1] := bdp[nb - 1] + bdp[nb];
      bs := bs[1:nb - 1]; be := be[1:nb - 1]; brp := brp[1:nb - 1]; bdp := bdp[1:nb - 1];
    end loop;
  end loop;
  for i in 1..cardinality(bs) loop
    update ripples.fluke_rates set
      fluke = case when brp[i] > 0 and prt > 0 and pdt > 0 then least(1, (bdp[i]::numeric / pdt) / (brp[i]::numeric / prt)) end,
      fluke_bins = case when bs[i] = be[i] then bins[bs[i]] else bins[bs[i]] || '..' || bins[be[i]] end
     where as_of = p_as_of and sbin = any(bins[bs[i]:be[i]]);
  end loop;
  return (select jsonb_agg(jsonb_build_object('sbin', sbin, 'real_tested', real_tested, 'real_pass', real_pass,
            'decoy_tested', decoy_tested, 'decoy_pass', decoy_pass, 'fluke', round(fluke, 4), 'pooled', fluke_bins) order by sbin)
            from ripples.fluke_rates where as_of = p_as_of);
end $$;

-- ------------------------------------------------------------------ seeds
-- SPEC §5.2: real seeds (top 12 by sources count, z_peak) and 8 decoy epicenters matched on baseline-median decile
-- and category with |z| < 1 over the last 14 days. Enqueues depth-1 expand jobs (real + decoy) and one history job.
-- A seed's baseline median must be >= config.pipeline.seed_min_median (a new page has no meaningful multiple).
create or replace function public.ripples_pick_seeds(p_as_of date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare nreal int := ripples._pcfg('seeds_real', 12); ndec int := ripples._pcfg('seeds_decoy', 8); r record; d record;
        used text[] := '{}'; kr int := 0; kd int := 0; hist jsonb; minmed numeric := ripples._pcfg('seed_min_median', 50);
begin
  delete from ripples.seeds where as_of = p_as_of;
  -- real seeds
  insert into ripples.seeds (as_of, qid, role, title, onset, peak_multiple, z_peak, median_views, langs, sources, spark, baseline, rank)
  select p_as_of, x.qid, 'real', x.title_en, x.onset, x.peak_multiple, x.z_peak, x.median_views, x.langs, x.sources, x.spark,
         jsonb_build_object('from', x.base_from, 'to', x.base_to, 'median', round(x.median_views)), x.rk
    from (
      select s.*, a.title_en, ss.langs, ss.sources, row_number() over (order by ss.nsrc desc, s.z_peak desc, s.qid) rk
        from ripples.screen s
        join ripples.articles a on a.qid = s.qid
        join ripples._seed_sources(p_as_of) ss on ss.qid = s.qid
       where s.as_of = p_as_of and s.onset is not null and s.peak_multiple >= 3
         and s.median_views >= minmed
         and ripples._safe(s.qid, p_as_of, s.median_views, true)
         -- not a puzzle seed in the last 30 days
         and not exists (select 1 from ripples.puzzles p
                          where p.kind in ('live','practice') and p.data_date between p_as_of - 30 and p_as_of - 1
                            and (p.payload->'seed'->>'qid' = s.qid
                                 or exists (select 1 from jsonb_array_elements(p.payload->'rounds') rr where rr->'seed'->>'qid' = s.qid)))
         -- not only a Main Page feature (TFA / DYK / OTD on the onset day with fewer than 2 other sources)
         and not (exists (select 1 from ripples.trend_obs t
                           where t.source = 'featured' and t.geo in ('tfa','dyk','onthisday') and t.day = s.onset
                             and (t.qid = s.qid or t.query = a.title_en))
                  and (select count(*) from unnest(ss.sources) src where src not like 'featured:%') < 2)
    ) x
   where x.rk <= nreal;
  get diagnostics kr = row_count;

  -- decoy epicenters: calm screened pages, matched 1:1 to the top real seeds on median decile and category
  for r in
    with pool as (
      select s.qid, s.title, s.median_views, a.category, ntile(10) over (order by s.median_views) dec
        from ripples.screen s join ripples.articles a on a.qid = s.qid
       where s.as_of = p_as_of and s.median_views is not null)
    select se.qid, se.onset, p.dec, a.category from ripples.seeds se
      join ripples.articles a on a.qid = se.qid
      left join pool p on p.qid = se.qid
     where se.as_of = p_as_of and se.role = 'real' order by se.rank limit ndec
  loop
    select c.* into d from (
      select s.qid, s.title, s.median_views, a.category, ntile(10) over (order by s.median_views) dec, s.max_abs_z14
        from ripples.screen s join ripples.articles a on a.qid = s.qid
       where s.as_of = p_as_of and s.median_views is not null) c
     where c.max_abs_z14 < 1 and not (c.qid = any(used))
       and not exists (select 1 from ripples.seeds x where x.as_of = p_as_of and x.qid = c.qid)
       and ripples._safe(c.qid, p_as_of, c.median_views, false)
     order by abs(c.dec - coalesce(r.dec, 5)), (c.category is distinct from r.category), c.qid
     limit 1;
    if found then
      insert into ripples.seeds (as_of, qid, role, title, onset, median_views, matched_to, rank)
      values (p_as_of, d.qid, 'decoy', d.title, r.onset, d.median_views, r.qid, kd + 1);
      used := used || d.qid;
      kd := kd + 1;
    end if;
  end loop;

  -- depth-1 expand jobs (identical code for real and decoy) + one history job for the real seeds
  for r in select s.*, a.title_en from ripples.seeds s join ripples.articles a on a.qid = s.qid
            where s.as_of = p_as_of order by (s.role = 'decoy'), s.rank loop
    perform ripples._enqueue(p_as_of, 'expand', r.role, r.qid, r.qid, r.title_en, r.onset, 1, '{}');
  end loop;
  select jsonb_agg(jsonb_build_object('qid', s.qid, 'title', a.title_en, 'onset', s.onset, 'as_of', p_as_of) order by s.rank)
    into hist from ripples.seeds s join ripples.articles a on a.qid = s.qid where s.as_of = p_as_of and s.role = 'real';
  if hist is not null then
    perform ripples._enqueue(p_as_of, 'history', 'real', null, null, null, null, null, jsonb_build_object('items', hist));
  end if;
  return jsonb_build_object('real', kr, 'decoy', kd);
end $$;

do $$
declare f text;
begin
  foreach f in array array['public.ripples_ingest_candidates(bigint, jsonb)', 'public.ripples_update_fluke(date)',
                           'public.ripples_pick_seeds(date)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- re-derive the safety flags of every stored article with the new description rules
select ripples._refresh_articles(array(select qid from ripples.articles));
