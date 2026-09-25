-- Knock-On v5 W4: Bluesky bot state + service-only RPCs (migration ripples_v5_w4_bot).
-- Objects: ripples.bot_posts, public.ripples_bot_context(), public.ripples_bot_log(int, text, text, text).
-- Both functions are service_role only (the ripples-bot edge function calls them with SUPABASE_SERVICE_ROLE_KEY).

create table if not exists ripples.bot_posts (
  n          int primary key,
  status     text not null check (status in ('claimed', 'posted', 'failed')),
  uri        text,
  err        text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table ripples.bot_posts enable row level security;
revoke all on table ripples.bot_posts from anon, authenticated, public;

-- Everything the bot needs in one call. Secrets are returned only when BOTH vault secrets exist.
-- target = the live, published puzzle dated the day before the current puzzle date (07:30 UTC rollover), and
-- only when ripples_og_data says it has passed; the bot never posts a puzzle that is still current.
-- social = the AI/template 'social' copy stored under TODAY's n (the Routine writes "about yesterday's reveal"
-- while captioning today's puzzle, SPEC §11); it is null when absent.
create or replace function public.ripples_bot_context() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  h text; pw text; cur date := ripples._current_date(); cur_n int := ripples._current_n();
  tn int; og jsonb; soc jsonb; posted text;
begin
  select decrypted_secret into h  from vault.decrypted_secrets where name = 'bsky_handle' limit 1;
  select decrypted_secret into pw from vault.decrypted_secrets where name = 'bsky_app_password' limit 1;
  select p.n into tn from ripples.puzzles p
   where p.kind = 'live' and p.status = 'published' and p.puzzle_date = cur - 1
   order by p.n desc limit 1;
  if tn is not null then
    og := public.ripples_og_data(tn);
    if og is null or coalesce((og ->> 'past')::boolean, false) is not true then tn := null; og := null; end if;
  end if;
  if tn is not null then
    select jsonb_build_object('text', c.text, 'source', c.source) into soc
      from ripples.copy c where c.n = cur_n and c.kind = 'social' and c.source in ('ai', 'template')
     order by (c.source = 'ai') desc, c.created_at desc limit 1;
    select b.status into posted from ripples.bot_posts b where b.n = tn;
  end if;
  return jsonb_build_object(
    'has_secrets', (coalesce(h, '') <> '' and coalesce(pw, '') <> ''),
    'handle', case when coalesce(h, '') <> '' and coalesce(pw, '') <> '' then h end,
    'app_password', case when coalesce(h, '') <> '' and coalesce(pw, '') <> '' then pw end,
    'current_date', cur, 'current_n', cur_n,
    'target_n', tn, 'og', og, 'social', soc, 'post_status', posted);
end $$;

-- claim (idempotent guard against double posts; a failed or stale claim can be re-claimed), posted, failed
create or replace function public.ripples_bot_log(p_n int, p_action text, p_uri text default null, p_err text default null)
returns boolean language plpgsql volatile security definer set search_path = '' as $$
begin
  if p_action = 'claim' then
    insert into ripples.bot_posts (n, status) values (p_n, 'claimed')
    on conflict (n) do update set status = 'claimed', err = null, updated_at = now()
      where ripples.bot_posts.status = 'failed'
         or (ripples.bot_posts.status = 'claimed' and ripples.bot_posts.updated_at < now() - interval '10 minutes');
    return found;
  elsif p_action = 'posted' then
    update ripples.bot_posts set status = 'posted', uri = left(p_uri, 300), err = null, updated_at = now() where n = p_n;
    return found;
  elsif p_action = 'failed' then
    update ripples.bot_posts set status = 'failed', err = left(p_err, 500), updated_at = now() where n = p_n;
    return found;
  end if;
  raise exception 'invalid';
end $$;

revoke execute on function public.ripples_bot_context() from public, anon, authenticated;
revoke execute on function public.ripples_bot_log(int, text, text, text) from public, anon, authenticated;
grant execute on function public.ripples_bot_context() to service_role;
grant execute on function public.ripples_bot_log(int, text, text, text) to service_role;

notify pgrst, 'reload schema';
