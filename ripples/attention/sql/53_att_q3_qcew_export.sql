-- 53: Q3 county jobs lens export (ripples/lab/more_panels.py county; ripples/docs/q3_protocol_county.md). Read-only,
-- service_role only. QCEW monthly employment by county area for one industry code (10 = all industries,
-- 1023 = financial activities), 2012-01..2026-08, in the sparse format of att_q3_export.
create or replace function public.att_q3_qcew_export(p_ind text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_object_agg(name, obj), '{}'::jsonb) from (
    select 'qcew|' || ind || '|' || area || '|' as name,
           jsonb_build_object('d', jsonb_agg(ym - date '2012-01-01' order by ym), 'v', jsonb_agg(emp order by ym)) as obj
      from ripples.att_b9_qcew
     where ind = p_ind and ym between date '2012-01-01' and date '2026-08-31' and emp is not null
     group by ind, area) t;
$$;
revoke all on function public.att_q3_qcew_export(text) from anon, authenticated, public;
grant execute on function public.att_q3_qcew_export(text) to service_role;
