-- 15e_att_ident_npm_scoped (W7 att-charts, 2026-09-25, applied as migration att_ident_npm_scoped)
-- The identifier screen treats any key that starts with '@' as a social handle, so att_ingest rejected every scoped npm
-- package (e.g. '@anthropic-ai/sdk', '@modelcontextprotocol/sdk') with 'identifier_like_key'. A scoped npm package name
-- is a package identifier (registry namespace + package), not a person's handle. Narrow exemption: source 'npm.dl' and
-- the exact npm scoped-name grammar '@scope/name'. Everything else is unchanged (bsky/masto/any other '@x' stays out).
create or replace function ripples._att_ident_like(p text, p_source text, p_strict boolean default false)
returns boolean
language sql immutable security definer set search_path = '' as $$
  select p is not null and (
       p ~* '(https?://|\mdid:(plc|web):|\mwww\.[a-z0-9-]+\.)'
    or p ~* '[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)+'
    or p ~* '\.bsky\.(social|app)$'
    or (p ~ '^@[[:alnum:]_]' and coalesce(p_source, '') !~ '^wiki\.'
        and not (coalesce(p_source, '') = 'npm.dl' and p ~ '^@[a-z0-9][a-z0-9._-]*/[a-z0-9][a-z0-9._-]*$'))
    or (p_strict and coalesce(p_source, '') ~ '^(bsky|masto)\.'
        and p !~ '\s' and (p ~* '^[a-z0-9-]+(\.[a-z0-9-]+){2,}$'
             or p ~* '^[a-z0-9-]+\.(com|net|org|io|dev|me|xyz|social|app|co|ai|blog|online|site|page|lol|art|us|uk|ca|de|fr|jp|eu|info|tv|fm|pub|world|zone|cafe|club|space|tech)$')))
$$;
revoke all on function ripples._att_ident_like(text, text, boolean) from public, anon, authenticated;
grant execute on function ripples._att_ident_like(text, text, boolean) to service_role;
