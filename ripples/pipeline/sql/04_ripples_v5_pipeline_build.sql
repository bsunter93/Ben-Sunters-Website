-- Knock-On v5 / W2: migration ripples_v5_pipeline_build
-- Puzzle composition (SPEC §5.3) and rendering into the W1 contract shapes (SPEC §10.2 + the `cross` extension).

-- Different title stem: neither base title contains the other and the first two words differ.
create or replace function ripples._stem_ok(a text, b text) returns boolean
language sql immutable set search_path = '' as $$
  with x as (
    select regexp_replace(lower(regexp_replace(coalesce(a, ''), '\s*\([^)]*\)\s*$', '')), '^the ', '') a1,
           regexp_replace(lower(regexp_replace(coalesce(b, ''), '\s*\([^)]*\)\s*$', '')), '^the ', '') b1)
  select a1 <> '' and b1 <> '' and strpos(a1, b1) = 0 and strpos(b1, a1) = 0
     and array_to_string((regexp_split_to_array(a1, '\s+'))[1:2], ' ') <> array_to_string((regexp_split_to_array(b1, '\s+'))[1:2], ' ')
    from x
$$;

-- Three calm decoys for the hop (as_of, root, parent -> answer): calm, linked, safe siblings with median within
-- 0.5-2x the answer's (on the rounded medians that are published), a different title stem, at least 2 of 3 sharing the
-- answer's category (same-category first, then the closest median). null when the hop cannot be a round.
create or replace function ripples._pick_decoys(p_as_of date, p_root text, p_parent text, p_answer text, p_exclude text[])
returns text[]
language sql stable security definer set search_path = '' as $$
  with ans as (
    select c.qid, round(c.median_views) med, a.category, a.title_en
      from ripples.candidates c join ripples.articles a on a.qid = c.qid
     where c.as_of = p_as_of and c.role = 'real' and c.root_qid = p_root and c.parent_qid = p_parent and c.qid = p_answer
  ), sib as (
    select c.qid, (a.category = ans.category) same_cat,
           abs(ln(greatest(round(c.median_views), 1) / greatest(ans.med, 1))) dist
      from ans
      join ripples.candidates c on c.as_of = p_as_of and c.role = 'real' and c.root_qid = p_root and c.parent_qid = p_parent
      join ripples.articles a on a.qid = c.qid
     where c.qid <> ans.qid and c.calm and c.linked and c.spark is not null
       and abs(coalesce(c.max_abs_z, 9)) < 1 and c.multiple < 1.25
       and not (c.qid = any(coalesce(p_exclude, '{}')))
       and round(c.median_views) >= 0.5 * ans.med and round(c.median_views) <= 2 * ans.med
       and ripples._stem_ok(a.title_en, ans.title_en)
       and ripples._safe(c.qid, p_as_of, c.median_views, false)
  ), ranked as (
    select qid, same_cat, row_number() over (order by same_cat desc, dist, qid) rn from sib
  )
  select case when (select count(*) from ranked where same_cat) >= 2 and (select count(*) from ranked) >= 3
              then array(select qid from ranked order by rn limit 3) end
$$;

-- Caption template (source 'template'): measured facts only, SPEC 12.1 wording ("linked from", "spiked after",
-- "alongside"); no reader-flow or causal words.
create or replace function ripples._caption(p_answer text, p_parent text, p_mult numeric, p_lag int) returns text
language sql immutable set search_path = '' as $$
  with t as (select case when p_lag = 0 then 'alongside it' when p_lag = 1 then '1 day after it'
                         else p_lag || ' days after it' end tm,
                    trim(to_char(round(p_mult, 1), 'FM9999990.0')) m)
  select case when length(x) <= 140 then x
              else left('Linked from ' || p_parent || '; spiked ' || t.tm || ' at ' || t.m || '× its usual daily views.', 200) end
    from t, lateral (select p_answer || ' is linked from the ' || p_parent || ' article and spiked ' || t.tm || ': '
                            || t.m || '× its usual daily views.' x) y
$$;

