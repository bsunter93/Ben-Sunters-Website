-- Knock-On v5 / W1: migration ripples_v5_w1_verifier_fixes_2 (applied after 01-04). Net effect below; the same
-- bodies are in sql/02 (full current definitions) and, where re-declared, sql/04, so any install order ends identical.
-- 1. _canon pins extra_float_digits = 0: the ledger hash no longer depends on the session's float output setting.
-- 2. _puzzle_json serves payload.status from the row; _ledger_input hashes that same row status.
-- 3. ripples_submit_call closes at the earlier of the puzzle period's end (07:30 UTC on puzzle_date + 1) and
--    00:00 UTC after window_start.
-- 4. ripples_publish_bundle(explicit n) applies the 07:20 UTC cutoff to built live puzzles (error 'too_early').

-- PuzzlePayload with copy overlay (ai/template headline from ripples.copy; fixture is never overlaid)
create or replace function ripples._puzzle_json(p_n int) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare r ripples.puzzles; h record; out jsonb;
begin
  select * into r from ripples.puzzles where n = p_n;
  if not found or r.payload is null then return null; end if;
  out := r.payload;
  -- status is served from the row (build writes 'built'; publish flips the row), never the stale stored value
  if jsonb_typeof(out) = 'object' then out := out || jsonb_build_object('status', r.status); end if;
  if r.kind <> 'fixture' then
    select c.text, c.source into h from ripples.copy c
     where c.n = p_n and c.kind = 'headline' and coalesce(c.i, 0) = 0;
    if found then
      out := jsonb_set(out, '{headline}', jsonb_build_object('text', h.text, 'source', h.source), true);
    end if;
  end if;
  return out;
end $$;

-- Canonical JSON for hashing: every number is round-tripped through float8 (15 significant digits,
-- plain notation), so a JSON file re-serialised by JS/Python hashes the same as the stored jsonb.
-- extra_float_digits is pinned to 0 (float8 text = %.15g) so the hash never depends on the caller's session
-- (pgjdbc/npgsql set 3, which would give shortest-round-trip 17-digit output and a different hash).
create or replace function ripples._canon(p jsonb) returns jsonb
language plpgsql immutable set search_path = '' set extra_float_digits = 0 as $$
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
-- "status" is taken from the row (as _puzzle_json serves it), so it is always "published" for a ledgered row.
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
    'puzzle', case when jsonb_typeof(r.payload) = 'object'
                   then (r.payload - 'headline') || jsonb_build_object('status', r.status) else r.payload end,
    'reveal', rv, 'callit', cl));
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
  -- calls close at the EARLIER of (a) the end of the puzzle's period (07:30 UTC rollover on puzzle_date + 1) and
  -- (b) 00:00 UTC after window_start, when the first window day's daily pageviews become public (no look-ahead).
  -- With window_start = puzzle_date (+0) that is 00:00 UTC; with window_start = puzzle_date + 1 (recommended to
  -- W2) calls stay open for the whole puzzle period.
  if r.kind = 'live' and now() >= least(((r.puzzle_date + 1) + time '07:30') at time zone 'utc',
                                        ((c.window_start + 1)::timestamp) at time zone 'utc') then
    raise exception 'closed';
  end if;
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

create or replace function public.ripples_publish_bundle(p_n int default null) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare nn int := p_n; r ripples.puzzles; track jsonb; csv jsonb := '[]'::jsonb; recent jsonb; ledger_head text;
        ledger jsonb;
begin
  perform ripples._purge_salts();
  if nn is null then
    -- newest live puzzle dated <= the UTC date as of 07:20 (the veto deadline): the 07:25 run pre-stages today's
    -- puzzle, but an earlier call can never publish (and so ledger / lock against a veto) a puzzle still in review
    select n into nn from ripples.puzzles
     where kind = 'live' and status in ('built', 'published')
       and puzzle_date <= ((now() at time zone 'utc') - interval '7 hours 20 minutes')::date
     order by n desc limit 1;
  end if;
  if nn is not null then
    select * into r from ripples.puzzles where n = nn;
    if not found then raise exception 'not_found'; end if;
    if r.status in ('vetoed', 'delayed') then raise exception 'not_publishable'; end if;
    -- the same 07:20 UTC veto cutoff applies to an explicit n: a built live puzzle dated after the UTC date as of
    -- 07:20 is still in review, so it can't be published (ledgered, locked against a veto) early
    if r.kind = 'live' and r.status = 'built'
       and r.puzzle_date > ((now() at time zone 'utc') - interval '7 hours 20 minutes')::date then
      raise exception 'too_early';
    end if;
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

-- ======================= grants (unchanged; re-asserted) =======================
revoke execute on all functions in schema ripples from public, anon, authenticated;
revoke execute on function public.ripples_submit_call(text, int, text)          from public, anon, authenticated;
revoke execute on function public.ripples_publish_bundle(int)                   from public, anon, authenticated;
grant execute on function public.ripples_submit_call(text, int, text)           to anon, authenticated, service_role;
grant execute on function public.ripples_publish_bundle(int)                    to service_role;

notify pgrst, 'reload schema';
