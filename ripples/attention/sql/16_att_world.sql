-- 16_att_world (W7 att-world, 2026-09-25, applied as migration att_world_sources)
-- att-world: budgets, hosts and backfill routing for the PHYS/INST sources.
-- DEMARCATION Q6: no published limit -> 1 request / 5 s per host (IEM: <= 1 / 10 s per its service note), daily cadence.
-- Per-day caps allow the daily call(s) plus the one-off 400-day backfill (TSA year pages, IEM archive windows,
-- Citi Bike JC monthly files); they are still single-digit to low-double-digit requests per host per day.
update ripples.att_sources set per_run_cap = 10, per_day_cap = 20, spacing_ms = 5000, backfill_fn = 'att-world',
  reason = 'Q6: no published limit -> 1 req/5 s; 1-2 daily page fetches + one-off 2019..2026 year-page backfill (8 pages)'
 where source = 'tsa.pax';
update ripples.att_sources set per_run_cap = 8, per_day_cap = 20, spacing_ms = 5000, backfill_fn = 'att-world',
  reason = 'Q6: no published limit -> 1 req/5 s; 2 ComCat queries per run (felt, M4.5+), backfill in 100-day windows'
 where source = 'usgs.eq';
update ripples.att_sources set per_run_cap = 8, per_day_cap = 40, spacing_ms = 10000, backfill_fn = 'att-world',
  reason = 'IEM asks for gentle polling: 1 req/10 s; 1-2 daily requests + one-off 400-day archive backfill in windows'
 where source = 'iem.warn';
update ripples.att_sources set per_run_cap = 5, per_day_cap = 10, spacing_ms = 5000, backfill_fn = 'att-world',
  reason = 'Q6: no published limit -> 1 req/5 s; OpenFEMA $top<=10000 per call; 1 daily query + 400-day backfill'
 where source = 'fema.decl';
update ripples.att_sources set per_run_cap = 2, per_day_cap = 4, spacing_ms = 5000,
  reason = 'Q6: no published limit -> 1 req/5 s; one RSS snapshot per run (no history available)'
 where source = 'gdacs';
update ripples.att_sources set per_run_cap = 5, per_day_cap = 10, spacing_ms = 5000, backfill_fn = 'att-world',
  reason = 'Q6: Socrata unauthenticated (no app token), no numeric limit published -> 1 req/5 s; 1 daily query + backfill'
 where source = 'mta.ridership';
update ripples.att_sources set per_run_cap = 8, per_day_cap = 20, spacing_ms = 5000, backfill_fn = 'att-world',
  hosts = array['tripdata.s3.amazonaws.com'],
  reason = 'Q6: no published limit -> 1 req/5 s; bucket listing + JC monthly file (1-3 MB). NYC monthly files are ~1 GB: too large for the 110 s / CPU budget, reported partial'
 where source = 'citibike.trips';
update ripples.att_sources set per_run_cap = 4, per_day_cap = 8, spacing_ms = 5000, backfill_fn = 'att-world',
  hosts = array['raw.githubusercontent.com'],
  reason = 'Q6: no published limit -> 1 req/5 s; conditional GET (If-None-Match) so the 12 MB CSV is only downloaded when upstream changed; api.github.com not used'
 where source = 'hiringlab.postings';