-- Render a composition into ripples.puzzles / callit / copy.
-- p_rounds: [{"root","parent","qid","depth","continues","decoys":[q,q,q]}...]; data comes from p_data_as_of,
-- the Board from p_board_as_of (today's trends even when the rounds come from the reserve bank).
create or replace function ripples._render(p_n int, p_kind text, p_date date, p_data_as_of date, p_board_as_of date,
  p_from_date date, p_rounds jsonb, p_end text, p_chain_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  seed record; rr jsonb; i int := 0; v_rounds int := jsonb_array_length(p_rounds);
  rounds_p jsonb := '[]'; rounds_r jsonb := '[]'; answers jsonb := '[]'; caps jsonb := '[]';
  ans record; par record; opt record; opts_p jsonb; opts_r jsonb; ids text[] := array['a','b','c','d']; k int;
  fl record; cs_month text; used text[] := '{}'; callit jsonb := null; callopts jsonb; ws date; we date;
  clim numeric := coalesce((ripples._cfg('callit_climatology') #>> '{}')::numeric, 0.08);
  mult jsonb := coalesce(ripples._cfg('callit_cs_mult'), '{}');
  payload jsonb; reveal jsonb; board jsonb; why jsonb; badges jsonb; headline text; final_m numeric; answer_id text;
  st_stop boolean; mini jsonb; parent_obj jsonb;
begin
  select s.*, a.title_en, a.category, a.emoji, a.short_desc into seed
    from ripples.seeds s join ripples.articles a on a.qid = s.qid
   where s.as_of = p_data_as_of and s.role = 'real' and s.qid = p_rounds->0->>'root';
  if not found then raise exception 'render: seed % missing', p_rounds->0->>'root'; end if;
  if to_regclass('ripples.clickstream') is not null then
    execute 'select to_char(max(month), ''YYYY-MM'') from ripples.clickstream' into cs_month;
  end if;
  used := array(select jsonb_array_elements_text(r->'decoys') from jsonb_array_elements(p_rounds) r)
          || array(select r->>'qid' from jsonb_array_elements(p_rounds) r)
          || array(select r->>'root' from jsonb_array_elements(p_rounds) r);

  for rr in select value from jsonb_array_elements(p_rounds) loop
    i := i + 1;
    select c.*, a.title_en, a.category acat, a.emoji aemoji, a.short_desc, pj.parent_onset into ans
      from ripples.candidates c
      join ripples.articles a on a.qid = c.qid
      join ripples.jobs pj on pj.id = c.job_id
     where c.as_of = p_data_as_of and c.role = 'real' and c.root_qid = rr->>'root' and c.parent_qid = rr->>'parent' and c.qid = rr->>'qid';
    select a.qid, a.title_en, a.emoji into par from ripples.articles a where a.qid = rr->>'parent';
    parent_obj := jsonb_build_object('qid', par.qid, 'title', par.title_en, 'emoji', par.emoji);
    mini := null;
    if not (rr->>'continues')::boolean then
      select jsonb_build_object('qid', s.qid, 'title', a.title_en, 'emoji', a.emoji, 'multiple', round(s.peak_multiple, 1),
                                'biggest_in_days', case when coalesce(s.biggest_since_records, false) then null else s.biggest_in_days end)
        into mini from ripples.seeds s join ripples.articles a on a.qid = s.qid
       where s.as_of = p_data_as_of and s.role = 'real' and s.qid = rr->>'root';
    end if;
    select * into fl from ripples._fluke(p_data_as_of, ans.s_stat);
    -- options in a deterministic shuffled order
    opts_p := '[]'; opts_r := '[]'; k := 0; answer_id := null;
    for opt in
      select c.*, a.title_en, a.emoji aemoji, a.short_desc, (c.qid = ans.qid) is_ans
        from ripples.candidates c join ripples.articles a on a.qid = c.qid
       where c.as_of = p_data_as_of and c.role = 'real' and c.root_qid = rr->>'root' and c.parent_qid = rr->>'parent'
         and (c.qid = ans.qid or c.qid in (select jsonb_array_elements_text(rr->'decoys')))
       order by md5(p_n || '|' || i || '|' || c.qid)
    loop
      k := k + 1;
      if opt.is_ans then answer_id := ids[k]; end if;
      opts_p := opts_p || jsonb_build_object('id', ids[k], 'qid', opt.qid, 'title', opt.title_en, 'emoji', opt.aemoji,
                                             'desc', opt.short_desc);
      opts_r := opts_r || jsonb_build_object('id', ids[k], 'qid', opt.qid, 'url', ripples._wiki_url(opt.title_en),
        'multiple', round(opt.multiple, 1), 'z', trunc(opt.s_stat, 1), 'calm', opt.calm, 'spark', to_jsonb(opt.spark),
        'median', round(opt.median_views),
        'lag_days', case when opt.is_ans then opt.onset_lag end,
        'timing', case when opt.is_ans then case when opt.onset_lag = 0 then 'alongside' else 'after' end end);
    end loop;
    if k <> 4 or answer_id is null then raise exception 'render: round % has % options', i, k; end if;
    -- the chain stopped here because the next hop was a shared trigger
    st_stop := exists (select 1 from ripples.candidates x where x.as_of = p_data_as_of and x.role = 'real'
                         and x.root_qid = rr->>'root' and x.parent_qid = ans.qid and x.pass_raw and ripples._shared_trigger(x));
    rounds_p := rounds_p || jsonb_build_object('i', i, 'continues', (rr->>'continues')::boolean, 'parent', parent_obj,
      'seed', mini, 'options', opts_p, 'answer_h', encode(extensions.digest(p_n || '|' || i || '|' || ans.qid, 'sha256'), 'hex'));
    rounds_r := rounds_r || jsonb_build_object('i', i, 'answer', answer_id, 'answer_qid', ans.qid, 'options', opts_r,
      'evidence', jsonb_build_object(
         'linked', ans.linked,
         'clickstream', case when ans.cs_rank is not null and cs_month is not null
                             then jsonb_build_object('month', cs_month, 'clicks', ans.cs_clicks, 'rank', ans.cs_rank) end,
         'fluke', case when fl.warming then null else round(fl.f, 3) end,
         'fluke_1_in', case when fl.warming then null else fl.one_in end,
         'fluke_warming', fl.warming,
         'p_time', round(ans.p_time, 3), 'placebos', ans.n_placebo, 'split_ok', ans.split_ok,
         'badge', case when ans.cs_rank is not null and ans.cs_rank <= 20 and cs_month is not null then 'flowed' else 'spiked_after' end,
         'cross', '[]'::jsonb),
      'caption', jsonb_build_object('text', ripples._caption(ans.title_en, par.title_en, ans.multiple, ans.onset_lag), 'source', 'template'),
      'shared_trigger_stop', st_stop);
    answers := answers || jsonb_build_object('i', i, 'qid', ans.qid, 'option_id', answer_id);
    caps := caps || jsonb_build_object('i', i, 'text', ripples._caption(ans.title_en, par.title_en, ans.multiple, ans.onset_lag));
    final_m := round(ans.multiple, 1);
  end loop;

  -- "Why it's trending": Google Trends RSS news for the seed (up to 3), badges from Trends RSS geos and Bluesky
  select coalesce(jsonb_agg(x.j) filter (where x.rn <= 3), '[]') into why from (
    select jsonb_build_object('title', left(e->>'title', 200), 'source', left(e->>'source', 80), 'url', e->>'url') j,
           row_number() over (order by t.rank, t.observed_at desc) rn
      from (select distinct on (e->>'url') t.*, e from ripples.trend_obs t
              join ripples.title_map m on m.lang = 'q:' || t.lang and m.title = ripples._qnorm(t.query)
              cross join lateral jsonb_array_elements(coalesce(t.news, '[]')) e
             where t.source = 'gtrends' and m.qid = seed.qid and t.day between p_data_as_of - 2 and p_data_as_of + 1
               and e->>'url' like 'https://%') t) x;
  select coalesce(jsonb_agg(b order by b), '[]') into badges from (
    select distinct 'gtrends:' || t.geo b from ripples.trend_obs t
      join ripples.title_map m on m.lang = 'q:' || t.lang and m.title = ripples._qnorm(t.query)
     where t.source = 'gtrends' and m.qid = seed.qid and t.day between p_data_as_of - 2 and p_data_as_of + 1
    union
    select 'bsky' from ripples.trend_obs t
     where t.source = 'bsky' and t.day between p_data_as_of - 2 and p_data_as_of + 1
       and lower(t.query) = lower(regexp_replace(seed.title_en, '\s*\([^)]*\)$', ''))) z;

  -- Call It: 4 calm depth-1 neighbours of round 1's seed, median >= 2000/day, not a puzzle option, <= 2 per category
  ws := p_date + coalesce((ripples._cfg('callit_window_offset') #>> '{}')::int, 0);
  we := ws + 6;
  select jsonb_agg(q order by rn) into callopts from (
    select jsonb_build_object('qid', c.qid, 'title', a.title_en, 'emoji', a.emoji, 'desc', a.short_desc,
             'category', a.category, 'median', round(c.median_views),
             'model_p', round(least(1, clim * coalesce((mult->>(case when c.cs_rank <= 5 then 'top5' when c.cs_rank <= 20 then 'top20' else 'none' end))::numeric, 1)), 3)) q,
           row_number() over (order by c.cs_rank nulls last, c.median_views desc, c.qid) rn
      from (select c.*, row_number() over (partition by a.category order by c.cs_rank nulls last, c.median_views desc, c.qid) catn
              from ripples.candidates c join ripples.articles a on a.qid = c.qid
             where c.as_of = p_data_as_of and c.role = 'real' and c.root_qid = seed.qid and c.depth = 1 and c.parent_qid = seed.qid
               and c.calm and c.linked and c.median_views >= 2000 and not (c.qid = any(used))
               and ripples._safe(c.qid, p_data_as_of, c.median_views, false)) c
      join ripples.articles a on a.qid = c.qid
     where c.catn <= 2) s where rn <= 4;
  delete from ripples.callit where n = p_n;
  if callopts is not null then
    insert into ripples.callit (n, qid, title, emoji, category, baseline_median, model_p, window_start, window_end, outcome)
    select p_n, o->>'qid', o->>'title', o->>'emoji', o->>'category', (o->>'median')::numeric, (o->>'model_p')::numeric, ws, we, 'pending'
      from jsonb_array_elements(callopts) o;
    callit := jsonb_build_object('window_start', ws, 'window_end', we,
      'options', (select jsonb_agg(jsonb_build_object('qid', o->>'qid', 'title', o->>'title', 'emoji', o->>'emoji', 'desc', o->'desc'))
                    from jsonb_array_elements(callopts) o));
  end if;

  headline := left(seed.title_en || ': which linked pages spiked next?', 70);
  if length(seed.title_en || ': which linked pages spiked next?') > 70 then headline := 'One trend. Which linked pages spiked next?'; end if;

  payload := jsonb_build_object('v', 1, 'n', p_n, 'kind', p_kind, 'date', p_date, 'data_date', p_data_as_of,
    'from_date', p_from_date, 'status', 'built', 'method', coalesce(ripples._cfg('method_version') #>> '{}', '5.0'),
    'seed', jsonb_build_object('qid', seed.qid, 'title', seed.title_en, 'emoji', seed.emoji, 'category', seed.category,
        'desc', seed.short_desc, 'multiple', round(seed.peak_multiple, 1),
        'biggest_in_days', case when coalesce(seed.biggest_since_records, false) then null else seed.biggest_in_days end,
        'biggest_since_records', coalesce(seed.biggest_since_records, false), 'langs', coalesce(seed.langs, 1),
        'onset', seed.onset, 'spark', to_jsonb(seed.spark),
        'baseline', jsonb_build_object('from', seed.baseline->>'from', 'to', seed.baseline->>'to', 'median', (seed.baseline->>'median')::numeric),
        'why', why, 'badges', badges, 'cross', '[]'::jsonb),
    'rounds', rounds_p,
    'final', jsonb_build_object('round', v_rounds, 'mag_min', 1.5, 'mag_max', 100),
    'callit', callit,
    'headline', jsonb_build_object('text', headline, 'source', 'template'));
  reveal := jsonb_build_object('v', 1, 'n', p_n, 'rounds', rounds_r,
    'end', jsonb_build_object('reason', p_end, 'text', 'The measured trail ends here.'), 'final_multiple', final_m);

  -- Board: every expanded real seed that passes safety (sensitive allowed, quadrant null); wake k of a fixed K=20 set
  select jsonb_build_object('n', p_n, 'date', p_date, 'trends', coalesce(jsonb_agg(t order by (t->>'splash_multiple')::numeric desc), '[]')) into board
    from (
      select jsonb_build_object('qid', s.qid, 'title', a.title_en, 'emoji', a.emoji, 'category', a.category,
               'splash_multiple', round(s.peak_multiple, 1),
               'biggest_in_days', case when coalesce(s.biggest_since_records, false) then null else s.biggest_in_days end,
               'wake_k', w.k, 'wake_of', w.tested,
               'quadrant', case when a.sensitive or not ripples._safe(s.qid, p_board_as_of, s.median_views, false) then null
                                when s.peak_multiple >= 10 and w.k >= 3 then 'big_wave'
                                when s.peak_multiple < 10 and w.k >= 3 then 'sleeper'
                                when s.peak_multiple >= 10 and w.k = 0 and w.tested >= 15 then 'belly_flop'
                                else 'ripple' end,
               'sensitive', a.sensitive or not ripples._safe(s.qid, p_board_as_of, s.median_views, false),
               'spark', to_jsonb(coalesce(s.spark[greatest(1, cardinality(s.spark) - 29):cardinality(s.spark)], '{}')),
               'cross', '[]'::jsonb) t
        from ripples.seeds s join ripples.articles a on a.qid = s.qid
        cross join lateral (
          select count(*) filter (where c.pass_raw and ((fx.warming and c.p_time <= 0.05) or (not fx.warming and c.p_time <= 0.10 and fx.f <= 0.20)))::int k,
                 least(20, count(*))::int tested
            from ripples.candidates c cross join lateral ripples._fluke(c.as_of, c.s_stat) fx
           where c.as_of = s.as_of and c.role = 'real' and c.root_qid = s.qid and c.parent_qid = s.qid and c.depth = 1
             and case when exists (select 1 from ripples.candidates c2 where c2.as_of = s.as_of and c2.role = 'real'
                                     and c2.root_qid = s.qid and c2.depth = 1 and c2.cs_rank is not null)
                      then c.cs_rank is not null and c.cs_rank <= 20 else c.set_rank <= 20 end) w
       where s.as_of = p_board_as_of and s.role = 'real'
         and ripples._safe(s.qid, p_board_as_of, s.median_views, true)
         and exists (select 1 from ripples.jobs j where j.as_of = s.as_of and j.kind = 'expand' and j.root_qid = s.qid
                       and j.depth = 1 and j.status = 'done')) b;

  insert into ripples.puzzles (n, kind, puzzle_date, data_date, from_date, status, payload, reveal, board, answers, final_multiple, chain_id, built_at, published_at)
  values (p_n, p_kind, p_date, p_data_as_of, p_from_date, 'built', payload, reveal, board, answers, final_m, p_chain_id, now(), null)
  on conflict (n) do update set kind = excluded.kind, puzzle_date = excluded.puzzle_date, data_date = excluded.data_date,
    from_date = excluded.from_date, status = 'built', payload = excluded.payload, reveal = excluded.reveal, board = excluded.board,
    answers = excluded.answers, final_multiple = excluded.final_multiple, chain_id = excluded.chain_id, built_at = now(),
    published_at = null;

  -- template copy (an AI row written later by W6 replaces it)
  delete from ripples.copy where n = p_n and kind in ('headline','caption');
  insert into ripples.copy (n, i, kind, text, source) values (p_n, null, 'headline', headline, 'template');
  insert into ripples.copy (n, i, kind, text, source)
  select p_n, (c->>'i')::int, 'caption', c->>'text', 'template' from jsonb_array_elements(caps) c;
  return jsonb_build_object('n', p_n, 'rounds', v_rounds, 'seed', seed.title_en, 'callit', coalesce(jsonb_array_length(callopts), 0),
                            'board', jsonb_array_length(board->'trends'));
end $$;

-- SPEC §5.3: rank chains by confidence, compose 3-4 rounds (chain / chain + fresh ripples / fresh ripples),
-- fall back to the reserve bank (unused valid compositions from the last 14 days), else delayed.
create or replace function public.ripples_build_puzzle(p_as_of date, p_kind text default 'live') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_date date := p_as_of + 1; v_n int; ex record; excl text[] := '{}'; best record; alt_c record;
  rounds jsonb := '[]'; used text[] := '{}'; dec text[]; k int; endr text; cid bigint; alt int := 0;
  res jsonb; resv record; roots text[] := '{}'; hop record;
begin
  if p_kind not in ('live','practice') then raise exception 'kind must be live or practice'; end if;
  v_n := case when p_kind = 'live' then v_date - ripples._epoch() else p_as_of - ripples._epoch() end;
  if p_kind = 'live' and v_n <= 0 then raise exception 'live n must be > 0 (got %)', v_n; end if;
  if p_kind = 'practice' and v_n >= 0 then raise exception 'practice n must be < 0 (got %)', v_n; end if;
  select * into ex from ripples.puzzles where n = v_n;
  if found and ex.status = 'published' then return jsonb_build_object('n', v_n, 'status', 'published', 'note', 'already published; not rebuilt'); end if;
  if found and ex.kind <> p_kind then raise exception 'n % already exists with kind %', v_n, ex.kind; end if;
  -- a vetoed puzzle is rebuilt from the next chain: exclude every root used by earlier compositions for this n
  if found and ex.status = 'vetoed' then
    select coalesce(array_agg(distinct r->>'root'), '{}') into excl from ripples.chains c, jsonb_array_elements(c.rounds) r where c.used_n = v_n;
  end if;
  update ripples.chains set used_n = null where used_n = v_n and as_of = p_as_of and not (root_qid = any(excl));
  delete from ripples.chains where as_of = p_as_of and used_n is null and kind = p_kind;

  -- shared-trigger flags (depth >= 2) for the record
  update ripples.candidates c set shared_trigger = ripples._shared_trigger(c) where c.as_of = p_as_of and c.role = 'real' and c.depth >= 2;

  -- answer-eligible, round-usable hops
  drop table if exists pg_temp._hops;
  create temp table _hops on commit drop as
  select c.root_qid root, c.parent_qid parent, c.qid, c.depth, a.category cat,
         log(1 / greatest(coalesce(fl.f, c.p_time), 1e-6)) lf, c.onset_lag, c.p_time
    from ripples.candidates c
    join ripples.articles a on a.qid = c.qid
    cross join lateral ripples._fluke(c.as_of, c.s_stat) fl
   where c.as_of = p_as_of and c.role = 'real' and coalesce(c.split_ok, false) and ripples._pre_eligible(c)
     and not (c.root_qid = any(excl))
     and exists (select 1 from ripples.seeds s where s.as_of = p_as_of and s.role = 'real' and s.qid = c.root_qid
                   and ripples._safe(s.qid, p_as_of, s.median_views, false))
     and ripples._pick_decoys(p_as_of, c.root_qid, c.parent_qid, c.qid, array[c.root_qid, c.parent_qid]) is not null;

  -- chains per root (depth-1 hop from the seed, then parent = previous answer), ranked by confidence
  drop table if exists pg_temp._chains;
  create temp table _chains on commit drop as
  with recursive ch as (
    select h.root, array[h.qid] path, array[h.parent] parents, 1 len, h.lf sumlf,
           (h.cat is distinct from sa.category)::int jumps, h.cat lastcat
      from _hops h join ripples.articles sa on sa.qid = h.root
     where h.depth = 1 and h.parent = h.root
    union all
    select ch.root, ch.path || h.qid, ch.parents || h.parent, ch.len + 1, ch.sumlf + h.lf,
           ch.jumps + (h.cat is distinct from ch.lastcat)::int, h.cat
      from ch join _hops h on h.root = ch.root and h.depth = ch.len + 1 and h.parent = ch.path[ch.len]
     where ch.len < 4 and not (h.qid = any(ch.path)) and h.qid <> ch.root
  )
  select ch.*, coalesce(case when s.biggest_since_records then 100000 else s.biggest_in_days end, 0) big, s.onset,
         row_number() over (order by ch.len desc, ch.sumlf desc, ch.jumps desc,
                            coalesce(case when s.biggest_since_records then 100000 else s.biggest_in_days end, 0) desc,
                            s.onset desc, ch.root, ch.path) rk
    from ch join ripples.seeds s on s.as_of = p_as_of and s.role = 'real' and s.qid = ch.root;

  select * into best from _chains order by rk limit 1;
  if found then
    used := array[best.root];
    -- 1. the chain itself (a round is dropped, and the chain cut, if its decoys collide with earlier rounds)
    for k in 1 .. least(best.len, 4) loop
      dec := ripples._pick_decoys(p_as_of, best.root, best.parents[k], best.path[k], used || best.path);
      exit when dec is null;
      rounds := rounds || jsonb_build_object('root', best.root, 'parent', best.parents[k], 'qid', best.path[k], 'depth', k,
                                             'continues', true, 'decoys', to_jsonb(dec));
      used := used || best.path[k] || dec;
    end loop;
    roots := array[best.root];
    endr := 'evidence_ended';
    -- 2./3. fresh ripples from other seeds when the chain is shorter than 3
    if jsonb_array_length(rounds) < 3 then
      for hop in
        select h.* from (select distinct on (c.root) c.root, c.path[1] qid, c.parents[1] parent, c.rk,
                                (select min(c2.rk) from _chains c2 where c2.root = c.root) root_rk
                           from _chains c where c.root <> best.root order by c.root, c.rk) h
         order by h.root_rk
      loop
        exit when jsonb_array_length(rounds) >= 4;
        continue when hop.root = any(roots) or hop.qid = any(used);
        dec := ripples._pick_decoys(p_as_of, hop.root, hop.parent, hop.qid, used || hop.root);
        continue when dec is null;
        rounds := rounds || jsonb_build_object('root', hop.root, 'parent', hop.parent, 'qid', hop.qid, 'depth', 1,
                                               'continues', false, 'decoys', to_jsonb(dec));
        used := used || hop.qid || hop.root || dec;
        roots := roots || hop.root;
        endr := 'fresh_ripples';
      end loop;
    end if;
  end if;

  if jsonb_array_length(rounds) >= 3 then
    insert into ripples.chains (as_of, kind, root_qid, rounds, score, detail, used_n)
    values (p_as_of, p_kind, best.root, rounds, best.len * 1000 + best.sumlf,
            jsonb_build_object('chain_len', best.len, 'end', endr), v_n)
    returning id into cid;
    -- reserve bank: other complete chains (>= 3 hops) from other seeds, kept unused for up to 14 days
    for alt_c in select * from _chains c where c.len >= 3 and not (c.root = any(roots))
               and c.rk = (select min(c2.rk) from _chains c2 where c2.root = c.root) order by c.rk limit 3 loop
      declare rr2 jsonb := '[]'; u2 text[] := array[alt_c.root]; d2 text[];
      begin
        for k in 1 .. least(alt_c.len, 4) loop
          d2 := ripples._pick_decoys(p_as_of, alt_c.root, alt_c.parents[k], alt_c.path[k], u2 || alt_c.path);
          exit when d2 is null;
          rr2 := rr2 || jsonb_build_object('root', alt_c.root, 'parent', alt_c.parents[k], 'qid', alt_c.path[k], 'depth', k, 'continues', true, 'decoys', to_jsonb(d2));
          u2 := u2 || alt_c.path[k] || d2;
        end loop;
        if jsonb_array_length(rr2) >= 3 then
          insert into ripples.chains (as_of, kind, root_qid, rounds, score, detail) values
            (p_as_of, p_kind, alt_c.root, rr2, alt_c.len * 1000 + alt_c.sumlf, jsonb_build_object('chain_len', alt_c.len, 'end', 'evidence_ended'));
          alt := alt + 1;
        end if;
      end;
    end loop;
    res := ripples._render(v_n, p_kind, v_date, p_as_of, p_as_of, null, rounds, endr, cid);
    return res || jsonb_build_object('status', 'built', 'format', case when endr = 'fresh_ripples' then 'fresh_ripples' else 'chain' end,
                                     'chain_len', best.len, 'reserve_added', alt);
  end if;

  -- 5. reserve bank: newest unused valid composition from the last 14 days (its real date is shown as from_date)
  select c.* into resv from ripples.chains c
   where c.used_n is null and (c.kind = p_kind or p_kind = 'live') and c.as_of between p_as_of - 14 and p_as_of - 1 and jsonb_array_length(c.rounds) >= 3
     and not (c.root_qid = any(excl))
     and not exists (select 1 from jsonb_array_elements(c.rounds) r
                      where not exists (select 1 from ripples.candidates x where x.as_of = c.as_of and x.role = 'real'
                                          and x.root_qid = r->>'root' and x.parent_qid = r->>'parent' and x.qid = r->>'qid'))
   order by c.as_of desc, c.score desc limit 1;
  if found then
    update ripples.chains set used_n = v_n where id = resv.id;
    res := ripples._render(v_n, p_kind, v_date, resv.as_of, p_as_of, resv.as_of + 1, resv.rounds,
                           coalesce(resv.detail->>'end', 'evidence_ended'), resv.id);
    return res || jsonb_build_object('status', 'built', 'format', 'reserve', 'from_date', resv.as_of + 1);
  end if;

  -- 6. nothing at all: delayed (no puzzle row; the page keeps the previous puzzle)
  return jsonb_build_object('n', v_n, 'status', 'delayed', 'hops', (select count(*) from _hops), 'chains', (select count(*) from _chains));
end $$;

do $$
begin
  revoke execute on function public.ripples_build_puzzle(date, text) from public, anon, authenticated;
  grant execute on function public.ripples_build_puzzle(date, text) to service_role;
end $$;
