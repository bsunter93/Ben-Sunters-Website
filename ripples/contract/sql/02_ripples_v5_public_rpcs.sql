-- Knock-On v5 / W1: migration ripples_v5_public_rpcs
-- Public read/write RPCs (anon) + service-only og_data / publish_bundle.
-- Every function: SECURITY DEFINER, search_path = '', fully-qualified names.

-- ======================= internal helpers =======================
create or replace function ripples._categories() returns text[]
language sql immutable set search_path = '' as $$
  select array['person','place','film_tv','music','sport','science_health','tech','business',
               'politics_law','food_drink','nature_weather','history_culture','other']
$$;

-- category from the fixed category emoji (VS16 ignored)
create or replace function ripples._cat(p_emoji text) returns text
language sql immutable set search_path = '' as $$
  select case replace(coalesce(p_emoji, ''), U&'\FE0F', '')
    when '👤' then 'person'        when '📍' then 'place'          when '🎬' then 'film_tv'
    when '🎵' then 'music'         when '🏅' then 'sport'          when '🧬' then 'science_health'
    when '💻' then 'tech'          when '🏢' then 'business'       when '⚖'  then 'politics_law'
    when '🍎' then 'food_drink'    when '🌦' then 'nature_weather' when '🏛' then 'history_culture'
    when '🔹' then 'other'         else null end
$$;

create or replace function ripples._wiki_url(p_title text) returns text
language sql immutable set search_path = '' as $$
  select case when p_title is null then null else
    'https://en.wikipedia.org/wiki/' ||
    replace(replace(replace(replace(replace(p_title, '%', '%25'), ' ', '_'), '?', '%3F'), '#', '%23'), '"', '%22')
  end
$$;

-- Visibility: live = published and puzzle_date <= current puzzle date (07:30 UTC rollover);
-- practice = built/published; fixture = n 0 only.
create or replace function ripples._visible(p_n int) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from ripples.puzzles p
     where p.n = p_n and (
          (p.kind = 'live'     and p.status = 'published' and p.puzzle_date <= ripples._current_date())
       or (p.kind = 'practice' and p.status in ('built', 'published'))
       or (p.kind = 'fixture'  and p.n = 0)))
$$;

create or replace function ripples._latest_live_n() returns int
language sql stable security definer set search_path = '' as $$
  select max(n) from ripples.puzzles
   where kind = 'live' and status = 'published' and puzzle_date <= ripples._current_date()
$$;

-- PuzzlePayload with copy overlay (ai/template headline from ripples.copy; fixture is never overlaid)
create or replace function ripples._puzzle_json(p_n int) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r ripples.puzzles; h record; out jsonb;
begin
  select * into r from ripples.puzzles where n = p_n;
  if not found or r.payload is null then return null; end if;
  out := r.payload;
  if r.kind <> 'fixture' then
    select c.text, c.source into h from ripples.copy c
     where c.n = p_n and c.kind = 'headline' and coalesce(c.i, 0) = 0;
    if found then
      out := jsonb_set(out, '{headline}', jsonb_build_object('text', h.text, 'source', h.source), true);
    end if;
  end if;
  return out;
end $$;

-- RevealPayload with caption overlay from ripples.copy (fixture never overlaid)
create or replace function ripples._reveal_json(p_n int) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r ripples.puzzles; rounds jsonb;
begin
  select * into r from ripples.puzzles where n = p_n;
  if not found or r.reveal is null then return null; end if;
  if r.kind = 'fixture' or not exists (select 1 from ripples.copy c where c.n = p_n and c.kind = 'caption') then
    return r.reveal;
  end if;
  select coalesce(jsonb_agg(
           case when c.text is not null
                then t.e || jsonb_build_object('caption', jsonb_build_object('text', c.text, 'source', c.source))
                else t.e end
           order by t.ord), '[]'::jsonb)
    into rounds
    from jsonb_array_elements(r.reveal -> 'rounds') with ordinality as t(e, ord)
    left join ripples.copy c on c.n = p_n and c.kind = 'caption' and c.i = (t.e ->> 'i')::int;
  return jsonb_set(r.reveal, '{rounds}', rounds);
end $$;

