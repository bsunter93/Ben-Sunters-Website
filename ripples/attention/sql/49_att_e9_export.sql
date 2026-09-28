-- 49: E9 phase 1 export for the registered analysis (ripples/tools/experiments/e9_phase1.py, run on GitHub Actions).
-- Read-only, service_role only: daily pageviews per article (start date + contiguous views array) and female/male
-- baby-name counts by year keyed "name|sex".
create or replace function public.att_e9_export() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'pv', (select jsonb_object_agg(article, d) from (
             select article, jsonb_build_object('start', min(day), 'views', jsonb_agg(views order by day)) d
               from ripples.att_e9_pv group by article) a),
    'pv_days', (select jsonb_object_agg(article, n) from (select article, count(*) n, max(day) - min(day) + 1 span
               from ripples.att_e9_pv group by article) a),
    'names', (select jsonb_object_agg(k, ys) from (
             select name || '|' || sex k, jsonb_object_agg(year::text, n) ys from ripples.att_e9_names group by 1) b));
$$;
revoke all on function public.att_e9_export() from anon, authenticated, public;
grant execute on function public.att_e9_export() to service_role;
