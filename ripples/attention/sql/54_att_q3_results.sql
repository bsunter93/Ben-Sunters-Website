-- 54: Q3 results store. Workflows write each finished screen report here (ripples/lab/q3_upload.py) because the job
-- log API returns only the last 5,000 lines and the artifact host is unreachable from the authoring environment.
-- Aggregate statistics only (no identities). Service role only.
create table if not exists ripples.att_q3_results (
  id bigserial primary key,
  name text not null,
  run_url text,
  report jsonb not null,
  created_at timestamptz not null default now()
);
alter table ripples.att_q3_results enable row level security;
revoke all on ripples.att_q3_results from anon, authenticated;
create or replace function public.att_q3_result_put(p_name text, p_run text, p_report jsonb) returns bigint
language sql volatile security definer set search_path = '' as $$
  insert into ripples.att_q3_results(name, run_url, report) values (p_name, p_run, p_report) returning id;
$$;
revoke all on function public.att_q3_result_put(text, text, jsonb) from anon, authenticated, public;
grant execute on function public.att_q3_result_put(text, text, jsonb) to service_role;
