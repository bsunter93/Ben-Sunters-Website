-- Migration: attention_stack_core_definer_helpers (W7 att-core): the three immutable helpers are SECURITY DEFINER too
-- (rule: every att function is SECURITY DEFINER, search_path='', service_role only).
alter function ripples.att_norm_term(text) security definer;
alter function ripples.att_skip_title(text) security definer;
alter function ripples.att_is_stopword(text) security definer;
revoke all on function ripples.att_norm_term(text), ripples.att_skip_title(text), ripples.att_is_stopword(text) from public, anon, authenticated;
grant execute on function ripples.att_norm_term(text), ripples.att_skip_title(text), ripples.att_is_stopword(text) to service_role;
