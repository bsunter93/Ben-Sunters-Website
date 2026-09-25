-- Migration: attention_stack_core_ops  (W7 att-core, 2026-09-25)
-- Source lookup + title filter RPCs for edge functions, and the att-core cron jobs (§3.4).
create or replace function ripples.att_source_get(p_source text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select to_jsonb(s) from ripples.att_sources s where s.source = p_source
$$;

create or replace function ripples.att_filter_titles(p_titles text[]) returns text[]
language sql immutable security definer set search_path = '' as $$
  select coalesce(array_agg(t), '{}') from unnest(p_titles) t where not ripples.att_skip_title(t)
$$;

create or replace function public.att_source_get(p_source text) returns jsonb
language sql security definer set search_path = '' as $$ select ripples.att_source_get(p_source) $$;
create or replace function public.att_filter_titles(p_titles text[]) returns text[]
language sql security definer set search_path = '' as $$ select ripples.att_filter_titles(p_titles) $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where (n.nspname = 'ripples' and (p.proname like 'att\_%' or p.proname like '\_att\_%'))
              or (n.nspname = 'public' and p.proname like 'att\_%')
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    execute format('grant execute on function %s to service_role', f.sig);
  end loop;
end $$;

-- cron (UTC). Hop-window tick and off-peak backfill/resolve drain; registry upkeep after the morning build.
select cron.schedule('att-tick-hops-a', '33-59 7 * * *', $$select ripples.att_tick('hops')$$);
select cron.schedule('att-tick-hops-b', '0-18 8 * * *',  $$select ripples.att_tick('hops')$$);
select cron.schedule('att-backfill',    '*/2 10-23 * * *', $$select ripples.att_tick('backfill')$$);
select cron.schedule('att-registry',    '52 9 * * *',
  $$select ripples.att_registry_maintain(); select public.call_collector('att-registry', '{"mode":"bootstrap"}'::jsonb)$$);
notify pgrst, 'reload schema';
