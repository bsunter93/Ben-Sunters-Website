-- 44: E1 method bake-off extract (experiments program, ledger 1272; ripples/docs/experiments.md).
-- Placebo-only: for every eligible b9 flood event it returns the DONOR counties (same state, no declaration of any kind in
-- [-12, +24] months) with their pre-period path and window outcome. The real designated counties are never exported, so
-- choosing a method cannot peek at the real effect. The bake-off itself runs outside the database
-- (ripples/tools/experiments/e1_bakeoff.py).
create or replace function ripples.att_e1_extract(p_ind text default '1023', p_lo int default 13, p_hi int default 24) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare reg jsonb := coalesce(ripples._att_cfg('engine63') -> 'regime_exclusions', '[]'::jsonb); v jsonb;
begin
  with ev as (
    select e.num, e.sf, e.m0, e.cty from (
      select d.num, left(min(d.county), 2) sf, date_trunc('month', min(d.began))::date m0, array_agg(distinct d.county) cty
        from ripples.att_b9_decl d
       where d.type = 'DR' and d.it in ('Flood', 'Dam/Levee Break', 'Mud/Landslide') and d.county !~ '000$'
       group by d.num having count(distinct left(d.county, 2)) = 1) e
     where e.m0 >= date '2001-03-01' and e.m0 < date '2024-04-01'
       and not exists (select 1 from jsonb_array_elements(reg) r
                        where (e.m0 - interval '12 months')::date <= (r ->> 'to')::date and (e.m0 + interval '24 months')::date >= (r ->> 'from')::date)),
  cty as (   -- donors only
    select e.num, e.m0, q.area, q.ym, ln(q.emp) y
      from ev e join ripples.att_b9_qcew q on q.ind = p_ind and left(q.area, 2) = e.sf and q.emp > 0
       and q.ym between (e.m0 - interval '12 months')::date and (e.m0 + make_interval(months => p_hi))::date
     where not (q.area = any(e.cty))
       and not exists (select 1 from ripples.att_b9_decl d2 where d2.county = q.area
                        and d2.began between (e.m0 - interval '12 months')::date and (e.m0 + interval '24 months')::date)),
  per as (
    select num, area,
           array_agg(y order by ym) filter (where ym < m0) pre,
           avg(y) filter (where ym between (m0 + make_interval(months => p_lo))::date and (m0 + make_interval(months => p_hi))::date) w,
           count(*) filter (where ym between (m0 + make_interval(months => p_lo))::date and (m0 + make_interval(months => p_hi))::date) nw
      from cty group by num, area)
  select jsonb_agg(jsonb_build_object('num', ev.num, 'n_t', cardinality(ev.cty), 'dose', cardinality(ev.cty),
           'donors', (select jsonb_agg(jsonb_build_object('a', p.area, 'pre', (select jsonb_agg(round(x::numeric, 5)) from unnest(p.pre) x), 'w', round(p.w::numeric, 5)))
                        from per p where p.num = ev.num and cardinality(p.pre) = 12 and p.nw = p_hi - p_lo + 1)))
    into v from ev;
  return jsonb_build_object('ind', p_ind, 'window', jsonb_build_array(p_lo, p_hi), 'events', v);
end $$;
revoke all on function ripples.att_e1_extract(text, int, int) from anon, authenticated, public;
