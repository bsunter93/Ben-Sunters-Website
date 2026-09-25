-- att-news n9: the SQL second screen (ripples._att_news_stop, used by att_news_candidates_merge and
-- att_news_edges_accum) gets the same phrase-fragment, bare-title and anonymous-role patterns as the function's
-- JUNK_LABEL, so a label that slips past the function (or an older deploy) is still refused. Owner-editable config.
update ripples.att_config
   set value = (
     select jsonb_agg(distinct x) from (
       select jsonb_array_elements_text(value) x
       union all select unnest(array[
         '(^| )(has|have|had|is|are|was|were|would|could|should|ever|never|been|being|says|said|does|did|not)( |$)',
         '^(\S+ ){6,}\S+$',
         '^(the )?(prime minister|president|vice president|minister|first minister|foreign minister|justice minister|chancellor|governor|mayor|senator|premier|secretary|secretary of state|chief executive|spokesperson|spokesman|spokeswoman)$',
         '(^| )(resident|residents|spokesperson|spokesman|spokeswoman|official|officials|source|sources|victim|witness|neighbour|neighbor)$'
       ])) s)
 where key = 'news_entity_stop_regex';
