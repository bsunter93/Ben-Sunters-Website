-- Migration `att_market_jobs` (W7 att-market builder, 2026-09-25).
-- Per-job payload keys for merged backfill dispatches, so att-market can mark finished keys' jobs done and requeue the
-- rest after a short delay (att_jobs_done 'requeue' without p_not_before waits 1 h). service_role only.
create or replace function ripples.att_market_jobs(p_ids bigint[])
returns table(id bigint, keys text[])
language sql stable security definer set search_path = '' as $$
  select j.id, array(select e->>'key' from jsonb_array_elements(coalesce(j.payload->'keys', '[]'::jsonb)) e)
  from ripples.att_jobs j where j.id = any(p_ids) and j.fn = 'att-market'
$$;
create or replace function public.att_market_jobs(p_ids bigint[])
returns table(id bigint, keys text[])
language sql security definer set search_path = '' as
$$ select * from ripples.att_market_jobs(p_ids) $$;
do $$ declare f text; begin
  foreach f in array array['ripples.att_market_jobs(bigint[])', 'public.att_market_jobs(bigint[])'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
