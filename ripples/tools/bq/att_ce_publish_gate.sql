-- Wire the BigQuery forecast check into what the site publishes (applied 2026-09-26 as migrations
-- rm_cascade_content_ce_gate + ce_gate_test_override). OWNER_DECISIONS D-12: Measured requires agreement.
--
-- 1. ripples.rm_cascade_content(bigint,date): each node's public tier is
--      case when engine tier = 'measured' then att_ce_gate(hop,'measured')->>'tier' else engine tier end
--    and a demoted node's tier_reason is the gate's reason ("forecast check pending" / "... disagrees" /
--    "... cannot assess this series"). ripples.att_publish_cascade records published_tier from this payload,
--    so the registry and every served version carry the gated tier.
-- 2. ripples.att_ce_gate reads an optional transaction-local override:
--      current_setting('ripples.ce_gate_mode', true) -> 'enforce' | 'shadow' | 'off'
--    ripples.rm_contract_test() sets it to 'shadow' (set_config(..., true)) because its synthetic hops test the
--    Measured wording; the gate itself is covered by the att_ce tests. Production reads att_config.ce.gate_mode.
--
-- Applied as in-place replacements of the live definitions (anchor-checked), equivalent to:
do $do$
declare d text;
  old text := $q$'tier', n ->> 'tier', 'tier_reason', ripples.rm_reason(n ->> 'tier_reason'),$q$;
  new text := $q$'tier', case when n ->> 'tier' = 'measured' then ripples.att_ce_gate((n ->> 'hop_id')::bigint, 'measured') ->> 'tier' else n ->> 'tier' end,
      'tier_reason', case when n ->> 'tier' = 'measured' and ripples.att_ce_gate((n ->> 'hop_id')::bigint, 'measured') ->> 'tier' <> 'measured'
                          then ripples.att_ce_gate((n ->> 'hop_id')::bigint, 'measured') ->> 'reason'
                          else ripples.rm_reason(n ->> 'tier_reason') end,$q$;
begin
  d := pg_get_functiondef('ripples.rm_cascade_content(bigint,date)'::regprocedure);
  if position(old in d) > 0 then execute replace(d, old, new); end if;
  d := pg_get_functiondef('ripples.att_ce_gate(bigint,text)'::regprocedure);
  if position('ripples.ce_gate_mode' in d) = 0 then
    execute replace(d, $q$v_mode text := coalesce(ripples._att_cfg('ce')->>'gate_mode', 'enforce');$q$,
      $q$v_mode text := coalesce(nullif(current_setting('ripples.ce_gate_mode', true), ''), ripples._att_cfg('ce')->>'gate_mode', 'enforce');$q$);
  end if;
  d := pg_get_functiondef('ripples.rm_contract_test()'::regprocedure);
  if position('ripples.ce_gate_mode' in d) = 0 then
    execute regexp_replace(d, '\mbegin\M', $q$begin
  perform set_config('ripples.ce_gate_mode', 'shadow', true);$q$);
  end if;
end $do$;
