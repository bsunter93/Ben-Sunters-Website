-- 45: b9 QCEW backfill for 2001-2013 (ledger 1274 disclosure). The QCEW open-data API only serves 2014 onward, so the
-- earlier years come from the BLS bulk annual "by industry" files, fetched on a GitHub runner
-- (ripples/tools/gov/qcew_backfill.py, .github/workflows/ripples-qcew-backfill.yml) and written here in small batches.
-- Same filters as the in-database parser (att_b9_tick): private ownership (own 5), county level (agglvl 73 for 1023,
-- 71 for 10), no suppressed cells, numeric monthly employment. Existing rows are never overwritten.
create or replace function public.att_b9_qcew_load(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) > 5000 then
    raise exception 'p_rows must be an array of at most 5000 rows';
  end if;
  insert into ripples.att_b9_qcew(area, ind, ym, emp)
    select r ->> 'a', r ->> 'i', (r ->> 'm')::date, (r ->> 'e')::int
      from jsonb_array_elements(p_rows) r
     where r ->> 'a' ~ '^[0-9]{5}$' and r ->> 'a' !~ '000$' and r ->> 'i' in ('10', '1023')
       and r ->> 'm' ~ '^(2001|200[2-9]|201[0-3])-[0-9]{2}-01$' and r ->> 'e' ~ '^[0-9]+$'
  on conflict do nothing;
  get diagnostics n = row_count;
  return jsonb_build_object('rows', n, 'sent', jsonb_array_length(p_rows));
end $$;
revoke all on function public.att_b9_qcew_load(jsonb) from anon, authenticated, public;
grant execute on function public.att_b9_qcew_load(jsonb) to service_role;
