-- One-off cleanup (run with execute_sql, not a migration), 2026-09-25 ~19:45 UTC, after att-news v13 (n9):
-- GKG candidates and edges written before n9 cannot be re-checked against the n9 rules (person breadth: 10 outlets or
-- 2 source countries; title stubs; kind vote), and the candidate merge keeps the older row's meta when its evidence is
-- higher, so today's GKG candidates and edges are deleted and rebuilt by the n9 runs. attention_obs is not touched.
delete from ripples.att_trend_candidates where source = 'gdelt.gkg' and day = '2026-09-25';
delete from ripples.att_edges where source = 'gdelt.gkg' and period = '2026-09-25';
