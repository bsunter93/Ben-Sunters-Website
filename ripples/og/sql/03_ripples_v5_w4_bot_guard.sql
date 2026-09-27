-- Knock-On v5 W4 fix (migration ripples_v5_w4_bot_guard): ripples_bot_context() no longer targets a puzzle that
-- ripples_latest() is still serving. Before, the target rolled over at 07:30 whether or not today's puzzle existed,
-- so on a delayed day the bot would have picked yesterday's puzzle (still playable, "Here's yesterday's").
-- Now the target also needs ripples._latest_live_n() > target n. Grants are unchanged (service_role only).
-- Supersedes the function body in 01_ripples_v5_w4_bot.sql.

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
    -- also require a NEWER live puzzle to be served: on a delayed day ripples_latest() keeps serving yesterday's
    -- puzzle as playable, so its answers must not be posted yet
    if og is null or coalesce((og ->> 'past')::boolean, false) is not true
       or coalesce(ripples._latest_live_n(), -2147483648) <= tn then tn := null; og := null; end if;
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

revoke execute on function public.ripples_bot_context() from public, anon, authenticated;
grant execute on function public.ripples_bot_context() to service_role;
