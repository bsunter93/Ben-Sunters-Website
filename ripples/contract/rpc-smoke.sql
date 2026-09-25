-- Knock-On v5 / W1: RPC smoke test. Run as postgres (Supabase SQL editor / MCP execute_sql).
-- Exercises every W1 RPC including error paths, prints one row per check, and cleans up after itself
-- (removes its plays/calls for n=0, its rate-limit rows and its example.com waitlist rows).
-- Expected: every row has pass = true.
create temp table if not exists _smoke(k serial, chk text, pass boolean, detail text);
truncate _smoke;

do $smoke$
declare
  v jsonb; v2 jsonb; ok boolean; msg text; c int; c2 int; i int;
  cli1 text := 'smokeClient_AAAAAAAAAAAA01';
  cli2 text := 'smokeClient_AAAAAAAAAAAA02';
  ip_a text := '203.0.113.7';      -- TEST-NET-3 addresses only
  ip_b text := '203.0.113.8';
  ip_c text := '203.0.113.9';
  good jsonb := '[["c"],["b","a"],["a","b"]]';   -- fixture answers: c, a, d  -> codes 2,1,0
  hdr text;
  procedure_ok boolean;
begin
  -- ---------------- read RPCs ----------------
  v := public.ripples_puzzle(0);
  insert into _smoke(chk, pass, detail) values ('puzzle(0) n=0, 3 rounds, kind fixture',
    v->>'n' = '0' and jsonb_array_length(v->'rounds') = 3 and v->>'kind' = 'fixture', left(v::text, 60));
  insert into _smoke(chk, pass, detail) values ('puzzle(0) has no answers (no answer/answer_qid/multiple keys)',
    v::text !~ '"answer"|"answer_qid"|"multiple": 6.2', null);
  insert into _smoke(chk, pass, detail) values ('answer_h = sha256(n|i|qid) for every round',
    (select bool_and(r->>'answer_h' = encode(extensions.digest('0|' || (r->>'i') || '|' || (a->>'qid'), 'sha256'), 'hex'))
       from jsonb_array_elements(v->'rounds') r
       join jsonb_array_elements((select answers from ripples.puzzles where n = 0)) a on (a->>'i') = (r->>'i')), null);
  insert into _smoke(chk, pass, detail) values ('answer_h differs from every decoy hash',
    not exists (select 1 from jsonb_array_elements(v->'rounds') r, jsonb_array_elements(r->'options') o,
                       jsonb_array_elements((select answers from ripples.puzzles where n = 0)) a
                 where (a->>'i') = (r->>'i') and o->>'qid' <> a->>'qid'
                   and encode(extensions.digest('0|' || (r->>'i') || '|' || (o->>'qid'), 'sha256'), 'hex') = r->>'answer_h'), null);
  v := public.ripples_reveal(0);
  insert into _smoke(chk, pass, detail) values ('reveal(0) has 3 rounds and final_multiple 3.8',
    jsonb_array_length(v->'rounds') = 3 and (v->>'final_multiple')::numeric = 3.8, null);
  insert into _smoke(chk, pass, detail) values ('puzzle/reveal of unknown n are null',
    public.ripples_puzzle(987654) is null and public.ripples_reveal(987654) is null and public.ripples_puzzle(-987654) is null, null);
  v := public.ripples_latest();
  insert into _smoke(chk, pass, detail) values ('latest() never returns the fixture',
    coalesce(v->>'n', '') <> '0' and coalesce(v #>> '{puzzle,kind}', '') <> 'fixture', v::text);
  insert into _smoke(chk, pass, detail) values ('latest() delayed + puzzle null when no live puzzle is published',
    exists (select 1 from ripples.puzzles where kind = 'live' and status = 'published')
    or (v->>'status' = 'delayed' and v->'puzzle' = 'null'::jsonb), v::text);
  v := public.ripples_callit(0);
  insert into _smoke(chk, pass, detail) values ('callit(0): 4 options, 1 hit, 1 miss, 2 pending; urls only when resolved',
    jsonb_array_length(v->'options') = 4
    and (select count(*) from jsonb_array_elements(v->'options') o where o->>'outcome' = 'hit') = 1
    and (select count(*) from jsonb_array_elements(v->'options') o where o->>'outcome' = 'miss') = 1
    and (select bool_and((o->>'outcome' = 'pending') = (o->'url' = 'null'::jsonb)) from jsonb_array_elements(v->'options') o),
    null);
  v := public.ripples_board(0);
  insert into _smoke(chk, pass, detail) values ('board(0): all 4 quadrants + a sensitive row with quadrant null',
    (select count(distinct t->>'quadrant') from jsonb_array_elements(v->'trends') t where t->>'quadrant' is not null) = 4
    and exists (select 1 from jsonb_array_elements(v->'trends') t where (t->>'sensitive')::boolean and t->'quadrant' = 'null'::jsonb), null);
  insert into _smoke(chk, pass, detail) values ('board(null) is null or a live board (never the fixture)',
    coalesce(public.ripples_board(null)->>'n', 'x') <> '0', null);
  v := public.ripples_archive(60, 'fixture');
  insert into _smoke(chk, pass, detail) values ('archive(fixture) path', v->0->>'path' = '👤📍🎬·🎵🏅', v->0->>'path');
  insert into _smoke(chk, pass, detail) values ('archive(live) excludes fixture',
    not exists (select 1 from jsonb_array_elements(public.ripples_archive(500, 'all')) a where a->>'kind' = 'fixture'), null);
  v := public.ripples_brief(7, null);
  insert into _smoke(chk, pass, detail) values ('brief(7) shape', v ?& array['from','to','category','intro','reconstructed','items'], null);
  insert into _smoke(chk, pass, detail) values ('brief(bad category) is empty',
    jsonb_array_length(public.ripples_brief(7, 'not_a_category')->'items') = 0, null);
  v := public.ripples_health();
  insert into _smoke(chk, pass, detail) values ('health shape',
    v ?& array['latest_n','published_at','stale','stage','wm_calls','errors','clickstream_month'], v::text);
  v := public.ripples_og_data(0);
  insert into _smoke(chk, pass, detail) values ('og_data(0): R=3, answer multiples present',
    (v->>'R')::int = 3 and (v #>> '{rounds,0,multiple}')::numeric = 6.2 and (v #>> '{rounds,2,multiple}')::numeric = 3.8, null);

  -- ---------------- stats ----------------
  delete from ripples.plays where n = 0;
  delete from ripples.calls where n = 0;
  v := public.ripples_stats(0);
  insert into _smoke(chk, pass, detail) values ('stats(0) shown=false below min_players, arrays null',
    v->>'shown' = 'false' and v->'rounds' = 'null'::jsonb and v->'score_hist' = 'null'::jsonb and v->'you' = 'null'::jsonb, v::text);

  -- ---------------- submit_play ----------------
  perform set_config('request.headers', json_build_object('cf-connecting-ip', ip_a, 'cf-ipcountry', 'gb')::text, true);
  select count(*) into c from ripples.plays where n = 0;
  v := public.ripples_submit_play(cli1, 0, good, 3.8);
  select count(*) into c2 from ripples.plays where n = 0;
  insert into _smoke(chk, pass, detail) values ('submit_play valid inserts 1 row; server score 2+1+0+2=5 of 8',
    c2 = c + 1 and (v #>> '{you,score}')::int = 5 and (v #>> '{you,max}')::int = 8, v::text);
  insert into _smoke(chk, pass, detail) values ('plays row stores hashes + country, not raw ids',
    exists (select 1 from ripples.plays where n = 0 and client_hash ~ '^[0-9a-f]{64}$' and ip_hash ~ '^[0-9a-f]{64}$'
             and country = 'GB' and codes = '{2,1,0}' and client_hash <> cli1), null);
  v2 := public.ripples_submit_play(cli1, 0, good, 3.8);
  select count(*) into c from ripples.plays where n = 0;
  insert into _smoke(chk, pass, detail) values ('duplicate submit_play inserts 0 rows, same players count',
    c = c2 and v2->'players' = v->'players', v2->>'players');
  -- a different second answer does not change the stored play
  v2 := public.ripples_submit_play(cli1, 0, '[["a","c"],["a"],["d"]]', 10);
  insert into _smoke(chk, pass, detail) values ('duplicate with different picks keeps the first score',
    (v2 #>> '{you,score}')::int = 5, v2->>'you');

  foreach hdr in array array[
      '[["c"],["a"]]',                 -- wrong round count
      '[["c","a"],["a"],["d"]]',       -- second pick after a correct first pick
      '[["e"],["a"],["d"]]',           -- bad option id
      '[["c"],["a","a"],["d"]]',       -- duplicate pick
      '[["c"],[],["d"]]',              -- empty round
      '[["c"],["a","b","c"],["d"]]',   -- 3 picks
      '{"a":1}',                       -- not an array
      '[[1],["a"],["d"]]'] loop        -- non-string id
    begin
      perform public.ripples_submit_play('smokeClient_BAD_PICKS_01', 0, hdr::jsonb, 3.8);
      ok := false; msg := 'no error';
    exception when others then ok := (sqlerrm = 'invalid'); msg := sqlerrm;
    end;
    insert into _smoke(chk, pass, detail) values ('submit_play malformed picks ' || hdr || ' raises invalid', ok, msg);
  end loop;
  foreach hdr in array array['short', 'has space in it xxxxxxxxxx', repeat('x', 65)] loop
    begin
      perform public.ripples_submit_play(hdr, 0, good, 3.8); ok := false; msg := 'no error';
    exception when others then ok := (sqlerrm = 'invalid'); msg := sqlerrm;
    end;
    insert into _smoke(chk, pass, detail) values ('submit_play bad client regex raises invalid', ok, msg);
  end loop;
  foreach hdr in array array['1.49', '100.01', '-3'] loop
    begin
      perform public.ripples_submit_play(cli2, 0, good, hdr::numeric); ok := false; msg := 'no error';
    exception when others then ok := (sqlerrm = 'invalid'); msg := sqlerrm;
    end;
    insert into _smoke(chk, pass, detail) values ('submit_play p_mag ' || hdr || ' raises invalid', ok, msg);
  end loop;
  begin
    perform public.ripples_submit_play(cli2, 987654, good, 3.8); ok := false; msg := 'no error';
  exception when others then ok := (sqlerrm = 'closed'); msg := sqlerrm;
  end;
  insert into _smoke(chk, pass, detail) values ('submit_play unknown/unpublished n raises closed', ok, msg);

  -- rate limit: IP b makes 20 accepted calls (distinct clients), the 21st raises rate_limited
  perform set_config('request.headers', json_build_object('x-forwarded-for', ip_b || ', 10.0.0.1')::text, true);
  for i in 1..20 loop
    perform public.ripples_submit_play('smokeRate_' || lpad(i::text, 8, '0'), 0, good, 2.0);
  end loop;
  begin
    perform public.ripples_submit_play('smokeRate_00000021', 0, good, 2.0); ok := false; msg := 'no error';
  exception when others then ok := (sqlerrm = 'rate_limited'); msg := sqlerrm;
  end;
  insert into _smoke(chk, pass, detail) values ('21st submit_play from one IP hash (x-forwarded-for) raises rate_limited', ok, msg);
  insert into _smoke(chk, pass, detail) values ('rate_limited call inserted nothing',
    not exists (select 1 from ripples.plays p where p.n = 0 and p.client_hash = ripples._hash('smokeRate_00000021', (select puzzle_date from ripples.puzzles where n = 0))), null);
  -- a different IP is unaffected
  perform set_config('request.headers', json_build_object('cf-connecting-ip', ip_c)::text, true);
  v := public.ripples_submit_play('smokeRate_OTHER_IP_01', 0, good, 2.0);
  insert into _smoke(chk, pass, detail) values ('other IP still accepted', v ? 'players', v->>'players');

  -- 22 players now < 30: still hidden. Add 8 more to cross min_players and check shown=true + percentile
  perform set_config('request.headers', json_build_object('cf-connecting-ip', ip_a)::text, true);
  for i in 1..8 loop
    perform public.ripples_submit_play('smokeShown_' || lpad(i::text, 8, '0'), 0, '[["a","b"],["b","c"],["a","b"]]', 90);
  end loop;
  v := public.ripples_stats(0);
  insert into _smoke(chk, pass, detail) values ('stats(0) shown=true at >= 30 players with rounds/score_hist/median',
    v->>'shown' = 'true' and (v->>'players')::int >= 30 and jsonb_array_length(v->'rounds') = 3
    and jsonb_array_length(v->'score_hist') = 9 and v->'mag_median_x' <> 'null'::jsonb and v->'you' = 'null'::jsonb, left(v::text, 200));
  v := public.ripples_submit_play(cli1, 0, good, 3.8);
  insert into _smoke(chk, pass, detail) values ('duplicate at >=30 players returns percentile',
    (v #>> '{you,percentile}') is not null, v->>'you');

  -- ---------------- submit_call ----------------
  perform set_config('request.headers', json_build_object('cf-connecting-ip', ip_a)::text, true);
  v := public.ripples_submit_call(cli1, 0, 'Q999990043');
  select count(*) into c from ripples.calls where n = 0;
  insert into _smoke(chk, pass, detail) values ('submit_call valid -> ok, 1 row, split null below min',
    v->>'ok' = 'true' and v->'split' = 'null'::jsonb and c = 1, v::text);
  v := public.ripples_submit_call(cli1, 0, 'Q999990044');
  select count(*) into c2 from ripples.calls where n = 0;
  insert into _smoke(chk, pass, detail) values ('second call by same client is ignored (one per client per n)',
    c2 = 1 and (select qid from ripples.calls where n = 0) = 'Q999990043', null);
  begin
    perform public.ripples_submit_call(cli2, 0, 'Q42'); ok := false; msg := 'no error';
  exception when others then ok := (sqlerrm = 'invalid'); msg := sqlerrm;
  end;
  insert into _smoke(chk, pass, detail) values ('submit_call with a QID that is not an option raises invalid', ok, msg);
  begin
    perform public.ripples_submit_call(cli2, 0, 'not-a-qid'); ok := false; msg := 'no error';
  exception when others then ok := (sqlerrm = 'invalid'); msg := sqlerrm;
  end;
  insert into _smoke(chk, pass, detail) values ('submit_call malformed QID raises invalid', ok, msg);
  perform set_config('request.headers', json_build_object('cf-connecting-ip', ip_c)::text, true);
  for i in 1..19 loop   -- ip_c: 20 allowed per day
    perform public.ripples_submit_call('smokeCall_' || lpad(i::text, 8, '0'), 0, 'Q999990041');
  end loop;
  perform public.ripples_submit_call('smokeCall_00000020', 0, 'Q999990041');
  begin
    perform public.ripples_submit_call('smokeCall_00000021', 0, 'Q999990041'); ok := false; msg := 'no error';
  exception when others then ok := (sqlerrm = 'rate_limited'); msg := sqlerrm;
  end;
  insert into _smoke(chk, pass, detail) values ('21st submit_call from one IP raises rate_limited', ok, msg);
  v := public.ripples_callit(0);
  insert into _smoke(chk, pass, detail) values ('callit crowd_pct appears once calls >= min_players (21 calls < 30 -> null)',
    (select bool_and(o->'crowd_pct' = 'null'::jsonb) from jsonb_array_elements(v->'options') o), null);

  -- ---------------- join ----------------
  perform set_config('request.headers', json_build_object('cf-connecting-ip', '198.51.100.20')::text, true);
  select count(*) into c from ripples.waitlist;
  v := public.ripples_join('not-an-email', null, 'free', null, 'smoke');
  select count(*) into c2 from ripples.waitlist;
  insert into _smoke(chk, pass, detail) values ('join(not-an-email) -> {"ok":true}, no row', v = '{"ok":true}'::jsonb and c2 = c, v::text);
  v := public.ripples_join('  Smoke.Test+W1@Example.COM ', 'creator', 'radar5', array['music','tech'], 'smoke');
  select count(*) into c2 from ripples.waitlist;
  insert into _smoke(chk, pass, detail) values ('join(valid) -> {"ok":true}, 1 row, email lowercased+trimmed',
    v = '{"ok":true}'::jsonb and c2 = c + 1
    and exists (select 1 from ripples.waitlist where email_norm = 'smoke.test+w1@example.com' and price = 'radar5'), v::text);
  v := public.ripples_join('smoke.test+w1@example.com', null, 'report149', null, 'smoke');
  select count(*) into c from ripples.waitlist;
  insert into _smoke(chk, pass, detail) values ('join upsert on email_norm (no duplicate, price updated, role kept)',
    c = c2 and exists (select 1 from ripples.waitlist where email_norm = 'smoke.test+w1@example.com' and price = 'report149' and role = 'creator'), null);
  v := public.ripples_join('smoke.bad.enum@example.com', 'ceo', 'free', null, 'smoke');
  v2 := public.ripples_join('smoke.bad.topic@example.com', null, 'free', array['crypto'], 'smoke');
  insert into _smoke(chk, pass, detail) values ('join with bad role / topic -> ok but no row',
    v = '{"ok":true}'::jsonb and v2 = '{"ok":true}'::jsonb
    and not exists (select 1 from ripples.waitlist where email_norm in ('smoke.bad.enum@example.com', 'smoke.bad.topic@example.com')), null);
  -- 5 per IP per day: this IP has used 5 now; the 6th valid email is silently dropped
  v := public.ripples_join('smoke.sixth@example.com', null, 'free', null, 'smoke');
  insert into _smoke(chk, pass, detail) values ('6th join from one IP is silently dropped (still ok:true)',
    v = '{"ok":true}'::jsonb and not exists (select 1 from ripples.waitlist where email_norm = 'smoke.sixth@example.com'), null);
  insert into _smoke(chk, pass, detail) values ('no public ripples_* function result contains an email address',
    (public.ripples_latest()::text || coalesce(public.ripples_puzzle(0)::text, '') || coalesce(public.ripples_reveal(0)::text, '')
     || coalesce(public.ripples_stats(0)::text, '') || coalesce(public.ripples_callit(0)::text, '') || coalesce(public.ripples_board(0)::text, '')
     || public.ripples_archive(500, 'all')::text || public.ripples_brief(60, null)::text || public.ripples_health()::text)
    !~ '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}', null);

  -- ---------------- permissions ----------------
  execute 'set local role anon';
  begin perform 1 from ripples.plays limit 1; ok := false; msg := 'readable';
  exception when insufficient_privilege then ok := true; msg := sqlerrm; end;
  execute 'reset role';
  insert into _smoke(chk, pass, detail) values ('anon: select ripples.plays -> permission denied', ok, msg);
  execute 'set local role anon';
  begin perform 1 from ripples.waitlist limit 1; ok := false; msg := 'readable';
  exception when insufficient_privilege then ok := true; msg := sqlerrm; end;
  execute 'reset role';
  insert into _smoke(chk, pass, detail) values ('anon: select ripples.waitlist -> permission denied', ok, msg);
  execute 'set local role anon';
  begin perform public.ripples_publish_bundle(0); ok := false; msg := 'callable';
  exception when insufficient_privilege then ok := true; msg := sqlerrm; end;
  execute 'reset role';
  insert into _smoke(chk, pass, detail) values ('anon: ripples_publish_bundle(0) -> permission denied', ok, msg);
  execute 'set local role anon';
  begin perform public.ripples_og_data(0); ok := false; msg := 'callable';
  exception when insufficient_privilege then ok := true; msg := sqlerrm; end;
  execute 'reset role';
  insert into _smoke(chk, pass, detail) values ('anon: ripples_og_data(0) -> permission denied', ok, msg);
  execute 'set local role authenticated';
  begin perform ripples._hash('x'); ok := false; msg := 'callable';
  exception when insufficient_privilege then ok := true; msg := sqlerrm; end;
  execute 'reset role';
  insert into _smoke(chk, pass, detail) values ('authenticated: internal ripples._hash -> permission denied', ok, msg);
  execute 'set local role anon';
  begin v := public.ripples_puzzle(0); ok := v->>'n' = '0'; msg := 'ok';
  exception when others then ok := false; msg := sqlerrm; end;
  execute 'reset role';
  insert into _smoke(chk, pass, detail) values ('anon: ripples_puzzle(0) works', ok, msg);

  -- ---------------- publish_bundle (service) on the fixture ----------------
  v := public.ripples_publish_bundle(0);
  insert into _smoke(chk, pass, detail) values ('publish_bundle(0): keys, fixture stays status fixture, no csv, no ledger',
    v ?& array['latest','puzzle','reveal','callit','board','archive','track','csv_rows']
    and v #>> '{puzzle,n}' = '0' and jsonb_array_length(v->'csv_rows') = 0
    and (select status from ripples.puzzles where n = 0) = 'fixture'
    and not exists (select 1 from ripples.ledger where n = 0), null);
  v := public.ripples_publish_bundle(null);
  insert into _smoke(chk, pass, detail) values ('publish_bundle(null) with no live puzzle: latest delayed',
    exists (select 1 from ripples.puzzles where kind = 'live')
    or (v->'puzzle' = 'null'::jsonb and v #>> '{latest,status}' = 'delayed'), left(v::text, 120));

  -- ---------------- cleanup ----------------
  delete from ripples.plays where n = 0;
  delete from ripples.calls where n = 0;
  delete from ripples.waitlist where email_norm like 'smoke%@example.com';
  delete from ripples.rate_limits
   where day = (now() at time zone 'utc')::date
     and bucket in (select b || ripples._hash(ip) from unnest(array['play:','call:','join:']) b,
                    unnest(array[ip_a, ip_b, ip_c, '198.51.100.20']) ip);
end
$smoke$;


-- ---------------------------------------------------------------------------------------------
-- Part 2: live-puzzle lifecycle, fully rolled back (a subtransaction is aborted on purpose at the end).
-- Temporarily moves config.epoch so that a synthetic live n=20 is "today", then checks visibility,
-- publish_bundle (status, ledger chain, csv rows), copy overlay, brief, archive, og_data, health,
-- the closed window for submit_play/submit_call, and not_publishable for vetoed puzzles.
-- ---------------------------------------------------------------------------------------------
do $life$
declare
  res jsonb := '[]'; v jsonb; b jsonb; cur date := ripples._current_date(); fx ripples.puzzles; ok boolean; msg text;
  l19 ripples.ledger; l20 ripples.ledger;
  procedure_dummy int;
begin
  begin
    update ripples.config set value = to_jsonb((cur - 20)::text) where key = 'epoch';
    select * into fx from ripples.puzzles where n = 0;
    insert into ripples.puzzles (n, kind, puzzle_date, data_date, status, payload, reveal, board, answers, final_multiple)
    select k.n, 'live', cur + (k.n - 20), cur + (k.n - 21), k.st,
           fx.payload || jsonb_build_object('n', k.n, 'kind', 'live', 'status', 'published',
                                            'date', cur + (k.n - 20), 'data_date', cur + (k.n - 21)),
           fx.reveal || jsonb_build_object('n', k.n), fx.board || jsonb_build_object('n', k.n), fx.answers, fx.final_multiple
      from (values (10, 'published'), (19, 'built'), (20, 'built'), (21, 'published'), (18, 'vetoed')) k(n, st);
    insert into ripples.callit (n, qid, title, emoji, category, baseline_median, model_p, window_start, window_end, outcome)
    select k.n, c.qid, c.title, c.emoji, c.category, c.baseline_median, c.model_p, cur + (k.n - 20), cur + (k.n - 14), 'pending'
      from ripples.callit c, (values (19), (20)) k(n) where c.n = 0;

    v := public.ripples_latest();
    res := res || jsonb_build_object('chk', 'built (unpublished) puzzles are invisible; future published n=21 hidden; latest = n10 delayed',
      'pass', public.ripples_puzzle(20) is null and public.ripples_puzzle(21) is null and v->>'n' = '10' and v->>'status' = 'delayed',
      'detail', v->>'n');

    b := public.ripples_publish_bundle(19);
    b := public.ripples_publish_bundle(20);
    select * into l19 from ripples.ledger where n = 19;
    select * into l20 from ripples.ledger where n = 20;
    res := res || jsonb_build_object('chk', 'publish_bundle(20) marks published; latest=20 published',
      'pass', b->>'n' = '20' and (select status from ripples.puzzles where n = 20) = 'published'
              and (select published_at from ripples.puzzles where n = 20) is not null
              and b #>> '{latest,n}' = '20' and b #>> '{latest,status}' = 'published' and b #>> '{puzzle,n}' = '20',
      'detail', b->'latest'->>'status');
    res := res || jsonb_build_object('chk', 'publish_bundle csv_rows: 3 Wikimedia-only rows with the §10 columns',
      'pass', jsonb_array_length(b->'csv_rows') = 3
              and (select bool_and(r ?& array['date','n','round','parent','answer','multiple','z','lag_days','fluke','p_time','category']
                                   and (select count(*) from jsonb_object_keys(r)) = 11) from jsonb_array_elements(b->'csv_rows') r),
      'detail', b->'csv_rows'->0);
    res := res || jsonb_build_object('chk', 'publish_bundle recent_callit lists n=20 and n=19; archive has live 21? no',
      'pass', jsonb_array_length(b->'recent_callit') = 2
              and not exists (select 1 from jsonb_array_elements(b->'archive') a where a->>'n' in ('21', '0', '18')),
      'detail', (select string_agg(a->>'n', ',') from jsonb_array_elements(b->'archive') a));
    res := res || jsonb_build_object('chk', 'ledger: payload_hash and chain_hash recompute; n20.prev = n19.chain; genesis prev = 64 zeros',
      'pass', l19.prev_hash = repeat('0', 64) and l20.prev_hash = l19.chain_hash
              and l20.chain_hash = encode(extensions.digest(l20.prev_hash || l20.payload_hash, 'sha256'), 'hex')
              and l20.payload_hash = encode(extensions.digest(jsonb_build_object('n', 20,
                    'payload', (select payload from ripples.puzzles where n = 20), 'reveal', (select reveal from ripples.puzzles where n = 20),
                    'callit', (select jsonb_agg(jsonb_build_array(qid, model_p) order by qid) from ripples.callit where n = 20))::text, 'sha256'), 'hex')
              and b->>'ledger_head' = l20.chain_hash,
      'detail', l20.chain_hash);
    v := public.ripples_publish_bundle(null);
    res := res || jsonb_build_object('chk', 'publish_bundle(null) picks the newest built/published live puzzle dated <= UTC today',
      'pass', (v->>'n')::int = (select max(n) from ripples.puzzles where kind = 'live' and status in ('built', 'published')
                                   and puzzle_date <= (now() at time zone 'utc')::date)
              and v #>> '{latest,n}' = '20',
      'detail', v->>'n');
    b := public.ripples_publish_bundle(20);
    res := res || jsonb_build_object('chk', 'publish_bundle is idempotent (ledger unchanged on re-run)',
      'pass', (select chain_hash from ripples.ledger where n = 20) = l20.chain_hash and (select count(*) from ripples.ledger where n in (19, 20)) = 2,
      'detail', null);
    begin
      perform public.ripples_publish_bundle(18); ok := false; msg := 'no error';
    exception when others then ok := (sqlerrm = 'not_publishable'); msg := sqlerrm;
    end;
    res := res || jsonb_build_object('chk', 'publish_bundle(vetoed) raises not_publishable', 'pass', ok, 'detail', msg);

    insert into ripples.copy (n, i, kind, text, source) values
      (20, null, 'headline', 'TEST ai headline', 'ai'), (20, 2, 'caption', 'TEST ai caption for round 2', 'ai'),
      (0, null, 'headline', 'TEST must not overlay fixture', 'ai'), (19, null, 'brief_intro', 'TEST brief intro', 'ai');
    v := public.ripples_puzzle(20);
    res := res || jsonb_build_object('chk', 'copy overlay: ai headline + round-2 caption replace template; fixture untouched',
      'pass', v #>> '{headline,source}' = 'ai' and public.ripples_reveal(20) #>> '{rounds,1,caption,source}' = 'ai'
              and public.ripples_reveal(20) #>> '{rounds,0,caption,source}' = 'template'
              and public.ripples_puzzle(0) #>> '{headline,source}' = 'template',
      'detail', v #>> '{headline,text}');
    v := public.ripples_brief(7, null);
    res := res || jsonb_build_object('chk', 'brief(7): only n19 (n10 is outside 7 days, today''s n20 never included); intro from copy',
      'pass', (select bool_and((i->>'n')::int in (19, 10)) from jsonb_array_elements(v->'items') i)
              and jsonb_array_length(v->'items') = 3 and v->>'reconstructed' = 'false' and v #>> '{intro,text}' = 'TEST brief intro',
      'detail', jsonb_array_length(v->'items'));
    v := public.ripples_brief(30, 'sport');
    res := res || jsonb_build_object('chk', 'brief(30, sport) filters by answer category',
      'pass', (select bool_and(i->>'category' = 'sport') from jsonb_array_elements(v->'items') i) and jsonb_array_length(v->'items') = 2,
      'detail', jsonb_array_length(v->'items'));
    v := public.ripples_og_data(null);
    res := res || jsonb_build_object('chk', 'og_data(null) -> latest live n=20', 'pass', v->>'n' = '20', 'detail', v->>'n');
    v := public.ripples_health();
    res := res || jsonb_build_object('chk', 'health: latest_n 20, stale false', 'pass', v->>'latest_n' = '20' and v->>'stale' = 'false', 'detail', v::text);
    v := public.ripples_board(null);
    res := res || jsonb_build_object('chk', 'board(null) -> board of n=20', 'pass', v->>'n' = '20', 'detail', null);

    perform set_config('request.headers', '{"cf-connecting-ip":"203.0.113.77"}', true);
    v := public.ripples_submit_play('lifecycleClient_000001', 20, '[["c"],["a"],["d"]]', 3.8);
    res := res || jsonb_build_object('chk', 'submit_play on today''s live puzzle: perfect 8/8',
      'pass', (v #>> '{you,score}')::int = 8, 'detail', v->>'you');
    begin
      perform public.ripples_submit_play('lifecycleClient_000001', 10, '[["c"],["a"],["d"]]', 3.8); ok := false; msg := 'no error';
    exception when others then ok := (sqlerrm = 'closed'); msg := sqlerrm;
    end;
    res := res || jsonb_build_object('chk', 'submit_play on n older than latest-7 raises closed', 'pass', ok, 'detail', msg);
    begin
      perform public.ripples_submit_play('lifecycleClient_000001', 21, '[["c"],["a"],["d"]]', 3.8); ok := false; msg := 'no error';
    exception when others then ok := (sqlerrm = 'closed'); msg := sqlerrm;
    end;
    res := res || jsonb_build_object('chk', 'submit_play on a future puzzle raises closed', 'pass', ok, 'detail', msg);
    v := public.ripples_submit_call('lifecycleClient_000001', 20, 'Q999990041');
    res := res || jsonb_build_object('chk', 'submit_call on today''s puzzle ok', 'pass', v->>'ok' = 'true', 'detail', v::text);
    if (now() at time zone 'utc')::date > cur then
      begin
        perform public.ripples_submit_call('lifecycleClient_000001', 19, 'Q999990041'); ok := false; msg := 'no error';
      exception when others then ok := (sqlerrm = 'closed'); msg := sqlerrm;
      end;
      res := res || jsonb_build_object('chk', 'submit_call after the window start (+1 day grace) raises closed', 'pass', ok, 'detail', msg);
    end if;

    raise exception 'rollback_lifecycle';
  exception when others then
    if sqlerrm <> 'rollback_lifecycle' then
      res := res || jsonb_build_object('chk', 'lifecycle aborted unexpectedly', 'pass', false, 'detail', sqlerrm);
    end if;
  end;
  insert into _smoke(chk, pass, detail)
  select 'lifecycle: ' || (r->>'chk'), (r->>'pass')::boolean, left(r->>'detail', 200) from jsonb_array_elements(res) r;
  insert into _smoke(chk, pass, detail) values ('lifecycle rolled back (epoch restored, no synthetic rows, no ledger rows)',
    ripples._epoch() = date '2026-09-25'
    and not exists (select 1 from ripples.puzzles where n in (10, 18, 19, 20, 21) and payload->>'seed' like '%Test Seed Article%')
    and not exists (select 1 from ripples.ledger l join ripples.puzzles p on p.n = l.n where p.kind = 'fixture')
    and not exists (select 1 from ripples.copy where text like 'TEST ai %' or text = 'TEST brief intro'), null);
end
$life$;

select k, pass, chk, detail from _smoke order by k;
