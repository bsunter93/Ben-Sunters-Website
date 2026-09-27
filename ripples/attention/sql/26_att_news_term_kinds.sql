-- att-news n8: registry kind for each news term, returned inside match as match.kind
-- (place | person | work | other | unknown). The GKG name matcher uses it:
--   * a one-word pattern of a person, work or organisation must be a whole GKG name ("julia", "cnn")
--   * places never count through V1Persons names; persons/works/others never through V1Locations names
-- Signature and grants are unchanged (create or replace keeps the ACL: service_role only).
create or replace function ripples.att_news_terms(p_source text, p_limit integer default 5000)
 returns table(key text, match jsonb, topic_id bigint, active boolean, key_type text)
 language sql stable security definer
 set search_path to ''
as $function$
  select w.key, w.match || jsonb_build_object('kind', w.kind), w.topic_id, w.act, w.key_type from (
    select distinct on (k.key) k.key, k.match, k.topic_id, (t.status = 'active') act, k.key_type, t.last_active,
      case
        when t.category = 'places'
          or coalesce(t.meta->'p31', '[]'::jsonb) ?| array['Q6256','Q3624078','Q515','Q1549591','Q5119','Q35657',
               'Q486972','Q23442','Q82794','Q107390','Q10864048','Q5852411','Q34876','Q15284','Q8502','Q4022','Q165',
               'Q46831','Q1637706','Q200250','Q7930989','Q3957','Q532','Q12813115','Q3336843','Q1620908','Q5107',
               'Q9430','Q23397','Q1093829','Q13218630','Q47168','Q2074737']
          then 'place'
        when coalesce(t.meta->'p31', '[]'::jsonb) ? 'Q5' or t.category like 'people%' then 'person'
        when t.category in ('film_tv', 'music', 'books_media', 'games') then 'work'
        when t.category is null and t.meta->'p31' is null then 'unknown'
        else 'other'
      end as kind
    from ripples.att_keys k join ripples.att_topics t on t.topic_id = k.topic_id
    where k.source = p_source and k.enabled and k.metric = 'n' and k.geo = 'ALL'
      and (t.status = 'active' or t.in_panel)
    order by k.key, (t.status = 'active') desc, k.topic_id) w
  order by w.act desc, w.last_active desc nulls last, w.topic_id
  limit greatest(p_limit, 0)
$function$;
revoke all on function ripples.att_news_terms(text, integer) from public, anon, authenticated;
