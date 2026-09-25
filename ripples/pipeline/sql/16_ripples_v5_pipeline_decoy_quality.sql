-- Knock-On v5 / W2: migration ripples_v5_pipeline_decoy_quality
-- Decoys must read as "views normal" (SPEC §2: "also linked; views normal, 0.9x"). The §5.2 calm test
-- (max |z| < 1 over [tp-7, as_of], window multiple < 1.25) is loose for pages whose baseline window holds an old
-- spike (a large MAD), which let pages in post-hype decay through (0.5x "normal"). So a decoy also needs a window
-- multiple >= config.pipeline.decoy_min_multiple (0.67), and among qualifying siblings the flattest recent series is
-- preferred (max / median of the last 30 days of the stored spark), then the closest median.
update ripples.config set value = value || '{"decoy_min_multiple":0.67}'::jsonb where key = 'pipeline';

create or replace function ripples._flat30(p_spark int[]) returns numeric
language sql immutable set search_path = '' as $$
  select case when p_spark is null or cardinality(p_spark) < 30 then null else
    (select max(v)::numeric / greatest(percentile_cont(0.5) within group (order by v), 1)::numeric
       from unnest(p_spark[cardinality(p_spark) - 29:cardinality(p_spark)]) v) end
$$;

create or replace function ripples._pick_decoys(p_as_of date, p_root text, p_parent text, p_answer text, p_exclude text[])
returns text[]
language sql stable security definer set search_path = '' as $$
  with ans as (
    select c.qid, round(c.median_views) med, a.category, a.title_en
      from ripples.candidates c join ripples.articles a on a.qid = c.qid
     where c.as_of = p_as_of and c.role = 'real' and c.root_qid = p_root and c.parent_qid = p_parent and c.qid = p_answer
  ), sib as (
    select c.qid, (a.category = ans.category) same_cat, coalesce(ripples._flat30(c.spark), 99) flat,
           abs(ln(greatest(round(c.median_views), 1) / greatest(ans.med, 1))) dist
      from ans
      join ripples.candidates c on c.as_of = p_as_of and c.role = 'real' and c.root_qid = p_root and c.parent_qid = p_parent
      join ripples.articles a on a.qid = c.qid
     where c.qid <> ans.qid and c.calm and c.linked and c.spark is not null
       and abs(coalesce(c.max_abs_z, 9)) < 1 and c.multiple < 1.25
       and c.multiple >= ripples._pcfg('decoy_min_multiple', 0.67)
       and not (c.qid = any(coalesce(p_exclude, '{}')))
       and round(c.median_views) >= 0.5 * ans.med and round(c.median_views) <= 2 * ans.med
       and ripples._stem_ok(a.title_en, ans.title_en)
       and ripples._safe(c.qid, p_as_of, c.median_views, false)
  ), ranked as (
    select qid, same_cat, row_number() over (order by same_cat desc, round(flat, 1), dist, qid) rn from sib
  )
  select case when (select count(*) from ranked where same_cat) >= 2 and (select count(*) from ranked) >= 3
              then array(select qid from ranked order by rn limit 3) end
$$;
