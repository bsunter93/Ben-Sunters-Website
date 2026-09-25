-- Knock-On v5 / W2: migration ripples_v5_pipeline_date_seeds (in-place patch of ripples._refresh_articles)
-- Calendar-day articles ("September 23") spike on their own date every year; the expand job already drops them from
-- candidate sets (kn.ts LIST_TITLE, SPEC 5.2 "date and year articles"), and now articles.is_list marks them too, so
-- ripples._safe keeps them out of seeds, options, Call It and the Board.
do $$
declare d text; d2 text;
begin
  select pg_get_functiondef('ripples._refresh_articles(text[])'::regprocedure) into d;
  d2 := regexp_replace(d, $p$or\s+r\.title_en\s+~\s+'\^\[0-9\]\{4\}s\?\s+in\s+',$p$,
    $r$or r.title_en ~ '^[0-9]{4}s? in '
                    or r.title_en ~ '^(January|February|March|April|May|June|July|August|September|October|November|December) [0-9]{1,2}$',$r$);
  if d2 = d then raise exception 'migration 19: pattern not found in ripples._refresh_articles'; end if;
  execute d2;
end $$;
update ripples.articles set is_list = true
 where not is_list and title_en ~ '^(January|February|March|April|May|June|July|August|September|October|November|December) [0-9]{1,2}$';
