-- 47: cultural event catalog for the discovery engine (owner direction D-26, ledger 1280). Built 2026-09-27 from the
-- Wikidata Query Service via pg_net (keyless, honest UA; 4 queries).
--   ripples.att_cult_events(qid, typ, title, released, links, meta)
--     typ       film | tv | song | book
--     released  earliest day-precision date (films: P577 publication date, which can be a festival premiere before the
--               wide release; TV: P580 start time; songs/books: P577). meta.dates keeps every day-precise date so the lab
--               can pick an onset rule explicitly.
--     links     number of Wikipedia language editions (prominence; used to match ghost events)
-- Selection: English Wikipedia article exists; 2008-2024; sitelinks >= 35 (films) or >= 30 (tv, songs, books).
--   film types: Q11424 film, Q29168811 animated feature film, Q202866 animated film, Q24869 feature film, Q17517379
--   tv types:   Q5398426 television series, Q1259759 miniseries, Q581714 animated series, Q526877 web series,
--               Q63952888 anime television series
--   song types: Q7366 song, Q134556 single, Q105543609 musical work/composition, Q2188189 musical work
--   book types: Q7725634 literary work, Q8261 novel, Q47461344 written work, Q571 book
-- Gotcha: in SPARQL "wikibase:timePrecision 11." parses as the decimal 11.0 and matches nothing; write "11 ." instead.
-- Result 2026-09-27: 1,200 films, 280 TV series, 58 songs, 22 books.
create table if not exists ripples.att_cult_events (qid text primary key, typ text, title text, released date, links int,
  meta jsonb default '{}'::jsonb);
create table if not exists ripples.att_cult_req (typ text primary key, req_id bigint, status text);
alter table ripples.att_cult_events enable row level security;
alter table ripples.att_cult_req enable row level security;
revoke all on ripples.att_cult_events, ripples.att_cult_req from anon, authenticated, public;
