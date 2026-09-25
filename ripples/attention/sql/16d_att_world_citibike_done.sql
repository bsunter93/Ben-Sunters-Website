-- att-world: Citi Bike JC backfill completed 2026-09-25 18:57 UTC (13 months, JC-202508..JC-202608, 395 days).
-- The self-removing cron att-world-citibike-cap (sql/16c) fired at 19:07 UTC: per_day_cap 30 -> 4, today's att_budget
-- cap lowered to the amount used (21), job unscheduled. This file only corrects the reason text ("14-month" -> "13-month").
-- Applied via execute_sql (data-only update, no DDL).
update ripples.att_sources
   set reason = 'Q6: no published limit -> 1 req/5 s; steady state 4/day (bucket listing + 1 JC monthly file + NYC size listing, once a month after the 6th). The one-off 13-month JC backfill (JC-202508..JC-202608) ran at 30/day on 2026-09-25 and was reset automatically. NYC monthly files are ~1 GB: too large for the 110 s / CPU budget, reported partial'
 where source = 'citibike.trips';