-- CallItPayload (no visibility check)
create or replace function ripples._callit_json(p_n int) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare minp int := coalesce((ripples._cfg('min_players') #>> '{}')::int, 30);
        total int; ws date; we date; opts jsonb; r ripples.puzzles;
begin
  select * into r from ripples.puzzles where n = p_n;
  select min(window_start), max(window_end) into ws, we from ripples.callit where n = p_n;
  if ws is null then return null; end if;
  select count(*) into total from ripples.calls where n = p_n;
  select jsonb_agg(jsonb_build_object(
           'qid', c.qid, 'title', c.title, 'emoji', c.emoji,
           'model_p', c.model_p,
           'crowd_pct', case when total >= minp
                             then round(100.0 * (select count(*) from ripples.calls k where k.n = p_n and k.qid = c.qid) / total)::int
                             end,
           'outcome', c.outcome,
           'max_z', case when c.outcome <> 'pending' then c.max_z end,
           'url', case when c.outcome <> 'pending' then ripples._wiki_url(c.title) end)
         order by coalesce(o.ord, 99), c.qid)
    into opts
    from ripples.callit c
    left join lateral (
      select x.ord from jsonb_array_elements(coalesce(r.payload #> '{callit,options}', '[]'::jsonb)) with ordinality as x(e, ord)
       where x.e ->> 'qid' = c.qid limit 1) o on true
   where c.n = p_n;
  return jsonb_build_object(
    'n', p_n, 'window_start', ws, 'window_end', we, 'resolves_on', ws + 8,
    'model', coalesce(ripples._cfg('model_label') #>> '{}', 'v0 base rate'),
    'options', coalesce(opts, '[]'::jsonb));
end $$;

-- StatsPayload. p_you is passed through; arrays only when players >= min_players.
create or replace function ripples._stats(p_n int, p_you jsonb default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare minp int := coalesce((ripples._cfg('min_players') #>> '{}')::int, 30);
        players int; nr int; mx int; rounds jsonb; hist jsonb; magx numeric;
begin
  select count(*) into players from ripples.plays where n = p_n;
  if players < minp then
    return jsonb_build_object('n', p_n, 'players', players, 'shown', false, 'rounds', null,
                              'score_hist', null, 'mag_median_x', null, 'you', p_you);
  end if;
  select jsonb_array_length(payload -> 'rounds') into nr from ripples.puzzles where n = p_n;
  nr := coalesce(nr, 0);
  mx := 2 * nr + 2;
  select jsonb_agg(x.o order by x.i) into rounds from (
    select g.i, jsonb_build_object(
      'i', g.i,
      'first_try_pct', round(100.0 * count(*) filter (where p.codes[g.i] = 2) / players)::int,
      'found_pct',     round(100.0 * count(*) filter (where p.codes[g.i] >= 1) / players)::int,
      'split', jsonb_build_object(
         'a', round(100.0 * count(*) filter (where p.picks -> (g.i - 1) ->> 0 = 'a') / players)::int,
         'b', round(100.0 * count(*) filter (where p.picks -> (g.i - 1) ->> 0 = 'b') / players)::int,
         'c', round(100.0 * count(*) filter (where p.picks -> (g.i - 1) ->> 0 = 'c') / players)::int,
         'd', round(100.0 * count(*) filter (where p.picks -> (g.i - 1) ->> 0 = 'd') / players)::int)) o
    from generate_series(1, nr) g(i) cross join ripples.plays p
   where p.n = p_n group by g.i) x;
  select jsonb_agg(coalesce(s.cnt, 0) order by g.sc) into hist
    from generate_series(0, mx) g(sc)
    left join (select score, count(*) cnt from ripples.plays where n = p_n group by score) s on s.score = g.sc;
  select round(power(10::numeric, percentile_cont(0.5) within group (order by mag_err)::numeric), 1)
    into magx from ripples.plays where n = p_n and mag_err is not null;
  return jsonb_build_object('n', p_n, 'players', players, 'shown', true, 'rounds', coalesce(rounds, '[]'::jsonb),
                            'score_hist', hist, 'mag_median_x', magx, 'you', p_you);
end $$;

-- archive row
create or replace function ripples._archive_row(r ripples.puzzles) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'n', r.n, 'date', r.puzzle_date, 'from_date', r.from_date, 'kind', r.kind,
    'seed_title', r.payload #>> '{seed,title}', 'seed_emoji', r.payload #>> '{seed,emoji}',
    'rounds', coalesce(jsonb_array_length(r.payload -> 'rounds'), 0),
    'path', coalesce(r.payload #>> '{seed,emoji}', '') || coalesce((
      select string_agg(
               case when coalesce((rd.e ->> 'continues')::boolean, true) then ''
                    else '·' || coalesce(rd.e #>> '{seed,emoji}', rd.e #>> '{parent,emoji}', '') end
               || coalesce((select o ->> 'emoji' from jsonb_array_elements(rd.e -> 'options') o
                             where o ->> 'id' = (select a ->> 'option_id' from jsonb_array_elements(r.answers) a
                                                  where (a ->> 'i')::int = (rd.e ->> 'i')::int limit 1) limit 1), '?'),
               '' order by rd.ord)
        from jsonb_array_elements(r.payload -> 'rounds') with ordinality rd(e, ord)), ''))
$$;

-- Canonical JSON for hashing: every number is round-tripped through float8 (15 significant digits,
-- plain notation), so a JSON file re-serialised by JS/Python hashes the same as the stored jsonb.
create or replace function ripples._canon(p jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
begin
  return case jsonb_typeof(p)
    when 'object' then coalesce((select jsonb_object_agg(e.k, ripples._canon(e.v)) from jsonb_each(p) e(k, v)), '{}'::jsonb)
    when 'array'  then coalesce((select jsonb_agg(ripples._canon(a.v) order by a.o)
                                   from jsonb_array_elements(p) with ordinality a(v, o)), '[]'::jsonb)
    when 'number' then to_jsonb((p #>> '{}')::float8)
    else p end;
end $$;

-- What the ledger commits to, reconstructable from the PUBLIC files v1/puzzle/{n}.json, v1/reveal/{n}.json
-- and v1/callit/{n}.json: the puzzle without "headline", the reveal with "caption" removed from every round
-- (copy is overlaid and may arrive after publish), and the Call It [qid, model_p] pairs ordered by qid (byte order).
create or replace function ripples._ledger_input(p_n int) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r ripples.puzzles; cl jsonb; rv jsonb;
begin
  select * into r from ripples.puzzles where n = p_n;
  if not found then return null; end if;
  select coalesce(jsonb_agg(jsonb_build_array(c.qid, c.model_p) order by c.qid collate "C"), '[]'::jsonb)
    into cl from ripples.callit c where c.n = p_n;
  rv := r.reveal;
  if jsonb_typeof(rv -> 'rounds') = 'array' then
    rv := jsonb_set(rv, '{rounds}', (select coalesce(jsonb_agg(case when jsonb_typeof(t.e) = 'object' then t.e - 'caption' else t.e end
                                                                order by t.o), '[]'::jsonb)
                                       from jsonb_array_elements(rv -> 'rounds') with ordinality t(e, o)));
  end if;
  return ripples._canon(jsonb_build_object(
    'n', p_n,
    'puzzle', case when jsonb_typeof(r.payload) = 'object' then r.payload - 'headline' else r.payload end,
    'reveal', rv, 'callit', cl));
end $$;

-- Hash-chained ledger row, written ONLY for a live puzzle whose status is 'published' (called by
-- ripples_publish_bundle; calling it earlier returns null and writes nothing, so a veto/rebuild can never
-- leave a row that certifies a discarded payload). A published puzzle can no longer be rebuilt or vetoed,
-- so the first row is final. prev_hash = chain_hash of the most recently WRITTEN row (seq order), or 64 zeros.
create or replace function ripples._ledger_write(p_n int) returns text
language plpgsql volatile security definer set search_path = '' as $$
declare r ripples.puzzles; ph text; prev text; ch text;
begin
  select chain_hash into ch from ripples.ledger where n = p_n;
  if ch is not null then return ch; end if;
  select * into r from ripples.puzzles where n = p_n;
  if not found or r.kind <> 'live' or r.status <> 'published' then return null; end if;
  lock table ripples.ledger in share row exclusive mode;
  select chain_hash into ch from ripples.ledger where n = p_n;
  if ch is not null then return ch; end if;
  ph := encode(extensions.digest(ripples._ledger_input(p_n)::text, 'sha256'), 'hex');
  prev := coalesce((select l.chain_hash from ripples.ledger l order by l.seq desc limit 1), repeat('0', 64));
  ch := encode(extensions.digest(prev || ph, 'sha256'), 'hex');
  insert into ripples.ledger(n, day, payload_hash, prev_hash, chain_hash)
  values (p_n, r.puzzle_date, ph, prev, ch);
  return ch;
end $$;

-- Recompute every ledger row in write order: payload_hash from the current stored puzzle, linkage, chain hash.
create or replace function ripples._ledger_verify() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare l record; prev text := repeat('0', 64); bad jsonb := '[]'::jsonb; cnt int := 0;
begin
  for l in select * from ripples.ledger order by seq loop
    cnt := cnt + 1;
    if l.prev_hash <> prev
       or l.payload_hash <> encode(extensions.digest(ripples._ledger_input(l.n)::text, 'sha256'), 'hex')
       or l.chain_hash <> encode(extensions.digest(l.prev_hash || l.payload_hash, 'sha256'), 'hex') then
      bad := bad || to_jsonb(l.n);
    end if;
    prev := l.chain_hash;
  end loop;
  return jsonb_build_object('ok', jsonb_array_length(bad) = 0, 'rows', cnt,
                            'head', (select chain_hash from ripples.ledger order by seq desc limit 1), 'bad', bad);
end $$;

-- Grants audit: public.ripples_* functions that anon or authenticated can EXECUTE but that are not on the
-- public allow-list. Must return zero rows. (This project's default privileges grant EXECUTE on every new
-- public function to anon and authenticated directly; "revoke ... from public" alone does NOT remove that.)
create or replace function ripples._grant_audit()
returns table(fn text, role text)
language sql stable security definer set search_path = '' as $$
  select p.oid::regprocedure::text, r.rolname::text
    from pg_catalog.pg_proc p
    cross join (values ('anon'), ('authenticated')) r(rolname)
   where p.pronamespace = 'public'::regnamespace
     and p.proname like 'ripples\_%'
     and p.proname not in ('ripples_latest','ripples_puzzle','ripples_reveal','ripples_stats','ripples_callit',
                           'ripples_board','ripples_archive','ripples_brief','ripples_health','ripples_submit_play',
                           'ripples_submit_call','ripples_join','ripples_track_record')
     and pg_catalog.has_function_privilege(r.rolname, p.oid, 'EXECUTE')
   order by 1, 2
$$;

-- ======================= public read RPCs (anon) =======================
create or replace function public.ripples_latest() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare cur date := ripples._current_date(); ln int; r ripples.puzzles;
        next_at timestamptz := (((now() at time zone 'utc') - interval '7 hours 30 minutes')::date + 1 + time '07:30') at time zone 'utc';
begin
  ln := ripples._latest_live_n();
  if ln is null then
    return jsonb_build_object('n', null, 'date', cur, 'status', 'delayed', 'puzzle', null, 'next_at', next_at);
  end if;
  select * into r from ripples.puzzles where n = ln;
  return jsonb_build_object('n', r.n, 'date', r.puzzle_date,
    'status', case when r.puzzle_date >= cur then 'published' else 'delayed' end,
    'puzzle', ripples._puzzle_json(r.n), 'next_at', next_at);
end $$;

create or replace function public.ripples_puzzle(p_n int) returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when ripples._visible(p_n) then ripples._puzzle_json(p_n) end
$$;

create or replace function public.ripples_reveal(p_n int) returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when ripples._visible(p_n) then ripples._reveal_json(p_n) end
$$;

create or replace function public.ripples_stats(p_n int) returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when ripples._visible(p_n) then ripples._stats(p_n, null) end
$$;

create or replace function public.ripples_callit(p_n int) returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when ripples._visible(p_n) then ripples._callit_json(p_n) end
$$;

create or replace function public.ripples_board(p_n int default null) returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when ripples._visible(x.n) then (select p.board from ripples.puzzles p where p.n = x.n) end
    from (select coalesce(p_n, ripples._latest_live_n()) as n) x
$$;

create or replace function public.ripples_archive(p_limit int default 60, p_kind text default 'live') returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(ripples._archive_row(p) order by (p.kind = 'live') desc, p.n desc), '[]'::jsonb)
    from ripples.puzzles p
   where p.n in (
     select q.n from ripples.puzzles q
      where ripples._visible(q.n)
        and (case coalesce(p_kind, 'live')
               when 'all' then q.kind in ('live', 'practice')
               else q.kind = coalesce(p_kind, 'live') end)
      order by (q.kind = 'live') desc, q.n desc
      limit greatest(1, least(coalesce(p_limit, 60), 500)))
$$;

create or replace function public.ripples_brief(p_days int default 7, p_category text default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare d int := greatest(1, least(coalesce(p_days, 7), 60));
        cur date := ripples._current_date();
        f date; t date; items jsonb; intro jsonb; recon boolean := false; lo int; hi int;
begin
  if p_category is not null and not (p_category = any (ripples._categories())) then
    return jsonb_build_object('from', cur - d, 'to', cur - 1, 'category', null, 'intro', null,
                              'reconstructed', false, 'items', '[]'::jsonb);
  end if;
  -- live puzzles strictly before today's (never spoil the current puzzle)
  f := cur - d; t := cur - 1;
  select min(n), max(n) into lo, hi from ripples.puzzles
   where kind = 'live' and status = 'published' and puzzle_date between f and t;
  if lo is null then
    -- nothing live yet: fall back to reconstructed practice puzzles, labeled as such
    select max(n) into hi from ripples.puzzles where kind = 'practice' and status in ('built','published');
    if hi is not null then
      lo := hi - d + 1; recon := true;
      select min(puzzle_date), max(puzzle_date) into f, t from ripples.puzzles
       where kind = 'practice' and n between lo and hi;
    end if;
  end if;
  select coalesce(jsonb_agg(it.o order by it.n desc, it.i), '[]'::jsonb) into items from (
    select p.n, (rd.e ->> 'i')::int as i, jsonb_build_object(
      'n', p.n, 'date', p.puzzle_date,
      'seed_title', coalesce(rd.e #>> '{seed,title}', p.payload #>> '{seed,title}'),
      'hop_title', op.o ->> 'title',
      'category', ripples._cat(op.o ->> 'emoji'),
      'emoji', op.o ->> 'emoji',
      'multiple', (rv.o ->> 'multiple')::numeric,
      'fluke_1_in', (rr.e #>> '{evidence,fluke_1_in}')::int,
      'lag_days', (rv.o ->> 'lag_days')::int,
      'timing', rv.o ->> 'timing') as o
    from ripples.puzzles p
    cross join lateral jsonb_array_elements(p.payload -> 'rounds') rd(e)
    cross join lateral (select z.v ->> 'option_id' as oid from jsonb_array_elements(p.answers) z(v)
                        where (z.v ->> 'i')::int = (rd.e ->> 'i')::int limit 1) ans
    cross join lateral (select y.v as o from jsonb_array_elements(rd.e -> 'options') y(v) where y.v ->> 'id' = ans.oid limit 1) op
    left join lateral (select x.v as e from jsonb_array_elements(p.reveal -> 'rounds') x(v)
                        where (x.v ->> 'i')::int = (rd.e ->> 'i')::int limit 1) rr on true
    left join lateral (select y.v as o from jsonb_array_elements(rr.e -> 'options') y(v) where y.v ->> 'id' = ans.oid limit 1) rv on true
   where p.n between lo and hi
     and ((not recon and p.kind = 'live' and p.status = 'published' and p.puzzle_date between f and t)
       or (recon and p.kind = 'practice' and p.status in ('built','published')))
     and (p_category is null or ripples._cat(op.o ->> 'emoji') = p_category)) it;
  select jsonb_build_object('text', c.text, 'source', c.source) into intro
    from ripples.copy c where c.kind = 'brief_intro' and c.n between coalesce(lo, 0) and coalesce(hi, -1)
   order by c.n desc, c.created_at desc limit 1;
  return jsonb_build_object('from', f, 'to', t, 'category', p_category, 'intro', intro,
                            'reconstructed', recon, 'items', items);
end $$;

create or replace function public.ripples_health() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare ln int; r ripples.puzzles; st text; wm int; er int; cm date; cur date := ripples._current_date();
begin
  ln := ripples._latest_live_n();
  if ln is not null then select * into r from ripples.puzzles where n = ln; end if;
  if to_regclass('ripples.runs') is not null then
    begin
      execute 'select stage::text, wm_calls::int, errors::int from ripples.runs order by as_of desc limit 1'
        into st, wm, er;
    exception when others then st := null; wm := null; er := null;
    end;
  end if;
  if to_regclass('ripples.clickstream') is not null then
    begin
      execute 'select max(month)::date from ripples.clickstream' into cm;
    exception when others then cm := null;
    end;
  end if;
  return jsonb_build_object(
    'latest_n', ln, 'published_at', r.published_at,
    'stale', (ln is null or r.puzzle_date < cur),
    'expected_n', (cur - ripples._epoch())::int,
    'stage', st, 'wm_calls', wm, 'errors', er,
    'clickstream_month', to_char(cm, 'YYYY-MM'));
end $$;

-- ======================= public write RPCs (anon) =======================
create or replace function public.ripples_submit_play(p_client text, p_n int, p_picks jsonb, p_mag numeric)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare r ripples.puzzles; nr int; codes smallint[] := '{}'; pts int := 0; mx int; ans text; pk jsonb;
        k int; e numeric; magpts int := 0; iph text; ch text; ins int; minp int; players int;
        below numeric; ties numeric; my_score int; you jsonb; cur_n int := ripples._current_n();
begin
  if p_client is null or p_client !~ '^[A-Za-z0-9_-]{16,64}$' then raise exception 'invalid'; end if;
  if p_n is null or p_picks is null or jsonb_typeof(p_picks) <> 'array'
     or p_mag is null or p_mag < 1.5 or p_mag > 100 then raise exception 'invalid'; end if;
  select * into r from ripples.puzzles where n = p_n;
  if not found or not ripples._visible(p_n) or r.kind = 'practice' then raise exception 'closed'; end if;
  if r.kind = 'live' and (p_n < cur_n - 7 or p_n > cur_n) then raise exception 'closed'; end if;
  nr := coalesce(jsonb_array_length(r.payload -> 'rounds'), 0);
  if nr = 0 or jsonb_array_length(p_picks) <> nr then raise exception 'invalid'; end if;
  for k in 1..nr loop
    pk := p_picks -> (k - 1);
    if jsonb_typeof(pk) <> 'array' or jsonb_array_length(pk) not between 1 and 2 then raise exception 'invalid'; end if;
    if exists (select 1 from jsonb_array_elements(pk) x
                where jsonb_typeof(x) <> 'string' or (x #>> '{}') not in ('a','b','c','d')) then
      raise exception 'invalid';
    end if;
    if jsonb_array_length(pk) = 2 and pk ->> 0 = pk ->> 1 then raise exception 'invalid'; end if;
    select a ->> 'option_id' into ans from jsonb_array_elements(r.answers) a where (a ->> 'i')::int = k limit 1;
    if ans is null then raise exception 'invalid'; end if;
    if pk ->> 0 = ans then
      if jsonb_array_length(pk) = 2 then raise exception 'invalid'; end if;
      codes := codes || 2::smallint; pts := pts + 2;
    elsif pk ->> 1 = ans then
      codes := codes || 1::smallint; pts := pts + 1;
    else
      codes := codes || 0::smallint;
    end if;
  end loop;
  if r.final_multiple is not null and r.final_multiple > 0 then
    e := abs(log(10::numeric, p_mag / r.final_multiple));
    magpts := case when e <= 0.176 then 2 when e <= 0.477 then 1 else 0 end;
  end if;
  pts := pts + magpts; mx := 2 * nr + 2;

  iph := ripples._ip_hash();
  if not ripples._rate('play:' || iph, 20) then raise exception 'rate_limited'; end if;

  ch := ripples._hash(p_client, r.puzzle_date);
  insert into ripples.plays(n, client_hash, ip_hash, picks, codes, score, max_score, mag_guess, mag_err, country)
  values (p_n, ch, iph, p_picks, codes, pts, mx, p_mag, round(e, 4), ripples._country())
  on conflict (n, client_hash) do nothing;
  get diagnostics ins = row_count;

  select score into my_score from ripples.plays where n = p_n and client_hash = ch;
  minp := coalesce((ripples._cfg('min_players') #>> '{}')::int, 30);
  select count(*), count(*) filter (where score < my_score), count(*) filter (where score = my_score)
    into players, below, ties from ripples.plays where n = p_n;
  you := jsonb_build_object('score', my_score, 'max', mx,
           'percentile', case when players >= minp then round(100 * (below + 0.5 * ties) / players)::int end);
  return ripples._stats(p_n, you);
end $$;

create or replace function public.ripples_submit_call(p_client text, p_n int, p_qid text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare r ripples.puzzles; c ripples.callit; iph text; total int; minp int; split jsonb;
begin
  if p_client is null or p_client !~ '^[A-Za-z0-9_-]{16,64}$' then raise exception 'invalid'; end if;
  if p_n is null or p_qid is null or p_qid !~ '^Q[0-9]{1,12}$' then raise exception 'invalid'; end if;
  select * into r from ripples.puzzles where n = p_n;
  if not found or not ripples._visible(p_n) or r.kind = 'practice' then raise exception 'closed'; end if;
  select * into c from ripples.callit where n = p_n and qid = p_qid;
  if not found then raise exception 'invalid'; end if;
  -- calls close at 00:00 UTC after window_start: from then on day-1 pageviews are public (no look-ahead)
  if r.kind = 'live' and (now() at time zone 'utc')::date > c.window_start then raise exception 'closed'; end if;
  iph := ripples._ip_hash();
  if not ripples._rate('call:' || iph, 20) then raise exception 'rate_limited'; end if;
  insert into ripples.calls(n, client_hash, qid)
  values (p_n, ripples._hash(p_client, r.puzzle_date), p_qid)
  on conflict (n, client_hash) do nothing;
  minp := coalesce((ripples._cfg('min_players') #>> '{}')::int, 30);
  select count(*) into total from ripples.calls where n = p_n;
  if total >= minp then
    select jsonb_agg(jsonb_build_object('qid', o.qid,
             'pct', round(100.0 * (select count(*) from ripples.calls k where k.n = p_n and k.qid = o.qid) / total)::int)
             order by o.qid)
      into split from ripples.callit o where o.n = p_n;
  end if;
  return jsonb_build_object('ok', true, 'split', split);
end $$;

create or replace function public.ripples_join(p_email text, p_role text default null, p_price text default 'free',
                                               p_topics text[] default null, p_source text default null)
returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare e text; iph text; ok jsonb := '{"ok":true}'::jsonb;
begin
  iph := ripples._ip_hash();
  if not ripples._rate('join:' || iph, 5) then return ok; end if;
  e := lower(trim(coalesce(p_email, '')));
  if e = '' or length(e) > 254
     or e !~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]{1,64}@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$'
  then return ok; end if;
  if p_role is not null and p_role not in ('player','creator','newsletter','pr_comms','seo_content',
                                           'journalist','researcher','brand','analyst','other') then return ok; end if;
  if coalesce(p_price, 'free') not in ('free','radar5','radar19','team149','report149','partner500','api') then return ok; end if;
  if p_topics is not null and (cardinality(p_topics) > 13 or not (p_topics <@ ripples._categories())) then return ok; end if;
  if p_source is not null and p_source !~ '^[a-z0-9_-]{1,32}$' then return ok; end if;
  insert into ripples.waitlist(email_norm, role, price, topics, source, ip_hash)
  values (e, p_role, coalesce(p_price, 'free'), p_topics, p_source, iph)
  on conflict (email_norm) do update
     set role   = coalesce(excluded.role, ripples.waitlist.role),
         -- price test: a paid intent (radar5, ...) is never downgraded by a later 'free' signup
         price  = case when excluded.price <> 'free' then excluded.price else ripples.waitlist.price end,
         topics = coalesce(excluded.topics, ripples.waitlist.topics),
         source = coalesce(ripples.waitlist.source, excluded.source);
  return ok;
end $$;

-- ======================= service-only RPCs =======================
create or replace function public.ripples_og_data(p_n int default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare nn int := coalesce(p_n, ripples._latest_live_n()); r ripples.puzzles; rounds jsonb;
begin
  if nn is null or not ripples._visible(nn) then return null; end if;
  select * into r from ripples.puzzles where n = nn;
  select coalesce(jsonb_agg(jsonb_build_object(
           'i', (rd.e ->> 'i')::int,
           'continues', coalesce((rd.e ->> 'continues')::boolean, true),
           'seed_emoji', rd.e #>> '{seed,emoji}',
           'emoji', op.o ->> 'emoji', 'title', op.o ->> 'title',
           'multiple', (rv.o ->> 'multiple')::numeric) order by rd.ord), '[]'::jsonb)
    into rounds
    from jsonb_array_elements(r.payload -> 'rounds') with ordinality rd(e, ord)
    left join lateral (select z.v ->> 'option_id' as oid from jsonb_array_elements(r.answers) z(v)
                        where (z.v ->> 'i')::int = (rd.e ->> 'i')::int limit 1) ans on true
    left join lateral (select y.v as o from jsonb_array_elements(rd.e -> 'options') y(v) where y.v ->> 'id' = ans.oid limit 1) op on true
    left join lateral (select x.v as e from jsonb_array_elements(r.reveal -> 'rounds') x(v)
                        where (x.v ->> 'i')::int = (rd.e ->> 'i')::int limit 1) rr on true
    left join lateral (select y.v as o from jsonb_array_elements(rr.e -> 'options') y(v) where y.v ->> 'id' = ans.oid limit 1) rv on true;
  return jsonb_build_object(
    'n', r.n, 'kind', r.kind, 'status', r.status, 'date', r.puzzle_date, 'from_date', r.from_date,
    -- past = the puzzle is no longer the current one (07:30 UTC rollover), so a reveal card cannot spoil it
    'past', r.puzzle_date < ripples._current_date(),
    'seed', jsonb_build_object(
       'title', r.payload #>> '{seed,title}', 'emoji', r.payload #>> '{seed,emoji}',
       'biggest_in_days', (r.payload #>> '{seed,biggest_in_days}')::int,
       'since_records', coalesce((r.payload #>> '{seed,biggest_since_records}')::boolean, false),
       'multiple', (r.payload #>> '{seed,multiple}')::numeric,
       'langs', (r.payload #>> '{seed,langs}')::int),
    'rounds', rounds, 'R', jsonb_array_length(rounds));
end $$;

create or replace function public.ripples_publish_bundle(p_n int default null) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare nn int := p_n; r ripples.puzzles; track jsonb; csv jsonb := '[]'::jsonb; recent jsonb; ledger_head text;
        ledger jsonb;
begin
  perform ripples._purge_salts();
  if nn is null then
    select n into nn from ripples.puzzles
     where kind = 'live' and status in ('built', 'published') and puzzle_date <= (now() at time zone 'utc')::date
     order by n desc limit 1;
  end if;
  if nn is not null then
    select * into r from ripples.puzzles where n = nn;
    if not found then raise exception 'not_found'; end if;
    if r.status in ('vetoed', 'delayed') then raise exception 'not_publishable'; end if;
    if r.kind in ('live', 'practice') and (r.status = 'built' or r.published_at is null) then
      update ripples.puzzles set status = 'published', published_at = coalesce(published_at, now()) where n = nn;
    end if;
    if r.kind = 'live' then perform ripples._ledger_write(nn); end if;
    select * into r from ripples.puzzles where n = nn;
  end if;

  if to_regprocedure('public.ripples_track_record()') is not null then
    begin
      execute 'select public.ripples_track_record()' into track;
    exception when others then track := null;
    end;
  end if;

  if nn is not null and r.kind = 'live' then
    select coalesce(jsonb_agg(jsonb_build_object(
             'date', r.puzzle_date, 'n', r.n, 'round', (rd.e ->> 'i')::int,
             'parent', rd.e #>> '{parent,title}', 'answer', op.o ->> 'title',
             'multiple', (rv.o ->> 'multiple')::numeric, 'z', (rv.o ->> 'z')::numeric,
             'lag_days', (rv.o ->> 'lag_days')::int,
             'fluke', (rr.e #>> '{evidence,fluke}')::numeric, 'p_time', (rr.e #>> '{evidence,p_time}')::numeric,
             'category', ripples._cat(op.o ->> 'emoji')) order by rd.ord), '[]'::jsonb)
      into csv
      from jsonb_array_elements(r.payload -> 'rounds') with ordinality rd(e, ord)
      left join lateral (select z.v ->> 'option_id' as oid from jsonb_array_elements(r.answers) z(v)
                        where (z.v ->> 'i')::int = (rd.e ->> 'i')::int limit 1) ans on true
      left join lateral (select y.v as o from jsonb_array_elements(rd.e -> 'options') y(v) where y.v ->> 'id' = ans.oid limit 1) op on true
      left join lateral (select x.v as e from jsonb_array_elements(r.reveal -> 'rounds') x(v)
                        where (x.v ->> 'i')::int = (rd.e ->> 'i')::int limit 1) rr on true
      left join lateral (select y.v as o from jsonb_array_elements(rr.e -> 'options') y(v) where y.v ->> 'id' = ans.oid limit 1) rv on true;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('n', x.n, 'callit', ripples._callit_json(x.n)) order by x.n desc), '[]'::jsonb)
    into recent
    from (select p.n from ripples.puzzles p
           where p.kind = 'live' and p.status = 'published' and p.n <= coalesce(nn, 2147483647)
             and exists (select 1 from ripples.callit c where c.n = p.n)
           order by p.n desc limit 8) x;

  -- ledger head = the most recently written row; `ledger` = every row in write order (for v1/ledger.json)
  select l.chain_hash into ledger_head from ripples.ledger l order by l.seq desc limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('n', l.n, 'day', l.day, 'payload_hash', l.payload_hash,
                                               'prev_hash', l.prev_hash, 'chain_hash', l.chain_hash) order by l.seq), '[]'::jsonb)
    into ledger from ripples.ledger l;

  return jsonb_build_object(
    'n', nn, 'kind', r.kind, 'date', r.puzzle_date,
    'latest',  public.ripples_latest(),
    'puzzle',  case when nn is not null then ripples._puzzle_json(nn) end,
    'reveal',  case when nn is not null then ripples._reveal_json(nn) end,
    'callit',  case when nn is not null then ripples._callit_json(nn) end,
    'board',   case when nn is not null then r.board else public.ripples_board(null) end,
    'archive', public.ripples_archive(500, 'all'),
    'track',   track,
    'csv_rows', csv,
    'recent_callit', recent,
    'ledger_head', ledger_head,
    'ledger', ledger);
end $$;

-- ======================= grants =======================
revoke execute on all functions in schema ripples from public, anon, authenticated;

revoke execute on function public.ripples_latest()                              from public, anon, authenticated;
revoke execute on function public.ripples_puzzle(int)                           from public, anon, authenticated;
revoke execute on function public.ripples_reveal(int)                           from public, anon, authenticated;
revoke execute on function public.ripples_stats(int)                            from public, anon, authenticated;
revoke execute on function public.ripples_callit(int)                           from public, anon, authenticated;
revoke execute on function public.ripples_board(int)                            from public, anon, authenticated;
revoke execute on function public.ripples_archive(int, text)                    from public, anon, authenticated;
revoke execute on function public.ripples_brief(int, text)                      from public, anon, authenticated;
revoke execute on function public.ripples_health()                              from public, anon, authenticated;
revoke execute on function public.ripples_submit_play(text, int, jsonb, numeric) from public, anon, authenticated;
revoke execute on function public.ripples_submit_call(text, int, text)          from public, anon, authenticated;
revoke execute on function public.ripples_join(text, text, text, text[], text)  from public, anon, authenticated;
revoke execute on function public.ripples_og_data(int)                          from public, anon, authenticated;
revoke execute on function public.ripples_publish_bundle(int)                   from public, anon, authenticated;

grant execute on function public.ripples_latest()                               to anon, authenticated, service_role;
grant execute on function public.ripples_puzzle(int)                            to anon, authenticated, service_role;
grant execute on function public.ripples_reveal(int)                            to anon, authenticated, service_role;
grant execute on function public.ripples_stats(int)                             to anon, authenticated, service_role;
grant execute on function public.ripples_callit(int)                            to anon, authenticated, service_role;
grant execute on function public.ripples_board(int)                             to anon, authenticated, service_role;
grant execute on function public.ripples_archive(int, text)                     to anon, authenticated, service_role;
grant execute on function public.ripples_brief(int, text)                       to anon, authenticated, service_role;
grant execute on function public.ripples_health()                               to anon, authenticated, service_role;
grant execute on function public.ripples_submit_play(text, int, jsonb, numeric) to anon, authenticated, service_role;
grant execute on function public.ripples_submit_call(text, int, text)           to anon, authenticated, service_role;
grant execute on function public.ripples_join(text, text, text, text[], text)   to anon, authenticated, service_role;
grant execute on function public.ripples_og_data(int)                           to service_role;
grant execute on function public.ripples_publish_bundle(int)                    to service_role;

notify pgrst, 'reload schema';
