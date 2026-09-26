-- =====================================================================================================================
-- 06_rm_public_rpcs.sql — WS-C (Ripple Map v6): public contracts, version freezing, publish bundle, count-only events
--
-- Supabase project kffkasnzqcddpystszch, schema `ripples` (service-only objects) + `public` (the rm_* RPCs).
-- Applied as migration `wsc_rm_public_rpcs` (+ addenda listed at the end of this file). Fixes after the 2026-09-26 verification:
-- `wsc_fix_public_names_a`..`_e`, `wsc_fix_contract_test`, `wsc_fix_contract_test_b`, `wsc_fix_lands_unit` (public names / withheld
-- versions, closed-window wording, rate units, frozen-file retry and withdrawal, per-run caps, coverage + synthetic contract test).
--
-- Contract: ENGINE_SPEC §11 (shapes), EXPERIENCE_SPEC §1/§3/§7 (routes, 8 domains, share text), OWNER_DECISIONS D-6/D-10.
-- Fixtures (shape reference, synthetic numbers): ripples/contract/fixtures/v2/*.json. `ripples.rm_contract_test()` diffs every
-- RPC's live output against them key by key (fixtures loaded into ripples.rm_contract_fixtures).
--
-- Rules carried by every object here:
--   * Public RPCs: SECURITY DEFINER, STABLE, search_path = '', revoke-then-grant, inputs are IDs only (bigint/int/date/'YYYY-WW'
--     /a domain code from a fixed list). No free text reaches a query.
--   * Decoy events (role 'decoy') are never addressable: rm_cascade/rm_hop/rm_og return null for them and for their hops; they
--     appear only as the aggregated `control` object of a real line / day. Negative-control hops are never addressable either.
--   * A line is public only once it has a frozen version in att_cascade_versions. Frozen versions are immutable (a trigger
--     refuses UPDATE/DELETE); a new version is frozen only when the line's substance hash changes (sparklines excluded, so a
--     new day of data alone never mints a version).
--   * `reconstructed` is passed through on every event object, archive row, lands row and week line.
--   * MONEY (tickers) is disabled in v6.0: nodes whose source's engine channel is MONEY are dropped from every public payload.
--   * Words: "consistent with", never causal; the two fluke labels exactly as ENGINE §8. Numbers come from the engine tables.
--   * Public names: a stop is shown only under a human name. A node whose label is still a raw QID is held back (counted in
--     `held_back`) until a name exists; a Likely-or-better stop without a name holds the whole line's next version instead.
--   * ORDER: apply this file AFTER 04/05_ripples_v5_w1_fixes*.sql. Those older files grant ripples_submit_play/call to anon;
--     re-applying them re-opens the v5 writes. rm_enforce_grants() (run by every publish) revokes whatever rm_grant_audit() lists.
-- =====================================================================================================================

-- ---------------------------------------------------------------------------------------------------------------------
-- 0. Tables (RLS on, no policies: service-only)
-- ---------------------------------------------------------------------------------------------------------------------
create table if not exists ripples.rm_publish_set (          -- non-live lines that are public (reconstructed archive, controls)
  event_id  bigint primary key references ripples.att_events,
  added_at  timestamptz not null default now(),
  note      text
);
create table if not exists ripples.rm_days (                 -- ShockList per day, as published
  day          date primary key,
  payload      jsonb not null,
  payload_hash text not null,
  published_at timestamptz not null default now(),
  ledger_seq   bigint
);
create table if not exists ripples.rm_publish_log (          -- one row per publish run (rm_health.stage)
  id      bigserial primary key,
  at      timestamptz not null default now(),
  as_of   date not null,
  stage   text not null,
  result  jsonb not null default '{}'::jsonb
);
create table if not exists ripples.rm_event_counts (         -- count-only share/landing events: no client, no IP, no page
  day   date not null,
  kind  text not null check (kind in ('share_tap','landing')),
  src   text not null check (src ~ '^[a-z0-9_-]{1,24}$'),
  n     int not null default 0,
  uniq  int not null default 0,
  primary key (day, kind, src)
);
create table if not exists ripples.rm_event_seen (           -- same-day de-duplication only; purged after 2 days
  day          date not null,
  kind         text not null,
  client_hash  text not null,                                -- sha256(daily salt | client id); the salt is deleted with the day
  primary key (day, kind, client_hash)
);
create table if not exists ripples.rm_contract_fixtures (    -- ripples/contract/fixtures/v2/*.json, loaded for rm_contract_test
  name    text primary key,
  payload jsonb not null
);
-- Public-text audit of every frozen version (versions are immutable, so each is checked once). A version whose public text
-- still carries a raw identifier (a Wikidata QID as a label, "… → Q76") is WITHHELD: the row stays frozen in
-- att_cascade_versions (and in the ledger), but no public RPC, Storage file, feed, card or stub serves it. Migration
-- wsc_fix_public_names (2026-09-26, after the independent verification).
create table if not exists ripples.rm_version_audit (
  event_id    bigint not null,
  version     int not null,
  leaks       int not null,
  sample      text[],
  withheld    boolean not null,
  reason      text,
  checked_at  timestamptz not null default now(),
  ledger_seq  bigint,
  primary key (event_id, version)
);
create table if not exists ripples.rm_publish_checked (       -- daily publish rotation (a per-run cap; oldest-checked first)
  event_id    bigint primary key,
  checked_at  timestamptz not null default now()
);
create table if not exists ripples.rm_hop_mirrored (          -- HopEvidence mirror rotation (a per-run cap; oldest first)
  hop_id      bigint primary key,
  mirrored_at timestamptz not null default now()
);
-- Public names for source-local nodes ('source:key'). WS-B's att_node_label returns the bare key for these ('DGS10', 'CISO',
-- 'e:1061358', '__total__'), which is an identifier, not a name. A source-local node is shown only under a name from this table
-- (or a WS-B label that is not its own key); otherwise it is held back like an unnamed QID. Each row names what the source's
-- own documentation says the key is (`basis`). Keys we cannot name with certainty (Polymarket event/market ids, whose titles we
-- do not store; USAspending queries; unlisted EIA-930 codes) are deliberately absent. Migration wsc_fix_source_key_names (2026-09-26).
create table if not exists ripples.rm_node_names (
  node        text primary key,
  label       text not null check (label !~ '^Q[0-9]+$' and label <> ''),
  basis       text not null
);
alter table ripples.rm_publish_set        enable row level security;
alter table ripples.rm_days               enable row level security;
alter table ripples.rm_publish_log        enable row level security;
alter table ripples.rm_event_counts       enable row level security;
alter table ripples.rm_event_seen         enable row level security;
alter table ripples.rm_contract_fixtures  enable row level security;
alter table ripples.rm_version_audit      enable row level security;
alter table ripples.rm_publish_checked    enable row level security;
alter table ripples.rm_hop_mirrored       enable row level security;
alter table ripples.rm_node_names         enable row level security;
revoke all on ripples.rm_publish_set, ripples.rm_days, ripples.rm_publish_log, ripples.rm_event_counts, ripples.rm_event_seen,
              ripples.rm_contract_fixtures, ripples.rm_version_audit, ripples.rm_publish_checked, ripples.rm_hop_mirrored,
              ripples.rm_node_names
  from public, anon, authenticated;
insert into ripples.rm_node_names(node, label, basis) values
  ('fred:DCOILBRENTEU', 'Brent crude oil price', 'FRED series DCOILBRENTEU'),
  ('fred:DCOILWTICO', 'WTI crude oil price', 'FRED series DCOILWTICO'),
  ('fred:DEXCAUS', 'Canadian dollars per US dollar', 'FRED series DEXCAUS'),
  ('fred:DEXCHUS', 'Chinese yuan per US dollar', 'FRED series DEXCHUS'),
  ('fred:DEXJPUS', 'Japanese yen per US dollar', 'FRED series DEXJPUS'),
  ('fred:DEXMXUS', 'Mexican pesos per US dollar', 'FRED series DEXMXUS'),
  ('fred:DEXUSEU', 'US dollars per euro', 'FRED series DEXUSEU'),
  ('fred:DEXUSUK', 'US dollars per British pound', 'FRED series DEXUSUK'),
  ('fred:DFF', 'Effective federal funds rate', 'FRED series DFF'),
  ('fred:DGS10', '10-year Treasury yield', 'FRED series DGS10'),
  ('fred:DGS2', '2-year Treasury yield', 'FRED series DGS2'),
  ('fred:DGS30', '30-year Treasury yield', 'FRED series DGS30'),
  ('fred:DGS3MO', '3-month Treasury bill yield', 'FRED series DGS3MO'),
  ('fred:DGS5', '5-year Treasury yield', 'FRED series DGS5'),
  ('fred:DHHNGSP', 'Henry Hub natural gas price', 'FRED series DHHNGSP'),
  ('fred:DJFUELUSGULF', 'US Gulf Coast jet fuel price', 'FRED series DJFUELUSGULF'),
  ('fred:DTWEXBGS', 'Broad US dollar index', 'FRED series DTWEXBGS'),
  ('fred:SOFR', 'Secured overnight financing rate (SOFR)', 'FRED series SOFR'),
  ('fred:T10Y2Y', '10-year minus 2-year Treasury spread', 'FRED series T10Y2Y'),
  ('fred:T10YIE', '10-year breakeven inflation', 'FRED series T10YIE'),
  ('fred:T5YIE', '5-year breakeven inflation', 'FRED series T5YIE'),
  ('fred.weekly:GASREGW', 'US regular gasoline price (weekly)', 'FRED series GASREGW'),
  ('fred.weekly:GASDESW', 'US diesel price (weekly)', 'FRED series GASDESW'),
  ('fred.claims:ICSA', 'US initial jobless claims', 'FRED series ICSA'),
  ('fred.claims:ICNSA', 'US initial jobless claims (not seasonally adjusted)', 'FRED series ICNSA'),
  ('fred.claims:CCSA', 'US continuing jobless claims', 'FRED series CCSA'),
  ('fred.claims:AKICLAIMS', 'Alaska initial jobless claims', 'FRED series AKICLAIMS'),
  ('fred.claims:ALICLAIMS', 'Alabama initial jobless claims', 'FRED series ALICLAIMS'),
  ('fred.claims:ARICLAIMS', 'Arkansas initial jobless claims', 'FRED series ARICLAIMS'),
  ('fred.claims:AZICLAIMS', 'Arizona initial jobless claims', 'FRED series AZICLAIMS'),
  ('fred.claims:CAICLAIMS', 'California initial jobless claims', 'FRED series CAICLAIMS'),
  ('fred.claims:COICLAIMS', 'Colorado initial jobless claims', 'FRED series COICLAIMS'),
  ('fred.claims:CTICLAIMS', 'Connecticut initial jobless claims', 'FRED series CTICLAIMS'),
  ('fred.claims:DCICLAIMS', 'Washington, DC initial jobless claims', 'FRED series DCICLAIMS'),
  ('fred.claims:DEICLAIMS', 'Delaware initial jobless claims', 'FRED series DEICLAIMS'),
  ('fred.claims:FLICLAIMS', 'Florida initial jobless claims', 'FRED series FLICLAIMS'),
  ('fred.claims:GAICLAIMS', 'Georgia initial jobless claims', 'FRED series GAICLAIMS'),
  ('fred.claims:HIICLAIMS', 'Hawaii initial jobless claims', 'FRED series HIICLAIMS'),
  ('fred.claims:IAICLAIMS', 'Iowa initial jobless claims', 'FRED series IAICLAIMS'),
  ('fred.claims:IDICLAIMS', 'Idaho initial jobless claims', 'FRED series IDICLAIMS'),
  ('fred.claims:ILICLAIMS', 'Illinois initial jobless claims', 'FRED series ILICLAIMS'),
  ('fred.claims:INICLAIMS', 'Indiana initial jobless claims', 'FRED series INICLAIMS'),
  ('fred.claims:KSICLAIMS', 'Kansas initial jobless claims', 'FRED series KSICLAIMS'),
  ('fred.claims:KYICLAIMS', 'Kentucky initial jobless claims', 'FRED series KYICLAIMS'),
  ('fred.claims:LAICLAIMS', 'Louisiana initial jobless claims', 'FRED series LAICLAIMS'),
  ('fred.claims:MAICLAIMS', 'Massachusetts initial jobless claims', 'FRED series MAICLAIMS'),
  ('fred.claims:MDICLAIMS', 'Maryland initial jobless claims', 'FRED series MDICLAIMS'),
  ('fred.claims:MEICLAIMS', 'Maine initial jobless claims', 'FRED series MEICLAIMS'),
  ('fred.claims:MIICLAIMS', 'Michigan initial jobless claims', 'FRED series MIICLAIMS'),
  ('fred.claims:MNICLAIMS', 'Minnesota initial jobless claims', 'FRED series MNICLAIMS'),
  ('fred.claims:MOICLAIMS', 'Missouri initial jobless claims', 'FRED series MOICLAIMS'),
  ('fred.claims:MSICLAIMS', 'Mississippi initial jobless claims', 'FRED series MSICLAIMS'),
  ('fred.claims:MTICLAIMS', 'Montana initial jobless claims', 'FRED series MTICLAIMS'),
  ('fred.claims:NCICLAIMS', 'North Carolina initial jobless claims', 'FRED series NCICLAIMS'),
  ('fred.claims:NDICLAIMS', 'North Dakota initial jobless claims', 'FRED series NDICLAIMS'),
  ('fred.claims:NEICLAIMS', 'Nebraska initial jobless claims', 'FRED series NEICLAIMS'),
  ('fred.claims:NHICLAIMS', 'New Hampshire initial jobless claims', 'FRED series NHICLAIMS'),
  ('fred.claims:NJICLAIMS', 'New Jersey initial jobless claims', 'FRED series NJICLAIMS'),
  ('fred.claims:NMICLAIMS', 'New Mexico initial jobless claims', 'FRED series NMICLAIMS'),
  ('fred.claims:NVICLAIMS', 'Nevada initial jobless claims', 'FRED series NVICLAIMS'),
  ('fred.claims:NYICLAIMS', 'New York initial jobless claims', 'FRED series NYICLAIMS'),
  ('fred.claims:OHICLAIMS', 'Ohio initial jobless claims', 'FRED series OHICLAIMS'),
  ('fred.claims:OKICLAIMS', 'Oklahoma initial jobless claims', 'FRED series OKICLAIMS'),
  ('fred.claims:ORICLAIMS', 'Oregon initial jobless claims', 'FRED series ORICLAIMS'),
  ('fred.claims:PAICLAIMS', 'Pennsylvania initial jobless claims', 'FRED series PAICLAIMS'),
  ('fred.claims:PRICLAIMS', 'Puerto Rico initial jobless claims', 'FRED series PRICLAIMS'),
  ('fred.claims:RIICLAIMS', 'Rhode Island initial jobless claims', 'FRED series RIICLAIMS'),
  ('fred.claims:SCICLAIMS', 'South Carolina initial jobless claims', 'FRED series SCICLAIMS'),
  ('fred.claims:SDICLAIMS', 'South Dakota initial jobless claims', 'FRED series SDICLAIMS'),
  ('fred.claims:TNICLAIMS', 'Tennessee initial jobless claims', 'FRED series TNICLAIMS'),
  ('fred.claims:TXICLAIMS', 'Texas initial jobless claims', 'FRED series TXICLAIMS'),
  ('fred.claims:UTICLAIMS', 'Utah initial jobless claims', 'FRED series UTICLAIMS'),
  ('fred.claims:VAICLAIMS', 'Virginia initial jobless claims', 'FRED series VAICLAIMS'),
  ('fred.claims:VTICLAIMS', 'Vermont initial jobless claims', 'FRED series VTICLAIMS'),
  ('fred.claims:WAICLAIMS', 'Washington state initial jobless claims', 'FRED series WAICLAIMS'),
  ('fred.claims:WIICLAIMS', 'Wisconsin initial jobless claims', 'FRED series WIICLAIMS'),
  ('fred.claims:WVICLAIMS', 'West Virginia initial jobless claims', 'FRED series WVICLAIMS'),
  ('fred.claims:WYICLAIMS', 'Wyoming initial jobless claims', 'FRED series WYICLAIMS'),
  ('fred.claims:GUICLAIMS', 'Guam initial jobless claims', 'FRED series GUICLAIMS'),
  ('fred.claims:VIICLAIMS', 'US Virgin Islands initial jobless claims', 'FRED series VIICLAIMS'),
  ('fred.claims:ASICLAIMS', 'American Samoa initial jobless claims', 'FRED series ASICLAIMS'),
  ('fred.claims:MPICLAIMS', 'Northern Mariana Islands initial jobless claims', 'FRED series MPICLAIMS'),
  ('bls.cpi_items:CUSR0000SAF11', 'US consumer prices: food at home', 'BLS CPI item CUSR0000SAF11'),
  ('bls.cpi_items:CUSR0000SAF111', 'US consumer prices: cereals and bakery products', 'BLS CPI item CUSR0000SAF111'),
  ('bls.cpi_items:CUSR0000SAF112', 'US consumer prices: meats, poultry, fish and eggs', 'BLS CPI item CUSR0000SAF112'),
  ('bls.cpi_items:CUSR0000SAF113', 'US consumer prices: fruits and vegetables', 'BLS CPI item CUSR0000SAF113'),
  ('bls.cpi_items:CUSR0000SAF116', 'US consumer prices: alcoholic beverages', 'BLS CPI item CUSR0000SAF116'),
  ('bls.cpi_items:CUSR0000SAG1', 'US consumer prices: other goods', 'BLS CPI item CUSR0000SAG1'),
  ('bls.cpi_items:CUSR0000SAH1', 'US consumer prices: shelter', 'BLS CPI item CUSR0000SAH1'),
  ('bls.cpi_items:CUSR0000SAH3', 'US consumer prices: household furnishings and operations', 'BLS CPI item CUSR0000SAH3'),
  ('bls.cpi_items:CUSR0000SEEE01', 'US consumer prices: computers and peripherals', 'BLS CPI item CUSR0000SEEE01'),
  ('bls.cpi_items:CUSR0000SEFJ', 'US consumer prices: dairy products', 'BLS CPI item CUSR0000SEFJ'),
  ('bls.cpi_items:CUSR0000SEFP01', 'US consumer prices: coffee', 'BLS CPI item CUSR0000SEFP01'),
  ('bls.cpi_items:CUSR0000SEFR', 'US consumer prices: sugar and sweets', 'BLS CPI item CUSR0000SEFR'),
  ('bls.cpi_items:CUSR0000SEFV', 'US consumer prices: food away from home', 'BLS CPI item CUSR0000SEFV'),
  ('bls.cpi_items:CUSR0000SEGA', 'US consumer prices: tobacco products', 'BLS CPI item CUSR0000SEGA'),
  ('bls.cpi_items:CUSR0000SEHA', 'US consumer prices: rent', 'BLS CPI item CUSR0000SEHA'),
  ('bls.cpi_items:CUSR0000SEHB', 'US consumer prices: hotels and lodging away from home', 'BLS CPI item CUSR0000SEHB'),
  ('bls.cpi_items:CUSR0000SEHC', 'US consumer prices: owners'' equivalent rent', 'BLS CPI item CUSR0000SEHC'),
  ('bls.cpi_items:CUSR0000SEHE', 'US consumer prices: fuel oil and other fuels', 'BLS CPI item CUSR0000SEHE'),
  ('bls.cpi_items:CUSR0000SEHF', 'US consumer prices: energy services', 'BLS CPI item CUSR0000SEHF'),
  ('bls.cpi_items:CUSR0000SEHF01', 'US consumer prices: electricity', 'BLS CPI item CUSR0000SEHF01'),
  ('bls.cpi_items:CUSR0000SEHF02', 'US consumer prices: piped gas service', 'BLS CPI item CUSR0000SEHF02'),
  ('bls.cpi_items:CUSR0000SEHG', 'US consumer prices: water, sewer and trash service', 'BLS CPI item CUSR0000SEHG'),
  ('bls.cpi_items:CUSR0000SEMD', 'US consumer prices: hospital services', 'BLS CPI item CUSR0000SEMD'),
  ('bls.cpi_items:CUSR0000SETA01', 'US consumer prices: new vehicles', 'BLS CPI item CUSR0000SETA01'),
  ('bls.cpi_items:CUSR0000SETA02', 'US consumer prices: used cars and trucks', 'BLS CPI item CUSR0000SETA02'),
  ('bls.cpi_items:CUSR0000SETB01', 'US consumer prices: gasoline', 'BLS CPI item CUSR0000SETB01'),
  ('bls.cpi_items:CUSR0000SETC', 'US consumer prices: motor vehicle parts', 'BLS CPI item CUSR0000SETC'),
  ('bls.cpi_items:CUSR0000SETD', 'US consumer prices: vehicle maintenance and repair', 'BLS CPI item CUSR0000SETD'),
  ('bls.cpi_items:CUSR0000SETG01', 'US consumer prices: airline fares', 'BLS CPI item CUSR0000SETG01'),
  ('eia.930:AECI', 'Associated Electric Cooperative power grid', 'EIA-930 balancing authority AECI'),
  ('eia.930:AVA', 'Avista power grid', 'EIA-930 balancing authority AVA'),
  ('eia.930:AZPS', 'Arizona Public Service power grid', 'EIA-930 balancing authority AZPS'),
  ('eia.930:BANC', 'Northern California (BANC) power grid', 'EIA-930 balancing authority BANC'),
  ('eia.930:BPAT', 'Bonneville Power Administration power grid', 'EIA-930 balancing authority BPAT'),
  ('eia.930:CHPD', 'Chelan County PUD power grid', 'EIA-930 balancing authority CHPD'),
  ('eia.930:CISO', 'California ISO power grid', 'EIA-930 balancing authority CISO'),
  ('eia.930:CPLE', 'Duke Energy Progress East power grid', 'EIA-930 balancing authority CPLE'),
  ('eia.930:CPLW', 'Duke Energy Progress West power grid', 'EIA-930 balancing authority CPLW'),
  ('eia.930:DOPD', 'Douglas County PUD power grid', 'EIA-930 balancing authority DOPD'),
  ('eia.930:DUK', 'Duke Energy Carolinas power grid', 'EIA-930 balancing authority DUK'),
  ('eia.930:EPE', 'El Paso Electric power grid', 'EIA-930 balancing authority EPE'),
  ('eia.930:ERCO', 'ERCOT (Texas) power grid', 'EIA-930 balancing authority ERCO'),
  ('eia.930:FMPP', 'Florida Municipal Power Pool power grid', 'EIA-930 balancing authority FMPP'),
  ('eia.930:FPC', 'Duke Energy Florida power grid', 'EIA-930 balancing authority FPC'),
  ('eia.930:FPL', 'Florida Power & Light power grid', 'EIA-930 balancing authority FPL'),
  ('eia.930:GCPD', 'Grant County PUD power grid', 'EIA-930 balancing authority GCPD'),
  ('eia.930:GVL', 'Gainesville Regional Utilities power grid', 'EIA-930 balancing authority GVL'),
  ('eia.930:IID', 'Imperial Irrigation District power grid', 'EIA-930 balancing authority IID'),
  ('eia.930:IPCO', 'Idaho Power power grid', 'EIA-930 balancing authority IPCO'),
  ('eia.930:ISNE', 'ISO New England power grid', 'EIA-930 balancing authority ISNE'),
  ('eia.930:JEA', 'JEA (Jacksonville) power grid', 'EIA-930 balancing authority JEA'),
  ('eia.930:LDWP', 'Los Angeles Water and Power power grid', 'EIA-930 balancing authority LDWP'),
  ('eia.930:LGEE', 'LG&E and KU (Kentucky) power grid', 'EIA-930 balancing authority LGEE'),
  ('eia.930:MISO', 'Midcontinent ISO power grid', 'EIA-930 balancing authority MISO'),
  ('eia.930:NEVP', 'Nevada Power power grid', 'EIA-930 balancing authority NEVP'),
  ('eia.930:NWMT', 'NorthWestern Energy (Montana) power grid', 'EIA-930 balancing authority NWMT'),
  ('eia.930:NYIS', 'New York ISO power grid', 'EIA-930 balancing authority NYIS'),
  ('eia.930:PACE', 'PacifiCorp East power grid', 'EIA-930 balancing authority PACE'),
  ('eia.930:PACW', 'PacifiCorp West power grid', 'EIA-930 balancing authority PACW'),
  ('eia.930:PGE', 'Portland General Electric power grid', 'EIA-930 balancing authority PGE'),
  ('eia.930:PJM', 'PJM Interconnection power grid', 'EIA-930 balancing authority PJM'),
  ('eia.930:PNM', 'Public Service Company of New Mexico power grid', 'EIA-930 balancing authority PNM'),
  ('eia.930:PSCO', 'Public Service Company of Colorado power grid', 'EIA-930 balancing authority PSCO'),
  ('eia.930:PSEI', 'Puget Sound Energy power grid', 'EIA-930 balancing authority PSEI'),
  ('eia.930:SC', 'Santee Cooper (South Carolina) power grid', 'EIA-930 balancing authority SC'),
  ('eia.930:SCEG', 'Dominion Energy South Carolina power grid', 'EIA-930 balancing authority SCEG'),
  ('eia.930:SCL', 'Seattle City Light power grid', 'EIA-930 balancing authority SCL'),
  ('eia.930:SEC', 'Seminole Electric Cooperative power grid', 'EIA-930 balancing authority SEC'),
  ('eia.930:SOCO', 'Southern Company power grid', 'EIA-930 balancing authority SOCO'),
  ('eia.930:SPA', 'Southwestern Power Administration power grid', 'EIA-930 balancing authority SPA'),
  ('eia.930:SRP', 'Salt River Project power grid', 'EIA-930 balancing authority SRP'),
  ('eia.930:SWPP', 'Southwest Power Pool power grid', 'EIA-930 balancing authority SWPP'),
  ('eia.930:TAL', 'City of Tallahassee power grid', 'EIA-930 balancing authority TAL'),
  ('eia.930:TEC', 'Tampa Electric power grid', 'EIA-930 balancing authority TEC'),
  ('eia.930:TEPC', 'Tucson Electric Power power grid', 'EIA-930 balancing authority TEPC'),
  ('eia.930:TIDC', 'Turlock Irrigation District power grid', 'EIA-930 balancing authority TIDC'),
  ('eia.930:TPWR', 'Tacoma Power power grid', 'EIA-930 balancing authority TPWR'),
  ('eia.930:TVA', 'Tennessee Valley Authority power grid', 'EIA-930 balancing authority TVA'),
  ('eia.930:WACM', 'WAPA Rocky Mountain power grid', 'EIA-930 balancing authority WACM'),
  ('eia.930:WALC', 'WAPA Desert Southwest power grid', 'EIA-930 balancing authority WALC'),
  ('eia.930:WAUW', 'WAPA Upper Great Plains West power grid', 'EIA-930 balancing authority WAUW'),
  ('eia.930:US48', 'Lower-48 US power grid', 'EIA-930 region US48'),
  ('iem.warn:__total__', 'NWS warnings and advisories issued (all types)', 'NWS VTEC code __total__ (Iowa Environmental Mesonet)'),
  ('iem.warn:DS.W', 'NWS dust storm warnings issued', 'NWS VTEC code DS.W (Iowa Environmental Mesonet)'),
  ('iem.warn:DS.Y', 'NWS blowing dust advisories issued', 'NWS VTEC code DS.Y (Iowa Environmental Mesonet)'),
  ('iem.warn:EW.W', 'NWS extreme wind warnings issued', 'NWS VTEC code EW.W (Iowa Environmental Mesonet)'),
  ('iem.warn:FA.W', 'NWS areal flood warnings issued', 'NWS VTEC code FA.W (Iowa Environmental Mesonet)'),
  ('iem.warn:FA.Y', 'NWS areal flood advisories issued', 'NWS VTEC code FA.Y (Iowa Environmental Mesonet)'),
  ('iem.warn:FF.W', 'NWS flash flood warnings issued', 'NWS VTEC code FF.W (Iowa Environmental Mesonet)'),
  ('iem.warn:FL.A', 'NWS flood watches issued', 'NWS VTEC code FL.A (Iowa Environmental Mesonet)'),
  ('iem.warn:FL.W', 'NWS flood warnings issued', 'NWS VTEC code FL.W (Iowa Environmental Mesonet)'),
  ('iem.warn:FL.Y', 'NWS flood advisories issued', 'NWS VTEC code FL.Y (Iowa Environmental Mesonet)'),
  ('iem.warn:MA.W', 'NWS special marine warnings issued', 'NWS VTEC code MA.W (Iowa Environmental Mesonet)'),
  ('iem.warn:SQ.W', 'NWS snow squall warnings issued', 'NWS VTEC code SQ.W (Iowa Environmental Mesonet)'),
  ('iem.warn:SV.W', 'NWS severe thunderstorm warnings issued', 'NWS VTEC code SV.W (Iowa Environmental Mesonet)'),
  ('iem.warn:TO.W', 'NWS tornado warnings issued', 'NWS VTEC code TO.W (Iowa Environmental Mesonet)'),
  ('fema.decl:all', 'FEMA disaster declarations (all types)', 'OpenFEMA, all declarations'),
  ('fema.decl:DR', 'FEMA major disaster declarations', 'OpenFEMA declaration type DR'),
  ('fema.decl:EM', 'FEMA emergency declarations', 'OpenFEMA declaration type EM'),
  ('fema.decl:FM', 'FEMA fire management declarations', 'OpenFEMA declaration type FM'),
  ('fema.decl:it:chemical', 'FEMA declarations for chemical incidents', 'OpenFEMA incident type chemical'),
  ('fema.decl:it:earthquake', 'FEMA declarations for earthquakes', 'OpenFEMA incident type earthquake'),
  ('fema.decl:it:fire', 'FEMA declarations for fires', 'OpenFEMA incident type fire'),
  ('fema.decl:it:flood', 'FEMA declarations for floods', 'OpenFEMA incident type flood'),
  ('fema.decl:it:hurricane', 'FEMA declarations for hurricanes', 'OpenFEMA incident type hurricane'),
  ('fema.decl:it:other', 'FEMA declarations for other incidents', 'OpenFEMA incident type other'),
  ('fema.decl:it:severe_storm', 'FEMA declarations for severe storms', 'OpenFEMA incident type severe_storm'),
  ('fema.decl:it:straight_line_winds', 'FEMA declarations for straight-line winds', 'OpenFEMA incident type straight_line_winds'),
  ('fema.decl:it:tropical_depression', 'FEMA declarations for tropical depressions', 'OpenFEMA incident type tropical_depression'),
  ('fema.decl:it:tropical_storm', 'FEMA declarations for tropical storms', 'OpenFEMA incident type tropical_storm'),
  ('fema.decl:it:typhoon', 'FEMA declarations for typhoons', 'OpenFEMA incident type typhoon'),
  ('fema.decl:it:winter_storm', 'FEMA declarations for winter storms', 'OpenFEMA incident type winter_storm'),
  ('fema.decl:st:AK', 'FEMA declarations in Alaska', 'OpenFEMA state AK'),
  ('fema.decl:st:AL', 'FEMA declarations in Alabama', 'OpenFEMA state AL'),
  ('fema.decl:st:AR', 'FEMA declarations in Arkansas', 'OpenFEMA state AR'),
  ('fema.decl:st:AZ', 'FEMA declarations in Arizona', 'OpenFEMA state AZ'),
  ('fema.decl:st:CA', 'FEMA declarations in California', 'OpenFEMA state CA'),
  ('fema.decl:st:CO', 'FEMA declarations in Colorado', 'OpenFEMA state CO'),
  ('fema.decl:st:CT', 'FEMA declarations in Connecticut', 'OpenFEMA state CT'),
  ('fema.decl:st:DC', 'FEMA declarations in Washington, DC', 'OpenFEMA state DC'),
  ('fema.decl:st:DE', 'FEMA declarations in Delaware', 'OpenFEMA state DE'),
  ('fema.decl:st:FL', 'FEMA declarations in Florida', 'OpenFEMA state FL'),
  ('fema.decl:st:GA', 'FEMA declarations in Georgia', 'OpenFEMA state GA'),
  ('fema.decl:st:HI', 'FEMA declarations in Hawaii', 'OpenFEMA state HI'),
  ('fema.decl:st:IA', 'FEMA declarations in Iowa', 'OpenFEMA state IA'),
  ('fema.decl:st:ID', 'FEMA declarations in Idaho', 'OpenFEMA state ID'),
  ('fema.decl:st:IL', 'FEMA declarations in Illinois', 'OpenFEMA state IL'),
  ('fema.decl:st:IN', 'FEMA declarations in Indiana', 'OpenFEMA state IN'),
  ('fema.decl:st:KS', 'FEMA declarations in Kansas', 'OpenFEMA state KS'),
  ('fema.decl:st:KY', 'FEMA declarations in Kentucky', 'OpenFEMA state KY'),
  ('fema.decl:st:LA', 'FEMA declarations in Louisiana', 'OpenFEMA state LA'),
  ('fema.decl:st:MA', 'FEMA declarations in Massachusetts', 'OpenFEMA state MA'),
  ('fema.decl:st:MD', 'FEMA declarations in Maryland', 'OpenFEMA state MD'),
  ('fema.decl:st:ME', 'FEMA declarations in Maine', 'OpenFEMA state ME'),
  ('fema.decl:st:MI', 'FEMA declarations in Michigan', 'OpenFEMA state MI'),
  ('fema.decl:st:MN', 'FEMA declarations in Minnesota', 'OpenFEMA state MN'),
  ('fema.decl:st:MO', 'FEMA declarations in Missouri', 'OpenFEMA state MO'),
  ('fema.decl:st:MS', 'FEMA declarations in Mississippi', 'OpenFEMA state MS'),
  ('fema.decl:st:MT', 'FEMA declarations in Montana', 'OpenFEMA state MT'),
  ('fema.decl:st:NC', 'FEMA declarations in North Carolina', 'OpenFEMA state NC'),
  ('fema.decl:st:ND', 'FEMA declarations in North Dakota', 'OpenFEMA state ND'),
  ('fema.decl:st:NE', 'FEMA declarations in Nebraska', 'OpenFEMA state NE'),
  ('fema.decl:st:NH', 'FEMA declarations in New Hampshire', 'OpenFEMA state NH'),
  ('fema.decl:st:NJ', 'FEMA declarations in New Jersey', 'OpenFEMA state NJ'),
  ('fema.decl:st:NM', 'FEMA declarations in New Mexico', 'OpenFEMA state NM'),
  ('fema.decl:st:NV', 'FEMA declarations in Nevada', 'OpenFEMA state NV'),
  ('fema.decl:st:NY', 'FEMA declarations in New York', 'OpenFEMA state NY'),
  ('fema.decl:st:OH', 'FEMA declarations in Ohio', 'OpenFEMA state OH'),
  ('fema.decl:st:OK', 'FEMA declarations in Oklahoma', 'OpenFEMA state OK'),
  ('fema.decl:st:OR', 'FEMA declarations in Oregon', 'OpenFEMA state OR'),
  ('fema.decl:st:PA', 'FEMA declarations in Pennsylvania', 'OpenFEMA state PA'),
  ('fema.decl:st:PR', 'FEMA declarations in Puerto Rico', 'OpenFEMA state PR'),
  ('fema.decl:st:RI', 'FEMA declarations in Rhode Island', 'OpenFEMA state RI'),
  ('fema.decl:st:SC', 'FEMA declarations in South Carolina', 'OpenFEMA state SC'),
  ('fema.decl:st:SD', 'FEMA declarations in South Dakota', 'OpenFEMA state SD'),
  ('fema.decl:st:TN', 'FEMA declarations in Tennessee', 'OpenFEMA state TN'),
  ('fema.decl:st:TX', 'FEMA declarations in Texas', 'OpenFEMA state TX'),
  ('fema.decl:st:UT', 'FEMA declarations in Utah', 'OpenFEMA state UT'),
  ('fema.decl:st:VA', 'FEMA declarations in Virginia', 'OpenFEMA state VA'),
  ('fema.decl:st:VT', 'FEMA declarations in Vermont', 'OpenFEMA state VT'),
  ('fema.decl:st:WA', 'FEMA declarations in Washington state', 'OpenFEMA state WA'),
  ('fema.decl:st:WI', 'FEMA declarations in Wisconsin', 'OpenFEMA state WI'),
  ('fema.decl:st:WV', 'FEMA declarations in West Virginia', 'OpenFEMA state WV'),
  ('fema.decl:st:WY', 'FEMA declarations in Wyoming', 'OpenFEMA state WY'),
  ('fema.decl:st:GU', 'FEMA declarations in Guam', 'OpenFEMA state GU'),
  ('fema.decl:st:VI', 'FEMA declarations in US Virgin Islands', 'OpenFEMA state VI'),
  ('fema.decl:st:AS', 'FEMA declarations in American Samoa', 'OpenFEMA state AS'),
  ('fema.decl:st:MP', 'FEMA declarations in Northern Mariana Islands', 'OpenFEMA state MP'),
  ('mta.ridership:aar', 'NYC Access-A-Ride trips', 'MTA ridership series aar'),
  ('mta.ridership:bt', 'MTA bridge and tunnel crossings', 'MTA ridership series bt'),
  ('mta.ridership:bus', 'NYC bus riders', 'MTA ridership series bus'),
  ('mta.ridership:cbd_entries', 'Manhattan central business district entries', 'MTA ridership series cbd_entries'),
  ('mta.ridership:crz_entries', 'Manhattan congestion zone entries', 'MTA ridership series crz_entries'),
  ('mta.ridership:lirr', 'Long Island Rail Road riders', 'MTA ridership series lirr'),
  ('mta.ridership:mnr', 'Metro-North riders', 'MTA ridership series mnr'),
  ('mta.ridership:sir', 'Staten Island Railway riders', 'MTA ridership series sir'),
  ('mta.ridership:subway', 'NYC subway riders', 'MTA ridership series subway'),
  ('tsa.pax:checkpoint', 'US air travellers at TSA checkpoints', 'TSA checkpoint travel numbers'),
  ('npm.dl:@anthropic-ai/sdk', 'npm downloads of @anthropic-ai/sdk', 'npm package @anthropic-ai/sdk'),
  ('npm.dl:@modelcontextprotocol/sdk', 'npm downloads of @modelcontextprotocol/sdk', 'npm package @modelcontextprotocol/sdk'),
  ('npm.dl:axios', 'npm downloads of axios', 'npm package axios'),
  ('npm.dl:express', 'npm downloads of express', 'npm package express'),
  ('npm.dl:langchain', 'npm downloads of langchain', 'npm package langchain'),
  ('npm.dl:next', 'npm downloads of next', 'npm package next'),
  ('npm.dl:ollama', 'npm downloads of ollama', 'npm package ollama'),
  ('npm.dl:openai', 'npm downloads of openai', 'npm package openai'),
  ('npm.dl:react', 'npm downloads of react', 'npm package react'),
  ('npm.dl:svelte', 'npm downloads of svelte', 'npm package svelte'),
  ('npm.dl:typescript', 'npm downloads of typescript', 'npm package typescript'),
  ('npm.dl:vue', 'npm downloads of vue', 'npm package vue'),
  ('pypi.dl:anthropic', 'PyPI downloads of anthropic', 'PyPI package anthropic'),
  ('pypi.dl:fastapi', 'PyPI downloads of fastapi', 'PyPI package fastapi'),
  ('pypi.dl:langchain', 'PyPI downloads of langchain', 'PyPI package langchain'),
  ('pypi.dl:numpy', 'PyPI downloads of numpy', 'PyPI package numpy'),
  ('pypi.dl:openai', 'PyPI downloads of openai', 'PyPI package openai'),
  ('pypi.dl:requests', 'PyPI downloads of requests', 'PyPI package requests'),
  ('pypi.dl:torch', 'PyPI downloads of torch', 'PyPI package torch'),
  ('pypi.dl:transformers', 'PyPI downloads of transformers', 'PyPI package transformers'),
  ('gh.stars:openai/openai-python', 'GitHub stars on openai/openai-python', 'GitHub repository openai/openai-python'),
  ('hn.algolia:chatgpt', 'Hacker News posts mentioning ChatGPT', 'HN Search query chatgpt'),
  ('se.api:chatgpt', 'Stack Exchange posts on ChatGPT', 'Stack Exchange query chatgpt'),
  ('tranco.rank:chatgpt.com', 'Web popularity rank of chatgpt.com (Tranco)', 'Tranco domain chatgpt.com')
on conflict (node) do update set label = excluded.label, basis = excluded.basis;
-- The versions the public may see: every frozen version that the audit did not withhold
create or replace view ripples.rm_public_versions with (security_invoker = true) as
  select v.* from ripples.att_cascade_versions v
   where not exists (select 1 from ripples.rm_version_audit a where a.event_id = v.event_id and a.version = v.version and a.withheld);
revoke all on ripples.rm_public_versions from public, anon, authenticated;

-- Frozen versions are immutable (ENGINE §1.5 "published cards never change")
create or replace function ripples._rm_versions_immutable() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'att_cascade_versions rows are frozen (event %, version %)', old.event_id, old.version using errcode = 'P0001';
end $$;
drop trigger if exists rm_versions_immutable on ripples.att_cascade_versions;
create trigger rm_versions_immutable before update or delete on ripples.att_cascade_versions
  for each row execute function ripples._rm_versions_immutable();

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Small helpers
-- ---------------------------------------------------------------------------------------------------------------------
-- The eight public domains (EXPERIENCE §3) from an engine channel code
create or replace function ripples.rm_domain(p_channel text) returns text
language sql immutable set search_path = '' as $$
  select case p_channel when 'READ' then 'reading' when 'SRCH' then 'reading' when 'SOC' then 'chatter' when 'NEWS' then 'chatter'
                        when 'TV' then 'chatter' when 'PM' then 'markets' when 'ECON' then 'markets' when 'MONEY' then 'markets'
                        when 'BLD' then 'builders' when 'PHYS' then 'real_world' when 'JOBS' then 'jobs' when 'INST' then 'institutions'
                        when 'CONS' then 'stuff' end
$$;
-- WS-B's cascade builder uses finer domain codes (att_domain_of); fold them into the eight
create or replace function ripples.rm_domain8(p text) returns text
language sql immutable set search_path = '' as $$
  select case p when 'reading' then 'reading' when 'search' then 'reading' when 'social' then 'chatter' when 'news' then 'chatter'
                when 'chatter' then 'chatter' when 'markets' then 'markets' when 'economy' then 'markets' when 'builders' then 'builders'
                when 'consumption' then 'stuff' when 'stuff' then 'stuff' when 'real_world' then 'real_world' when 'jobs' then 'jobs'
                when 'institutions' then 'institutions' else 'reading' end
$$;
create or replace function ripples.rm_domain_word(p text) returns text
language sql immutable set search_path = '' as $$
  select case p when 'reading' then 'Reading' when 'chatter' then 'Chatter' when 'markets' then 'Markets' when 'builders' then 'Builders'
                when 'real_world' then 'Real world' when 'jobs' then 'Jobs' when 'institutions' then 'Institutions' when 'stuff' then 'Stuff' end
$$;
create or replace function ripples.rm_domain_icon(p text) returns text
language sql immutable set search_path = '' as $$
  select case p when 'reading' then '📖' when 'chatter' then '💬' when 'markets' then '📊' when 'builders' then '🧰'
                when 'real_world' then '🛫' when 'jobs' then '🧑‍💼' when 'institutions' then '🏛' when 'stuff' then '🛍' else '◌' end
$$;
create or replace function ripples.rm_channel_word(p text) returns text
language sql immutable set search_path = '' as $$
  select case p when 'READ' then 'Reading' when 'SRCH' then 'Search' when 'SOC' then 'Chatter' when 'NEWS' then 'News' when 'TV' then 'TV news'
                when 'PM' then 'Prediction markets' when 'ECON' then 'Rates and prices' when 'BLD' then 'Builders' when 'PHYS' then 'Real world'
                when 'JOBS' then 'Jobs' when 'INST' then 'Institutions' when 'CONS' then 'Stuff' else p end
$$;
create or replace function ripples.rm_family_emoji(p text) returns text
language sql immutable set search_path = '' as $$
  select case p when 'hazard.storm' then '🌀' when 'hazard.flood' then '🌊' when 'hazard.wildfire' then '🔥' when 'hazard.heat' then '🌡'
                when 'hazard.cold' then '🥶' when 'hazard.quake' then '🌍' when 'tech.model_release' then '🤖' when 'tech.software_release' then '💾'
                when 'policy.macro_release' then '🏦' when 'policy.decision' then '⚖' when 'media.film' then '🎬' when 'media.game' then '🎮'
                when 'media.series' then '📺' when 'person' then '👤' else '🔹' end
$$;
-- Quiet mode (EXPERIENCE §2/§8): the engine's sensitive flag, or any hazard family (hazards with harm)
create or replace function ripples.rm_sensitive(p_event bigint) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(e.sensitive, false) or e.family like 'hazard.%' from ripples.att_events e where e.event_id = p_event
$$;
-- Public slug: {label-kebab}-{event_id}; the id is the key, the label is cosmetic (EXPERIENCE §1)
create or replace function ripples.rm_slug(p_event bigint) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(nullif(trim(both '-' from left(regexp_replace(lower(coalesce(e.label, '')), '[^a-z0-9]+', '-', 'g'), 60)), ''), 'line')
         || '-' || e.event_id
    from ripples.att_events e where e.event_id = p_event
$$;
create or replace function ripples.rm_event_from_slug(p_slug text) returns bigint
language sql immutable set search_path = '' as $$
  select case when p_slug ~ '-[0-9]{1,18}$' then substring(p_slug from '([0-9]{1,18})$')::bigint end
$$;
-- A line is public iff it is a real / library / control event with at least one frozen version that is not withheld
create or replace function ripples.rm_is_public(p_event bigint) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from ripples.att_events e where e.event_id = p_event and e.role in ('real','library','positive_control'))
     and exists (select 1 from ripples.rm_public_versions v where v.event_id = p_event)
$$;
-- node ids are 'Q…' or 'source:key'; MONEY sources (tickers) never reach a public payload
create or replace function ripples.rm_node_hidden(p_node text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(p_node ~ '^Q[0-9]+$', false) = false
     and exists (select 1 from ripples.att_sources s where s.source = split_part(p_node, ':', 1) and s.engine_channel = 'MONEY')
$$;
create or replace function ripples.rm_round_arr(p jsonb, p_digits int default 2) returns jsonb
language sql immutable set search_path = '' as $$
  select case when p is null or jsonb_typeof(p) <> 'array' then null else
    coalesce((select jsonb_agg(case when jsonb_typeof(x) = 'number' then to_jsonb(round((x #>> '{}')::numeric, p_digits)) else 'null'::jsonb end order by i)
                from jsonb_array_elements(p) with ordinality a(x, i)), '[]'::jsonb) end
$$;
create or replace function ripples.rm_num(p jsonb, p_digits int) returns jsonb
language sql immutable set search_path = '' as $$
  select case when p is null or jsonb_typeof(p) <> 'number' then 'null'::jsonb else to_jsonb(round((p #>> '{}')::numeric, p_digits)) end
$$;
-- remove keys anywhere in a document (used for the version substance hash: sparklines never mint a version)
create or replace function ripples.rm_strip(j jsonb, k text[]) returns jsonb
language sql immutable set search_path = '' as $$
  select case jsonb_typeof(j)
    when 'object' then coalesce((select jsonb_object_agg(e.key, ripples.rm_strip(e.value, k)) from jsonb_each(j) e where e.key <> all (k)), '{}'::jsonb)
    when 'array'  then coalesce((select jsonb_agg(ripples.rm_strip(a.value, k) order by a.i) from jsonb_array_elements(j) with ordinality a(value, i)), '[]'::jsonb)
    else j end
$$;
create or replace function ripples.rm_hash(p jsonb) returns text
language sql immutable set search_path = '' as $$
  select encode(extensions.digest(ripples._canon(p)::text, 'sha256'), 'hex')
$$;
-- "a late-September Wednesday"
create or replace function ripples.rm_day_phrase(p date) returns text
language sql immutable set search_path = '' as $$
  select case when p is null then 'its usual day' else
    'a ' || case when extract(day from p) <= 10 then 'early' when extract(day from p) <= 20 then 'mid' else 'late' end || '-'
    || trim(to_char(p, 'FMMonth')) || ' ' || trim(to_char(p, 'FMDay')) end
$$;
create or replace function ripples.rm_lag_phrase(p_lag float8) returns text
language sql immutable set search_path = '' as $$
  select case when p_lag is null then 'after' when round(p_lag) = 0 then 'the same day as' when round(p_lag) = 1 then '1 day after'
              else round(p_lag)::int || ' days after' end
$$;
create or replace function ripples.rm_one_in(p float8, p_cap int default null) returns int
language sql immutable set search_path = '' as $$
  select case when p is null or p <= 0 then null when p_cap is null then greatest(1, floor(1 / p))::int else least(p_cap, greatest(1, floor(1 / p))::int) end
$$;
-- human wording for engine tier reasons (WS-B att_finalize codes are already mostly words)
create or replace function ripples.rm_reason(p text) returns text
language sql immutable set search_path = '' as $$
  select case p when 'waiting_series' then 'waiting for enough data' when 'provisional' then 'early look, window still open'
                when 'probably linked; a fluke is not ruled out' then null when 'holding' then 'holding from an earlier look'
                when 'q above 0.05' then 'not rare enough for Measured yet' when 'final look not reached' then 'final look not reached yet'
                when 'placebo families' then 'too few placebo families' when 'a placebo family disagrees' then 'one placebo family disagrees'
                when 'common shock day' then 'many series moved that day' when 'lag order' then 'timing is not clearly after'
                when 'one source carries it' then 'one source carries it' when 'one channel only' then 'only one channel agrees'
                else p end
$$;

-- True when a label is an identifier rather than a name: empty, the node id itself, the node's bare key (the part after
-- 'source:'), a Wikidata QID, a 'source:key' / 'source.sub:key' string, a Polymarket-style 'e:123' / 'm:123' / 'topic:123' key,
-- or a '__total__'-style placeholder.
create or replace function ripples.rm_raw_id(p_label text, p_node text default null) returns boolean
language sql immutable set search_path = '' as $$
  select p_label is null or btrim(p_label) = ''
      or p_label = p_node
      or (p_node like '%:%' and p_label = substr(p_node, strpos(p_node, ':') + 1))
      or p_label ~ '^Q[0-9]+$'
      or p_label ~ '^[a-z][a-z0-9_]*(\.[a-z0-9_]+)*:[^ ]+$'
      or p_label ~ '^(e|m|t|topic|st|it|id):[A-Za-z0-9_.:-]+$'
      or p_label ~ '^__[A-Za-z0-9_]+__$'
$$;
-- A node's public name, or NULL when it has none yet (the caller holds the stop back and counts it in `held_back`).
--   * any node: a WS-B label that is not an identifier (rm_raw_id) wins; then the curated rm_node_names row.
--   * a QID node: the article title, the topic title/label, the Wikidata English label or enwiki title (att_wd_claims, CC0,
--     filled by WS-A's att-wikidata once the contact gate opens), the title maps, the geography nodes.
--   * a source-local node ('source:key'): nothing else. Its bare key ('e:1061358', 'DGS10', 'CISO') is never a name.
create or replace function ripples.rm_label_resolve(p_node text, p_label text) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when not ripples.rm_raw_id(p_label, p_node) then p_label
    when exists (select 1 from ripples.rm_node_names nn where nn.node = p_node) then (select nn.label from ripples.rm_node_names nn where nn.node = p_node)
    when coalesce(p_node, '') !~ '^Q[0-9]+$' then null
    else (select x from (select coalesce(
      (select a.title_en from ripples.articles a where a.qid = p_node and a.title_en is not null limit 1),
      (select t.title_en from ripples.att_topics t where t.qid = p_node and t.title_en is not null limit 1),
      (select t.label from ripples.att_topics t where t.qid = p_node and t.label !~ '^Q[0-9]+$' limit 1),
      (select w.label_en from ripples.att_wd_claims w where w.qid = p_node and w.status = 'ok' and w.label_en is not null limit 1),
      (select replace(w.enwiki, '_', ' ') from ripples.att_wd_claims w where w.qid = p_node and w.status = 'ok' and w.enwiki is not null limit 1),
      (select w2.label_en from ripples.att_wd_claims w join ripples.att_wd_claims w2 on w2.qid = w.redirect_to
        where w.qid = p_node and w.status = 'redirect' and w2.label_en is not null limit 1),
      (select m.title_en from ripples.title_map m where m.qid = p_node and m.title_en is not null limit 1),
      (select replace(m.title, '_', ' ') from ripples.att_qid_map m where m.qid = p_node and m.wiki in ('enwiki', 'en', 'en.wikipedia') limit 1),
      (select g.label from ripples.att_geo_nodes g where g.qid = p_node and g.label is not null and g.label !~ '^Q[0-9]+$' limit 1)) x) y
      where not ripples.rm_raw_id(y.x, p_node))
  end
$$;
-- the name or the raw id (for callers that must show something; public payloads use rm_label_resolve and hold back NULLs)
create or replace function ripples.rm_label(p_node text, p_label text) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(ripples.rm_label_resolve(p_node, p_label), p_node)
$$;
-- Every string in a public document that still shows a raw identifier. Machine keys (node ids, slugs, urls, hashes, ledger,
-- series, geo, channel codes) are stripped first; the node ids themselves are read from the document to learn its keys.
-- A string leaks when it:
--   * is, or contains, a QID ("Q76", "… → Q76");
--   * contains a 'source:key' token ("poly.mkt:e:1", "fred:DGS10") or a Polymarket-style key ("e:1061358", "topic:403");
--   * equals a node id or a node's bare key ("DGS10", "checkpoint"), starts with one ("e:1061358 ran …"), or names one after
--     an arrow ("Xi Jinping → e:1061358");
--   * contains a '__total__'-style placeholder.
-- Empty array = clean. (Before 2026-09-26 only QIDs were detected; the independent verification found source keys passing.)
create or replace function ripples.rm_label_leaks(p jsonb, p_skip text[] default array['node','id','slug','url','csv','payload_hash','ledger',
                                                   'template','spark','band','series','band_lo','band_hi','last_year','licences','sources','source_keys',
                                                   'geo','code','source_key']) returns text[]
language sql immutable set search_path = '' as $$
  with keys as (
    select distinct k from (
      select x #>> '{}' nid from jsonb_path_query(p, 'lax $.**.node') x where jsonb_typeof(x) = 'string'
      union select x #>> '{}' from jsonb_path_query(p, 'lax $.**.id') x where jsonb_typeof(x) = 'string') ids,
    lateral (select ids.nid union select substr(ids.nid, strpos(ids.nid, ':') + 1) where ids.nid like '%:%') kk(k)
    where ids.nid !~ '^Q[0-9]+$' and ids.nid like '%:%' and length(kk.k) > 0),
  esc as (select k, replace(replace(replace(k, '\', '\\'), '%', '\%'), '_', '\_') e from keys),
  strs as (select x #>> '{}' s from jsonb_path_query(ripples.rm_strip(p, p_skip), 'strict $.**') x where jsonb_typeof(x) = 'string')
  select coalesce(array_agg(distinct s order by s), '{}') from strs
   where s ~ '^Q[0-9]+$' or s ~ '(^|[^A-Za-z0-9_:./-])Q[0-9]{2,}([^A-Za-z0-9_]|$)'
      or s ~ '(^|[^A-Za-z0-9_])(e|m|t|topic):[0-9]+'
      or s ~ '(^|[^A-Za-z0-9_./@-])[a-z][a-z0-9_]*(\.[a-z0-9_]+)+:[^ ]'
      or s ~ '__[A-Za-z0-9_]+__'
      or exists (select 1 from esc where strs.s = esc.k or strs.s like esc.e || ' %' or strs.s like '%→ ' || esc.e
                                        or strs.s like '%→ ' || esc.e || ' %' or strs.s like '%→ ' || esc.e || '.%' or strs.s like '%→ ' || esc.e || ',%')
$$;
-- "0.91× its normal" (log kinds) or "0.40 points above its normal" (rates: rho is a difference in points, not a multiple)
create or replace function ripples.rm_mult_phrase(p_rho numeric, p_unit text, p_short boolean default false) returns text
language sql immutable set search_path = '' as $$
  select case when p_rho is null then 'an unknown amount against its normal'
              when p_unit = 'points' then
                trim(to_char(abs(round(p_rho, 2)), 'FM999990.00')) || case when abs(round(p_rho, 2)) = 1 then ' point ' else ' points ' end
                || case when p_rho < 0 then 'below' else 'above' end || case when p_short then ' normal' else ' its normal' end
              when p_short then trim(to_char(round(p_rho, 2), 'FM999990.00')) || ' times normal'
              else trim(to_char(round(p_rho, 2), 'FM999990.00')) || '× its normal' end
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Series helpers for the evidence card (read WS-B's att_zvec; ×normal = exp(resid) for log kinds, points for rates)
-- ---------------------------------------------------------------------------------------------------------------------
-- best series of a hop: an agreeing outcome channel first, then the highest ž; fallback the node's first series
create or replace function ripples.rm_hop_series(p_hop bigint) returns table(series_id bigint, channel text)
language sql stable security definer set search_path = '' as $$
  with t as (select s_by_channel from ripples.att_hop_tests where hop_id = p_hop and s_by_channel is not null order by look_no desc limit 1),
  b as (select (e.value ->> 'best_series')::bigint sid, e.key ch
          from t, jsonb_each(t.s_by_channel) e
         where (e.value ->> 'best_series') is not null
         order by ((e.value ->> 'zhat')::float8 >= 3) desc,
                  (select cs.kind = 'outcome' from ripples.att_channel_stat cs where cs.channel = e.key) desc nulls last,
                  (e.value ->> 'zhat')::float8 desc nulls last limit 1)
  select sid, ch from b
  union all
  select ns.series_id, ns.channel from ripples.att_node_series ns join ripples.att_hop_candidates c on c.node = ns.node
   where c.hop_id = p_hop and not exists (select 1 from b) order by 1 limit 1
$$;
-- window average multiple (the "0.98×" of a stayed-flat stub): exp(mean resid) over [onset, onset + L_c]
create or replace function ripples.rm_window_mult(p_series bigint, p_from date, p_days int) returns numeric
language sql stable security definer set search_path = '' as $$
  select round(case when z.value_kind = 'rate' then avg(z.resid[i])::numeric else exp(avg(z.resid[i]))::numeric end, 2)
    from ripples.att_zvec z, generate_series(greatest(1, (p_from - z.from_day) + 1), least(z.n, (p_from - z.from_day) + 1 + greatest(p_days, 0))) i
   where z.series_id = p_series and z.grain = 'day' and z.resid[i] is not null
   group by z.value_kind
$$;
-- q1 window: [onset − 91, min(onset + 28, as_of)], ×normal, the ±1.28σ band, and the same days a year earlier (t − 364)
create or replace function ripples.rm_series_window(p_series bigint, p_onset date, p_end date) returns jsonb
language sql stable security definer set search_path = '' as $$
  with z as (select * from ripples.att_zvec where series_id = p_series and grain = 'day'),
  d as (select g::date as dd, row_number() over (order by g) - 1 as idx
          from generate_series(p_onset - 91, least(p_onset + 28, p_end), interval '1 day') g),
  v as (select d.idx, d.dd,
               case when z.value_kind = 'rate' then z.resid[(d.dd - z.from_day) + 1] else exp(z.resid[(d.dd - z.from_day) + 1]) end x,
               case when z.value_kind = 'rate' then z.resid[(d.dd - 364 - z.from_day) + 1] else exp(z.resid[(d.dd - 364 - z.from_day) + 1]) end ly,
               case when z.value_kind = 'rate' then -1.28 * z.sigma else exp(-1.28 * z.sigma) end lo,
               case when z.value_kind = 'rate' then 1.28 * z.sigma else exp(1.28 * z.sigma) end hi
          from d cross join z)
  select jsonb_build_object(
    'series', coalesce(jsonb_agg(case when x is null then null else round(x::numeric, 3) end order by idx), '[]'::jsonb),
    'band_lo', coalesce(jsonb_agg(round(lo::numeric, 3) order by idx), '[]'::jsonb),
    'band_hi', coalesce(jsonb_agg(round(hi::numeric, 3) order by idx), '[]'::jsonb),
    'last_year', coalesce(jsonb_agg(case when ly is null then null else round(ly::numeric, 3) end order by idx), '[]'::jsonb),
    'onset_index', 91, 'from', p_onset - 91,
    'unit', (select case when value_kind = 'rate' then 'points' else 'x' end from z))
  from v
$$;
-- how many days since the shock's attention series was last this high (null = highest in the stored window)
create or replace function ripples.rm_biggest_in_days(p_event bigint) returns int
language sql stable security definer set search_path = '' as $$
  with e as (select * from ripples.att_events where event_id = p_event),
  s as (select se.series_id from ripples.att_series se, e where se.topic_id = e.topic_id and se.source = 'wiki.pv'
         order by (se.geo = 'en.wikipedia') desc limit 1),
  z as (select z.* from ripples.att_zvec z join s using (series_id) where z.grain = 'day'),
  pk as (select i, z.resid[i] r from z, e, generate_series(greatest(1, (e.onset - z.from_day) + 1), least(z.n, (e.onset - z.from_day) + 15)) i
          where z.resid[i] is not null order by z.resid[i] desc limit 1)
  select (select pk.i - max(j) from z, generate_series(1, pk.i - 1) j where z.resid[j] >= pk.r) from pk
$$;
-- the same, with its basis spelled out so a null is never ambiguous:
--   {days: n, basis: 'days_since_higher'}          the attention series was last this high n days before the peak
--   {days: null, basis: 'highest_in_window', window_days: n}   higher than anything in the n stored days before the peak
--   {days: null, basis: 'no_data'}                  no attention series for the shock's topic
create or replace function ripples.rm_biggest(p_event bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  with e as (select * from ripples.att_events where event_id = p_event),
  s as (select se.series_id from ripples.att_series se, e where se.topic_id = e.topic_id and se.source = 'wiki.pv'
         order by (se.geo = 'en.wikipedia') desc limit 1),
  z as (select z.* from ripples.att_zvec z join s using (series_id) where z.grain = 'day'),
  pk as (select i, z.resid[i] r from z, e, generate_series(greatest(1, (e.onset - z.from_day) + 1), least(z.n, (e.onset - z.from_day) + 15)) i
          where z.resid[i] is not null order by z.resid[i] desc limit 1),
  prev as (select pk.i - max(j) d from pk, z, generate_series(1, pk.i - 1) j where z.resid[j] >= pk.r group by pk.i)
  select case when not exists (select 1 from pk) then jsonb_build_object('days', null, 'basis', 'no_data', 'window_days', null)
              when (select d from prev) is not null then jsonb_build_object('days', (select d from prev), 'basis', 'days_since_higher', 'window_days', null)
              else jsonb_build_object('days', null, 'basis', 'highest_in_window', 'window_days', (select pk.i - 1 from pk)) end
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Public path wording (ENGINE §8: the mechanism is labelled by its source; internal meta never leaves the DB)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.rm_path_public(p_path jsonb, p_parent_label text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'type', p ->> 'type',
    'template', p ->> 'template',
    'text', case p ->> 'type'
              when 'MECH' then replace(coalesce(p ->> 'text', (select t.rationale from ripples.att_mech_templates t where t.template = p ->> 'template' limit 1), ''), '->', '→')
              when 'MAP'  then coalesce(replace(p ->> 'text', '->', '→'),
                                        (select replace(t.rationale, '->', '→') from ripples.att_mech_templates t where t.template = p ->> 'template' limit 1),
                                        coalesce(p_parent_label, 'the shock') || ' → '
                                          || coalesce(ripples.rm_label_resolve(p ->> 'to', ripples.att_node_label(p ->> 'to')), 'a linked item'))
              when 'WIKI' then 'Linked from the article (structure only)'
              when 'WD'   then 'Wikidata: ' || coalesce(p ->> 'prop_label', p ->> 'prop', 'a stated relation')
              when 'CS'   then 'Readers clicked through (Wikipedia clickstream)'
              when 'GK'   then 'Named together in news coverage'
              when 'IO'   then 'An input-output link (a hypothesis, not evidence)'
              else coalesce(p ->> 'text', '') end,
    'source', case p ->> 'type'
              when 'MECH' then regexp_replace(coalesce(p ->> 'source', 'mechanism library'), 'vv([0-9])', 'v\1', 'g')
              when 'MAP'  then coalesce(p ->> 'source', 'family mapper')
              when 'WIKI' then 'Wikipedia outlink' when 'WD' then 'Wikidata' when 'CS' then 'Wikipedia clickstream'
              when 'GK' then 'GDELT co-mentions' when 'IO' then 'BEA 2017 IO table' else coalesce(p ->> 'source', '') end,
    'sign', coalesce((p ->> 'sign')::int, 0)) order by i), '[]'::jsonb)
  from jsonb_array_elements(coalesce(p_path, '[]'::jsonb)) with ordinality x(p, i)
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Cascade content (CascadePayload minus the version fields), from WS-B's att_cascades.payload + the engine tables
-- ---------------------------------------------------------------------------------------------------------------------
-- ENGINE §8 sentence templates. `unit` = 'points' (rate series) is written as points above/below normal, never as a multiple.
-- `window_closed` (window_close before the day the version is built) switches Watching / provisional wording to the past tense:
-- a closed window never reads "closes {date}" or "we expect a move by then".
create or replace function ripples.rm_sentence(p_node jsonb, p_parent_label text, p_family text) returns text
language plpgsql stable security definer set search_path = '' as $$
declare tier text := p_node ->> 'tier'; lbl text := p_node ->> 'label'; s text; rsn text := ripples.rm_reason(p_node ->> 'tier_reason');
        p1 int := (p_node ->> 'p_1_in')::int; f1 int := (p_node ->> 'f_1_in')::int; ph float8 := (p_node ->> 'p_hat')::float8;
        fam text := coalesce((select lower(f.label) from ripples.att_families f where f.family = p_family), p_family);
        src text := coalesce(p_node -> 'path' -> 0 ->> 'source', 'the mechanism graph');
        closed boolean := coalesce((p_node ->> 'window_closed')::boolean, false); wc text := p_node ->> 'window_close';
begin
  if tier = 'measured' then
    s := format('%s ran %s for %s, starting %s %s. A random pairing looks this strong about 1 in %s times. %s Consistent with a ripple from %s. Measured movement, not proof of cause.',
                lbl, ripples.rm_mult_phrase((p_node ->> 'rho')::numeric, p_node ->> 'unit'), ripples.rm_day_phrase((p_node ->> 'onset')::date),
                ripples.rm_lag_phrase((p_node ->> 'lag_days')::float8), p_parent_label, coalesce(p1::text, '?'),
                case when f1 is null then 'The fluke rate for links like this is still warming up.'
                     else format('Links like this turn out to be flukes about 1 in %s times.', case when f1 >= 50 then '50+' else f1::text end) end,
                p_parent_label);
  elsif tier = 'likely' then
    if coalesce((p_node ->> 'attention_ripple')::boolean, false) then
      s := 'Readers moved together; nothing outside attention has moved yet.';
    else
      s := 'Probably linked; a fluke isn''t ruled out.' || case when rsn is not null then ' ' || upper(left(rsn, 1)) || substr(rsn, 2) || '.' else '' end;
    end if;
    if coalesce((p_node ->> 'provisional')::boolean, false) then
      s := s || case when closed then format(' Provisional: the window closed %s; the final look is pending.', wc) else ' Provisional: the window is still open.' end;
    end if;
  elsif tier = 'watching' then
    if closed then
      s := format('The mechanism exists (%s). Its window closed %s ', src, wc)
           || case when coalesce(p_node ->> 'tier_reason', '') = 'waiting_series' or rsn = 'waiting for enough data'
                   then 'before enough data arrived to test it; the result is pending.'
                   else 'with no measurable move so far; the final look is pending.' end
           || case when ph > 0 then format(' Before the window we expected a move about 1 in %s times for %s events.', ripples.rm_one_in(ph), fam) else '' end;
    else
      s := format('The mechanism exists (%s); no measurable move yet.', src)
           || case when wc is not null then format(' Window closes %s.', wc) else '' end
           || case when ph > 0 then format(' We expect a move by then about 1 in %s times for %s events.', ripples.rm_one_in(ph), fam) else '' end;
    end if;
  elsif tier = 'retracted' then
    s := format('Retracted %s: %s.', coalesce(p_node -> 'retracted' ->> 'date', '?'), coalesce(p_node -> 'retracted' ->> 'reason', rsn, 'see the evidence'));
  else
    s := 'Stayed flat: window closed, no move.';
  end if;
  if coalesce((p_node ->> 'depth')::int, 1) >= 2 then s := s || ' … if the previous step holds.'; end if;
  return s;
end $$;

-- CascadePayload minus the version fields. p_today (default: today, UTC) decides which windows have closed.
-- Public names: a node without one (a raw QID) is held back with its whole subtree and counted in `held_back`; if a held-back
-- node is Likely or better (or retracted) the payload carries `_label_hold` and att_publish_cascade freezes nothing for the line.
drop function if exists ripples.rm_cascade_content(bigint);
create or replace function ripples.rm_cascade_content(p_event bigint, p_today date default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare ev ripples.att_events; ws jsonb; n jsonb; nodes jsonb := '[]'::jsonb; flat jsonb := '[]'::jsonb; lbl jsonb := '{}'::jsonb;
        emoji text; v_as_of date; v_today date; sid bigint; ch text; plabel text; nn jsonb; title text; why jsonb := '[]'::jsonb; fs jsonb; rho numeric;
        nm text; dropped bigint[] := '{}'; held_stops int := 0; held_flat int := 0; hold boolean := false;
begin
  select * into ev from ripples.att_events where event_id = p_event;
  if not found or ev.role not in ('real','library','positive_control') then return null; end if;
  select payload into ws from ripples.att_cascades where event_id = p_event;
  if ws is null then return null; end if;
  v_as_of := coalesce((ws ->> 'as_of')::date, ev.as_of);
  v_today := greatest(v_as_of, coalesce(p_today, (now() at time zone 'utc')::date));
  emoji := coalesce(nullif(nullif(ws -> 'event' ->> 'emoji', '◌'), ''), ripples.rm_family_emoji(ev.family));
  -- public names by hop; a node without one is held back together with everything below it
  for n in select x from jsonb_array_elements(coalesce(ws -> 'nodes', '[]'::jsonb)) x order by coalesce((x ->> 'depth')::int, 1), (x ->> 'hop_id')::bigint loop
    continue when ripples.rm_node_hidden(n ->> 'node');
    nm := ripples.rm_label_resolve(n ->> 'node', n ->> 'label');
    if nm is null or ((n ->> 'parent_hop') is not null and (n ->> 'parent_hop')::bigint = any (dropped)) then
      dropped := dropped || (n ->> 'hop_id')::bigint;
      held_stops := held_stops + 1;
      if n ->> 'tier' in ('measured','likely','retracted') then hold := true; end if;
    else
      lbl := lbl || jsonb_build_object(n ->> 'hop_id', nm);
    end if;
  end loop;
  for n in select x from jsonb_array_elements(coalesce(ws -> 'nodes', '[]'::jsonb)) x order by coalesce((x ->> 'depth')::int, 1), (x ->> 'hop_id')::bigint loop
    continue when ripples.rm_node_hidden(n ->> 'node');
    continue when (n ->> 'hop_id')::bigint = any (dropped);
    plabel := case when (n ->> 'parent_hop') is null then ev.label else coalesce(lbl ->> (n ->> 'parent_hop'), ev.label) end;
    nn := jsonb_build_object(
      'hop_id', (n ->> 'hop_id')::bigint, 'depth', coalesce((n ->> 'depth')::int, 1), 'parent_hop', n -> 'parent_hop',
      'node', n ->> 'node', 'label', lbl ->> (n ->> 'hop_id'), 'domain', ripples.rm_domain8(n ->> 'domain'), 'kind', coalesce(n ->> 'kind', 'attention'),
      'tier', n ->> 'tier', 'tier_reason', ripples.rm_reason(n ->> 'tier_reason'),
      'provisional', coalesce((n ->> 'provisional')::boolean, false), 'attention_ripple', coalesce((n ->> 'attention_ripple')::boolean, false),
      'rho', ripples.rm_num(n -> 'rho', 2), 'rho_lo', ripples.rm_num(n -> 'rho_lo', 2), 'rho_hi', ripples.rm_num(n -> 'rho_hi', 2),
      'lag_days', ripples.rm_num(n -> 'lag_days', 0), 'onset', n -> 'onset',
      'p', ripples.rm_num(n -> 'p', 4), 'p_1_in', n -> 'p_1_in', 'f', ripples.rm_num(n -> 'f', 3), 'f_1_in', n -> 'f_1_in',
      'f_warming', coalesce((n ->> 'f_warming')::boolean, (n ->> 'tier') in ('measured','likely') and (n ->> 'f') is null),
      'q', ripples.rm_num(n -> 'q', 4),
      'channels', coalesce(n -> 'channels', jsonb_build_object('agree', 0, 'of', 0)), 'crossed_domains', coalesce((n ->> 'crossed_domains')::int, 0),
      'window_close', n -> 'window_close', 'window_closed', coalesce((n ->> 'window_close')::date < v_today, false),
      -- due: a closed Watching window has none; a due date already past (WS-B's payload lags the day) moves to the next scheduled
      -- look on or after today (att_hop_candidates.looks), or none. A published due date is never in the past.
      'due', case when (n ->> 'window_close')::date < v_today and n ->> 'tier' = 'watching' then 'null'::jsonb
                  when (n ->> 'due')::date < v_today then coalesce(to_jsonb((select min(d) from ripples.att_hop_candidates hc, unnest(hc.looks) d
                                                                             where hc.hop_id = (n ->> 'hop_id')::bigint and d >= v_today)), 'null'::jsonb)
                  else n -> 'due' end,
      'route', coalesce(n ->> 'route', 'na'), 'fork_of', n -> 'fork_of',
      'retracted', coalesce(n -> 'retracted', 'null'::jsonb),
      'spark', ripples.rm_round_arr(n -> 'spark', 2),
      'band', case when n -> 'band' is not null and jsonb_typeof(n -> 'band') = 'object'
                   then jsonb_build_object('lo', ripples.rm_round_arr(n -> 'band' -> 'lo', 2), 'hi', ripples.rm_round_arr(n -> 'band' -> 'hi', 2)) end,
      'unit', coalesce(n ->> 'unit', 'x'), 'p_hat', ripples.rm_num(n -> 'p_hat', 3),
      'path', ripples.rm_path_public(n -> 'path', plabel));
    nn := nn || jsonb_build_object('sentence', ripples.rm_sentence(nn || jsonb_build_object('tier_reason', n -> 'tier_reason'), plabel, ev.family));
    nodes := nodes || nn;
  end loop;
  for n in select x from jsonb_array_elements(coalesce(ws -> 'flat', '[]'::jsonb)) x loop
    continue when ripples.rm_node_hidden(n ->> 'node');
    nm := ripples.rm_label_resolve(n ->> 'node', n ->> 'label');
    if nm is null or ((n ->> 'parent_hop') is not null and (n ->> 'parent_hop')::bigint = any (dropped)) then held_flat := held_flat + 1; continue; end if;
    select s.series_id, s.channel into sid, ch from ripples.rm_hop_series((n ->> 'hop_id')::bigint) s;
    rho := coalesce((n ->> 'rho')::numeric,
                    case when sid is not null then ripples.rm_window_mult(sid, coalesce((select c.onset from ripples.att_hop_candidates c where c.hop_id = (n ->> 'hop_id')::bigint), ev.onset),
                                                                          coalesce((select cs.l_days from ripples.att_channel_stat cs where cs.channel = ch), 7)) end);
    fs := case when sid is not null then ripples.att_spark(sid, v_as_of, 60) end;
    flat := flat || jsonb_build_object('hop_id', (n ->> 'hop_id')::bigint, 'node', n ->> 'node', 'label', nm, 'domain', ripples.rm_domain8(n ->> 'domain'),
                                       'parent_hop', n -> 'parent_hop', 'reason', coalesce(n ->> 'reason', 'window closed, no move'),
                                       'rho', round(rho, 2), 'spark', ripples.rm_round_arr(fs -> 'spark', 2));
  end loop;
  select a.title_en into title from ripples.articles a where a.qid = ev.qid;
  if title is not null then
    why := jsonb_build_array(jsonb_build_object('title', title, 'source', 'Wikipedia', 'url', ripples._wiki_url(title)));
  end if;
  return jsonb_build_object('v', 2,
    'event', jsonb_build_object('event_id', ev.event_id, 'slug', ripples.rm_slug(ev.event_id), 'label', ev.label, 'emoji', emoji, 'family', ev.family,
                                'sensitive', ripples.rm_sensitive(ev.event_id), 'reconstructed', ev.reconstructed, 'onset', ev.onset,
                                'magnitude_x', ripples.rm_num(ws -> 'event' -> 'magnitude_x', 1), 'spark', ripples.rm_round_arr(ws -> 'event' -> 'spark', 2),
                                'baseline', coalesce(ws -> 'event' -> 'baseline', jsonb_build_object('from', ev.onset - 111, 'to', ev.onset - 21)), 'why', why),
    'as_of', v_as_of, 'status', coalesce(ws ->> 'status', ev.status), 'method', coalesce(ws ->> 'method', '6.0'),
    'denominators', jsonb_build_object('tested', coalesce((ws -> 'denominators' ->> 'tested')::int, 0), 'moved', coalesce((ws -> 'denominators' ->> 'moved')::int, 0),
                                       'measured', coalesce((ws -> 'denominators' ->> 'measured')::int, 0),
                                       'expected_false_links', ripples.rm_num(ws -> 'denominators' -> 'expected_false_links', 3),
                                       'sum_p', ripples.rm_num(ws -> 'denominators' -> 'sum_p', 3)),
    'weakest_tier', ws -> 'weakest_tier', 'depth', coalesce((ws ->> 'depth')::int, 0),
    'nodes', nodes, 'flat', flat, 'route_ideas', coalesce(ws -> 'route_ideas', '[]'::jsonb),
    'held_back', jsonb_build_object('stops', held_stops, 'flat', held_flat, 'reason', 'waiting for a public name'),
    'control', coalesce(ws -> 'control', 'null'::jsonb),
    'rivals', coalesce((select jsonb_agg(jsonb_build_object('event_id', (r ->> 'event_id')::bigint, 'label', r ->> 'label', 'note', coalesce(r ->> 'note', 'also active this week'))
                                         order by (r ->> 'event_id')::bigint)
                          from jsonb_array_elements(coalesce(ws -> 'rivals', '[]'::jsonb)) r), '[]'::jsonb))
    || case when hold then jsonb_build_object('_label_hold', true) else '{}'::jsonb end;
end $$;

-- the stop count a share line and grown_since use: Likely-or-better stations
create or replace function ripples.rm_stops(p jsonb) returns int
language sql immutable set search_path = '' as $$
  select count(*)::int from jsonb_array_elements(coalesce(p -> 'nodes', '[]'::jsonb)) n where n ->> 'tier' in ('measured','likely')
$$;

create or replace function ripples.rm_share_text(p jsonb, p_version int) returns jsonb
language plpgsql stable set search_path = '' as $$
declare url text := 'https://bensunter.com/ripples/line/' || (p -> 'event' ->> 'slug') || '/v' || p_version || '/';
        icons text; watch text; moved int := ripples.rm_stops(p); days int; st text; meas int; doms text;
begin
  select string_agg(ripples.rm_domain_icon(n ->> 'domain'), '━' order by (n ->> 'depth')::int, n ->> 'onset' nulls last, (n ->> 'hop_id')::bigint) into icons
    from jsonb_array_elements(p -> 'nodes') n where n ->> 'tier' in ('measured','likely');
  select string_agg('┄' || ripples.rm_domain_icon(d), '') into watch
    from (select distinct n ->> 'domain' d from jsonb_array_elements(p -> 'nodes') n
           where n ->> 'tier' = 'watching' and not coalesce((n ->> 'window_closed')::boolean, false) order by 1 limit 2) x;
  days := greatest(0, (p ->> 'as_of')::date - (p -> 'event' ->> 'onset')::date);
  st := case p ->> 'status' when 'running' then 'still running' when 'nowhere' then 'went nowhere' else 'line ended' end;
  select count(*), string_agg(distinct ripples.rm_domain_word(n ->> 'domain'), ', ') into meas, doms
    from jsonb_array_elements(p -> 'nodes') n where n ->> 'tier' = 'measured';
  return jsonb_build_object(
    'text_share', (p -> 'event' ->> 'emoji') || ' ' || (p -> 'event' ->> 'label') || ' ' || coalesce('━' || icons, '') || coalesce(watch, '') || E'\n'
                  || moved || case when moved = 1 then ' stop' else ' stops' end || ' in ' || days || case when days = 1 then ' day, ' else ' days, ' end || st || E'\n'
                  || 'consistent with, not proof of cause' || E'\n' || url,
    'text_plain', (p -> 'event' ->> 'label') || ': '
                  || case when meas > 0 then meas || ' measured ' || case when meas = 1 then 'stop' else 'stops' end || ' (' || doms || ')'
                          else moved || case when moved = 1 then ' stop' else ' stops' end || ', none Measured yet' end
                  || ' in ' || days || case when days = 1 then ' day. ' else ' days. ' end || url);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Freezing versions (att_publish_cascade: one line; att_publish_cascades: the day) — ENGINE §10.3
-- ---------------------------------------------------------------------------------------------------------------------
-- Audit every frozen version not yet audited (versions are immutable: once each). A version with a raw identifier in its public
-- text is withheld and the withholding is written to the ledger (kind version_publish, withheld: true). Returns rows withheld now.
-- Audits every frozen version not yet withheld, on every run: new versions once, and public versions again whenever the guard
-- (rm_label_leaks) learns a new pattern, so a guard fix withholds versions frozen under the weaker guard. Idempotent.
create or replace function ripples.rm_audit_versions() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0; l text[]; seq bigint;
begin
  for r in select v.event_id, v.version, v.payload, a.event_id is not null audited
             from ripples.att_cascade_versions v
             left join ripples.rm_version_audit a on a.event_id = v.event_id and a.version = v.version
            where a.event_id is null or not a.withheld
            order by v.event_id, v.version loop
    l := ripples.rm_label_leaks(r.payload);
    seq := null;
    if cardinality(l) > 0 then
      seq := ripples.att_ledger_append((now() at time zone 'utc')::date, 'version_publish', jsonb_build_object('event_id', r.event_id, 'version', r.version),
                                       jsonb_build_object('event_id', r.event_id, 'version', r.version, 'withheld', true,
                                                          'reason', 'raw identifiers in public labels', 'leaks', cardinality(l)));
      n := n + 1;
    elsif r.audited then
      continue;
    end if;
    insert into ripples.rm_version_audit(event_id, version, leaks, sample, withheld, reason, ledger_seq)
    values (r.event_id, r.version, cardinality(l), l[1:5], cardinality(l) > 0,
            case when cardinality(l) > 0 then 'raw identifiers in public labels' end, seq)
    on conflict (event_id, version) do update set leaks = excluded.leaks, sample = excluded.sample, withheld = excluded.withheld,
                                                 reason = excluded.reason, ledger_seq = excluded.ledger_seq, checked_at = now();
  end loop;
  return n;
end $$;

create or replace function ripples.att_publish_cascade(p_event bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare ev ripples.att_events; c jsonb; h text; last record; lastpub record; k int; v_full jsonb; v_seq bigint; sh jsonb; n jsonb; lk text[];
begin
  select * into ev from ripples.att_events where event_id = p_event;
  if not found then return jsonb_build_object('event_id', p_event, 'error', 'unknown event'); end if;
  if ev.role not in ('real','library','positive_control') then
    return jsonb_build_object('event_id', p_event, 'error', 'decoy and control-twin events are never published by id');
  end if;
  c := ripples.rm_cascade_content(p_event, null);
  if c is null then return jsonb_build_object('event_id', p_event, 'error', 'no cascade payload yet'); end if;
  if ev.role in ('library','positive_control') then
    insert into ripples.rm_publish_set(event_id, note) values (p_event, 'reconstructed line') on conflict (event_id) do nothing;
  end if;
  select v.version, v.payload, v.payload_hash into last from ripples.att_cascade_versions v where v.event_id = p_event order by v.version desc limit 1;
  -- public-name guards: a Likely-or-better stop without a name, or any raw identifier left in public text, holds the version
  if coalesce((c ->> '_label_hold')::boolean, false) then
    return jsonb_build_object('event_id', p_event, 'version', last.version, 'unchanged', true, 'held', 'a Likely-or-better stop has no public name yet');
  end if;
  lk := ripples.rm_label_leaks(c);
  if cardinality(lk) > 0 then
    return jsonb_build_object('event_id', p_event, 'version', last.version, 'unchanged', true, 'held', 'raw identifier in public text', 'sample', to_jsonb(lk[1:3]));
  end if;
  -- substance hash: everything except sparklines/bands (data refreshes) and as_of
  h := ripples.rm_hash(ripples.rm_strip(c - 'as_of', array['spark','band']));
  if last.version is not null and last.payload_hash = h then
    return jsonb_build_object('event_id', p_event, 'version', last.version, 'payload_hash', h, 'unchanged', true);
  end if;
  -- grown_since compares with the last version the public could see (withheld versions are skipped)
  select v.version, v.payload into lastpub from ripples.rm_public_versions v where v.event_id = p_event order by v.version desc limit 1;
  k := coalesce(last.version, 0) + 1;
  v_seq := ripples.att_ledger_append(current_date, 'version_publish', jsonb_build_object('event_id', p_event, 'version', k),
                                     jsonb_build_object('event_id', p_event, 'version', k, 'payload_hash', h, 'reconstructed', ev.reconstructed));
  sh := ripples.rm_share_text(c, k);
  v_full := c || sh || jsonb_build_object('version', k, 'published_at', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), 'payload_hash', h,
            'grown_since', case when lastpub.version is not null then jsonb_build_object('version', lastpub.version, 'stops_added', ripples.rm_stops(c) - ripples.rm_stops(lastpub.payload)) end,
            'grown_to', null,
            'ledger', jsonb_build_object('seq', v_seq, 'chain_hash', (select l.chain_hash from ripples.att_ledger l where l.seq = v_seq)));
  insert into ripples.att_cascade_versions(event_id, version, payload, payload_hash) values (p_event, k, v_full, h);
  insert into ripples.rm_version_audit(event_id, version, leaks, sample, withheld) values (p_event, k, 0, null, false) on conflict do nothing;
  update ripples.att_cascades set version = k where event_id = p_event;
  -- ENGINE §7 "freezing after publication": record the published tier and the attention evidence at first Likely+ publication
  for n in select x from jsonb_array_elements(c -> 'nodes') x where x ->> 'tier' in ('likely','measured') loop
    update ripples.att_hop_registry g
       set published_tier = n ->> 'tier', published_at = coalesce(g.published_at, now()),
           frozen_att = coalesce(g.frozen_att, (select jsonb_object_agg(e.key, e.value) from ripples.att_hop_tests t, jsonb_each(t.s_by_channel) e
                                                 where t.hop_id = g.hop_id and e.key in ('READ','SRCH','SOC')
                                                   and t.look_no = (select max(t2.look_no) from ripples.att_hop_tests t2 where t2.hop_id = g.hop_id and t2.tier is not null)))
     where g.hop_id = (n ->> 'hop_id')::bigint and (g.published_tier is distinct from n ->> 'tier');
  end loop;
  return jsonb_build_object('event_id', p_event, 'version', k, 'payload_hash', h, 'ledger_seq', v_seq, 'unchanged', false,
                            'stops', ripples.rm_stops(c), 'previous', last.version, 'held_back', c -> 'held_back');
end $$;

-- The day: freeze every public line that changed, then the day's ShockList. Idempotent.
--   p_events null → a rotation capped at p_cap lines per run: real lines with as_of in [p_as_of − 30, p_as_of] first, then lines
--   never checked, then the least recently checked (every line in rm_publish_set and every line whose latest version is not
--   archived); a line already checked today goes last, so the 08:40 run continues where the 08:25 run stopped.
--   p_events given → exactly those (library/control events join rm_publish_set), no cap.
drop function if exists ripples.att_publish_cascades(date, bigint[]);
create or replace function ripples.att_publish_cascades(p_as_of date default current_date, p_events bigint[] default null, p_cap int default 150) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare eid bigint; r jsonb; out jsonb := '[]'::jsonb; ids bigint[]; shocks jsonb := '[]'::jsonb; ctrl jsonb; line jsonb; hero jsonb; lsum jsonb;
        day_payload jsonb; h text; old record; v_seq bigint; n_new int := 0; v_pub timestamptz; n_cand int; n_withheld int; n_held int := 0;
begin
  n_withheld := ripples.rm_audit_versions();
  with cand as (
    select e.event_id, e.role = 'real' and e.as_of between p_as_of - 30 and p_as_of recent, pc.checked_at
      from ripples.att_events e join ripples.att_cascades c on c.event_id = e.event_id
      left join ripples.rm_publish_checked pc on pc.event_id = e.event_id
     where e.role in ('real','library','positive_control')
       and ((p_events is not null and e.event_id = any (p_events))
         or (p_events is null and ((e.role = 'real' and e.as_of between p_as_of - 30 and p_as_of)
                                   or e.event_id in (select s.event_id from ripples.rm_publish_set s)
                                   or exists (select 1 from ripples.att_cascade_versions v where v.event_id = e.event_id
                                                and v.version = (select max(v2.version) from ripples.att_cascade_versions v2 where v2.event_id = e.event_id)
                                                and v.payload ->> 'status' <> 'archived')))))
  select count(*)::int, coalesce((select array_agg(x.event_id order by x.event_id) from (
           select c2.event_id from cand c2
            order by (c2.checked_at is not null and (c2.checked_at at time zone 'utc')::date >= (now() at time zone 'utc')::date), not c2.recent,
                     c2.checked_at nulls first, c2.event_id
            limit case when p_events is null then greatest(coalesce(p_cap, 150), 1) else null end) x), '{}')
    into n_cand, ids from cand;
  foreach eid in array ids loop
    r := ripples.att_publish_cascade(eid);
    if (r ->> 'unchanged') = 'false' then n_new := n_new + 1; end if;
    if r ? 'held' then n_held := n_held + 1; end if;
    out := out || r;
    insert into ripples.rm_publish_checked(event_id, checked_at) values (eid, now()) on conflict (event_id) do update set checked_at = excluded.checked_at;
  end loop;

  -- ShockList (ENGINE §11): live lines of the last 14 days (or still running), ordered Measured, Likely, onset recency
  with lv as (
    select distinct on (v.event_id) v.event_id, v.version, v.payload p, e.as_of
      from ripples.rm_public_versions v join ripples.att_events e on e.event_id = v.event_id
     where e.role = 'real' and not e.reconstructed and e.as_of <= p_as_of
       and (e.as_of >= p_as_of - 13 or e.status = 'running')
     order by v.event_id, v.version desc),
  s as (
    select lv.*, (select count(*) from jsonb_array_elements(lv.p -> 'nodes') n where n ->> 'tier' = 'measured') m,
                 (select count(*) from jsonb_array_elements(lv.p -> 'nodes') n where n ->> 'tier' = 'likely') l
      from lv order by 5 desc, 6 desc, (lv.p -> 'event' ->> 'onset') desc, lv.event_id limit 20)
  select coalesce(jsonb_agg(jsonb_build_object(
      'event_id', s.event_id, 'slug', s.p -> 'event' ->> 'slug', 'label', s.p -> 'event' ->> 'label', 'emoji', s.p -> 'event' ->> 'emoji',
      'family', s.p -> 'event' ->> 'family', 'sensitive', (s.p -> 'event' ->> 'sensitive')::boolean, 'reconstructed', (s.p -> 'event' ->> 'reconstructed')::boolean,
      'onset', s.p -> 'event' ->> 'onset', 'magnitude_x', s.p -> 'event' -> 'magnitude_x',
      'biggest_in_days', b.b -> 'days', 'biggest_basis', b.b ->> 'basis', 'biggest_window_days', b.b -> 'window_days',
      'spark', s.p -> 'event' -> 'spark', 'status', s.p ->> 'status',
      'stops', jsonb_build_object('measured', s.m, 'likely', s.l,
                                  'watching', (select count(*) from jsonb_array_elements(s.p -> 'nodes') n where n ->> 'tier' = 'watching'),
                                  'flat', jsonb_array_length(coalesce(s.p -> 'flat', '[]'::jsonb))),
      'domains_reached', (select coalesce(jsonb_agg(distinct n ->> 'domain'), '[]'::jsonb) from jsonb_array_elements(s.p -> 'nodes') n where n ->> 'tier' in ('measured','likely')),
      'farthest_measured_domain', (select n ->> 'domain' from jsonb_array_elements(s.p -> 'nodes') n where n ->> 'tier' = 'measured'
                                    order by (n ->> 'depth')::int desc, (n ->> 'q')::float8 nulls last limit 1),
      -- the next due date of a window that is still open (a closed window is never "due")
      'next_due', (select min(n ->> 'due') from jsonb_array_elements(s.p -> 'nodes') n
                    where n ->> 'due' is not null and (n ->> 'due')::date > p_as_of
                      and not coalesce((n ->> 'window_closed')::boolean, false)
                      and coalesce((n ->> 'window_close')::date >= p_as_of, true)),
      'version', s.version) order by s.m desc, s.l desc, s.p -> 'event' ->> 'onset' desc, s.event_id), '[]'::jsonb)
    into shocks from s cross join lateral (select ripples.rm_biggest(s.event_id) b) b;
  -- the day's control ripple: every decoy matched to a listed line, aggregated (decoys are never addressable by id)
  select jsonb_build_object('event_id', min(d.event_id), 'label', 'a page that wasn''t trending',
           'stops', jsonb_build_object('measured', coalesce(sum(st.measured), 0), 'likely', coalesce(sum(st.likely), 0),
                                       'watching', coalesce(sum(st.watching), 0), 'flat', coalesce(sum(st.flat), 0)),
           'n_decoys', count(distinct d.event_id))
    into ctrl
    from ripples.att_events d
    left join lateral (
      select count(*) filter (where t.tier = 'measured') measured, count(*) filter (where t.tier = 'likely') likely,
             count(*) filter (where coalesce(t.tier, 'watching') = 'watching') watching, count(*) filter (where t.tier = 'flat') flat
        from ripples.att_hop_candidates c
        left join lateral (select t.tier from ripples.att_hop_tests t where t.hop_id = c.hop_id and t.tier is not null order by t.look_no desc limit 1) t on true
       where c.event_id = d.event_id and c.frozen_hash is not null) st on true
   where d.role = 'decoy' and d.matched_to in (select (x ->> 'event_id')::bigint from jsonb_array_elements(shocks) x);
  -- the day line: WS-B's finalize line for the day (att_state engine.day.<day>). When it is missing the day line is all null
  -- (source 'not available') — never a sum over lines passed off as the day. The sum over the listed lines is published
  -- separately as listed_lines_sum, labelled with its scope.
  select v into line from ripples.att_state where k = 'engine.day.' || p_as_of;
  if line is not null then
    line := jsonb_build_object('tested', coalesce((line ->> 'tested')::int, 0), 'moved', coalesce((line ->> 'moved')::int, 0),
                               'measured', coalesce((line ->> 'measured')::int, 0), 'expected_flukes', ripples.rm_num(line -> 'expected_flukes', 2),
                               'sum_p', ripples.rm_num(line -> 'sum_p', 2), 'source', 'engine day line');
  else
    line := jsonb_build_object('tested', null, 'moved', null, 'measured', null, 'expected_flukes', null, 'sum_p', null, 'source', 'not available');
  end if;
  select jsonb_build_object('tested', coalesce(sum((v.payload -> 'denominators' ->> 'tested')::int), 0),
                            'moved', coalesce(sum((v.payload -> 'denominators' ->> 'moved')::int), 0),
                            'measured', coalesce(sum((v.payload -> 'denominators' ->> 'measured')::int), 0),
                            'expected_flukes', round(coalesce(sum((v.payload -> 'denominators' ->> 'expected_false_links')::numeric), 0), 2),
                            'sum_p', round(coalesce(sum((v.payload -> 'denominators' ->> 'sum_p')::numeric), 0), 2),
                            'lines', count(*), 'scope', 'every path tested on the listed lines, over all their days; not one day''s tests')
    into lsum
    from jsonb_array_elements(shocks) x
    join ripples.att_cascade_versions v on v.event_id = (x ->> 'event_id')::bigint and v.version = (x ->> 'version')::int;
  -- hero (EXPERIENCE §2 cold-start rule): WS-E's att_hero_pick when deployed
  if to_regprocedure('ripples.att_hero_pick(date)') is not null then
    execute 'select ripples.att_hero_pick($1)' into hero using p_as_of;
    if hero is not null and (hero ->> 'event_id') is not null then
      hero := hero || jsonb_build_object('slug', ripples.rm_slug((hero ->> 'event_id')::bigint));
      if not ripples.rm_is_public((hero ->> 'event_id')::bigint) then hero := null; end if;
    else
      hero := null;   -- no Measured outcome stop live or in the published archive: the page shows the week/cold-start copy
    end if;
  end if;
  day_payload := jsonb_build_object('v', 2, 'day', p_as_of, 'method', '6.0', 'line', line, 'listed_lines_sum', lsum, 'shocks', shocks,
                                    'control', coalesce(ctrl, jsonb_build_object('event_id', null, 'label', 'a page that wasn''t trending',
                                                        'stops', jsonb_build_object('measured', 0, 'likely', 0, 'watching', 0, 'flat', 0), 'n_decoys', 0)),
                                    'hero', hero, 'since', jsonb_build_object('note', 'client compares with its stored timestamp'));
  h := ripples.rm_hash(ripples.rm_strip(day_payload, array['spark']));
  select * into old from ripples.rm_days where day = p_as_of;
  if old.day is null or old.payload_hash <> h then
    v_pub := now();
    v_seq := ripples.att_ledger_append(p_as_of, 'version_publish', jsonb_build_object('day', p_as_of), jsonb_build_object('day', p_as_of, 'payload_hash', h,
               'lines', (select coalesce(jsonb_agg(jsonb_build_array(x -> 'event_id', x -> 'version')), '[]'::jsonb) from jsonb_array_elements(shocks) x)));
    day_payload := day_payload || jsonb_build_object('published_at', to_char(v_pub at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
    insert into ripples.rm_days(day, payload, payload_hash, published_at, ledger_seq) values (p_as_of, day_payload, h, v_pub, v_seq)
    on conflict (day) do update set payload = excluded.payload, payload_hash = excluded.payload_hash, published_at = excluded.published_at, ledger_seq = excluded.ledger_seq;
  end if;
  insert into ripples.rm_publish_log(as_of, stage, result)
  values (p_as_of, 'frozen', jsonb_build_object('lines', jsonb_array_length(out), 'candidates', n_cand, 'deferred', greatest(n_cand - jsonb_array_length(out), 0),
                                                'new_versions', n_new, 'held', n_held, 'withheld_now', n_withheld, 'shocks', jsonb_array_length(shocks)));
  return jsonb_build_object('as_of', p_as_of, 'lines', out, 'candidates', n_cand, 'deferred', greatest(n_cand - jsonb_array_length(out), 0),
                            'new_versions', n_new, 'held', n_held, 'withheld_now', n_withheld,
                            'shocks', jsonb_array_length(shocks), 'day_changed', old.day is null or old.payload_hash <> h);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 6. HopEvidence (ENGINE §11), built live from the engine tables; only for hops of public lines
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.rm_hop_evidence(p_hop bigint) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare c ripples.att_hop_candidates; t ripples.att_hop_tests; ev ripples.att_events; lv jsonb; nd jsonb; sid bigint; ch text; se ripples.att_series;
        src ripples.att_sources; z ripples.att_zvec; parent_label text; q1 jsonb; chans jsonb := '[]'::jsonb; e record; lc int; best jsonb;
        dayln jsonb; lic jsonb; bh jsonb; rank int; sib jsonb; plc jsonb; n_of int; nxt date; flat_n jsonb; wclosed boolean;
begin
  select * into c from ripples.att_hop_candidates where hop_id = p_hop;
  if not found or c.role not in ('real','library','positive_control','fork_check') or c.frozen_hash is null then return null; end if;
  if ripples.rm_node_hidden(c.node) then return null; end if;
  select * into ev from ripples.att_events where event_id = c.event_id;
  if ev.role not in ('real','library','positive_control') or not ripples.rm_is_public(ev.event_id) then return null; end if;
  select v.payload into lv from ripples.rm_public_versions v where v.event_id = ev.event_id order by v.version desc limit 1;
  select x into nd from jsonb_array_elements(lv -> 'nodes') x where (x ->> 'hop_id')::bigint = p_hop;
  if nd is null then select x into flat_n from jsonb_array_elements(lv -> 'flat') x where (x ->> 'hop_id')::bigint = p_hop; end if;
  if nd is null and flat_n is null then return null; end if;             -- only stops that appear on the published line
  select * into t from ripples.att_hop_tests where hop_id = p_hop and tier is not null order by look_no desc limit 1;
  select s.series_id, s.channel into sid, ch from ripples.rm_hop_series(p_hop) s;
  select * into se from ripples.att_series where series_id = sid;
  select * into src from ripples.att_sources where source = coalesce(se.source, split_part(c.node, ':', 1));
  select * into z from ripples.att_zvec where series_id = sid and grain = 'day';
  parent_label := case when c.parent_hop is null then ev.label
                       else coalesce((select x ->> 'label' from jsonb_array_elements(lv -> 'nodes') x where (x ->> 'hop_id')::bigint = c.parent_hop),
                                     (select ripples.rm_label_resolve(c2.node, ripples.att_node_label(c2.node)) from ripples.att_hop_candidates c2 where c2.hop_id = c.parent_hop),
                                     'the previous stop') end;
  wclosed := coalesce((nd ->> 'window_close')::date < greatest((lv ->> 'as_of')::date, (now() at time zone 'utc')::date), false);
  lc := coalesce((select cs.l_days from ripples.att_channel_stat cs where cs.channel = ch), 7);
  if sid is not null then
    q1 := ripples.rm_series_window(sid, coalesce(t.t_v, c.onset), coalesce(t.look_day, (lv ->> 'as_of')::date));
    q1 := q1 || jsonb_build_object('onset_index', 91,
               'window', jsonb_build_array(91 - (coalesce(t.t_v, c.onset) - c.onset), 91 - (coalesce(t.t_v, c.onset) - c.onset) + lc),
               'baseline', jsonb_build_object('from', c.onset - 111, 'to', c.onset - 21, 'weekday_matched', coalesce(z.same_dow, false),
                                              'year_ago_term', coalesce(z.n_obs, 0) >= 400));
  end if;
  -- channels (Q3): one tile per channel in C, agree = ž ≥ 3; hatched (no data) when the channel has no statistic
  for e in select k, v from jsonb_each(coalesce(t.s_by_channel, '{}'::jsonb)) x(k, v) order by k loop
    chans := chans || jsonb_build_object('code', e.k, 'label', ripples.rm_channel_word(e.k),
                                         'source', coalesce(e.v -> 'sources' ->> 0, ''), 'sources', coalesce(e.v -> 'sources', '[]'::jsonb),
                                         'zhat', ripples.rm_num(e.v -> 'zhat', 2), 'agree', coalesce((e.v ->> 'zhat')::float8 >= 3, false),
                                         'kappa', ripples.rm_num(e.v -> 'kappa', 2));
  end loop;
  select v into dayln from ripples.att_state where k = case when ev.reconstructed then 'engine.libday.' else 'engine.day.' end || coalesce(t.look_day, ev.as_of);
  bh := t.detail -> 'bh';
  if bh is not null and (bh ->> 'p_bh') is not null then
    select count(*) + 1 into rank from ripples.att_hop_tests t2
     where t2.look_day = t.look_day and (t2.detail -> 'bh' ->> 'm') = (bh ->> 'm') and (t2.hop_id, t2.look_no) <> (t.hop_id, t.look_no)
       and (t2.detail -> 'bh' ->> 'p_bh')::float8 / nullif((t2.detail -> 'bh' ->> 'weight')::float8, 0) < (bh ->> 'p_bh')::float8 / nullif((bh ->> 'weight')::float8, 0);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('label', x ->> 'label', 'rho', x -> 'rho') order by x ->> 'hop_id'), '[]'::jsonb) into sib
    from (select x from jsonb_array_elements(coalesce(lv -> 'flat', '[]'::jsonb)) x
           where (x ->> 'parent_hop') is not distinct from (nd ->> 'parent_hop') and (x ->> 'hop_id')::bigint <> p_hop limit 3) s(x);
  select coalesce(jsonb_object_agg(f, jsonb_build_object('n', coalesce((t.placebo -> f ->> 'n')::int, 0), 'exceed', coalesce((t.placebo -> f ->> 'exceed')::int, 0))), '{}'::jsonb)
    into plc from unnest(array['date','link','topic']) f;
  select coalesce(jsonb_agg(distinct jsonb_build_object('source', s.source, 'attribution', s.attribution, 'licence', s.license_note)), '[]'::jsonb) into lic
    from ripples.att_sources s
   where s.source = src.source
      or s.source in (select jsonb_array_elements_text(v -> 'sources') from jsonb_each(coalesce(t.s_by_channel, '{}'::jsonb)) x(k, v));
  n_of := coalesce(cardinality(c.looks), 0);
  select min(d) into nxt from unnest(c.looks) d where d > coalesce(t.look_day, ev.as_of) and d >= (now() at time zone 'utc')::date;
  best := case when ch is not null then t.s_by_channel -> ch end;
  if nd is null then  -- a stayed-flat stub opened from the fork
    nd := jsonb_build_object('tier', 'flat', 'tier_reason', flat_n ->> 'reason', 'provisional', false, 'rho', flat_n -> 'rho', 'rho_lo', null, 'rho_hi', null,
                             'lag_days', null, 'label', flat_n ->> 'label', 'domain', flat_n ->> 'domain', 'kind', null, 'p', null, 'p_1_in', null, 'f', null,
                             'f_1_in', null, 'f_warming', false, 'q', null, 'retracted', null, 'sentence', 'Stayed flat: window closed, no move.',
                             'path', ripples.rm_path_public(c.path, parent_label));
  end if;
  return jsonb_build_object('v', 2, 'hop_id', p_hop,
    'event', jsonb_build_object('event_id', ev.event_id, 'slug', ripples.rm_slug(ev.event_id), 'label', ev.label, 'emoji', lv -> 'event' ->> 'emoji',
                                'sensitive', ripples.rm_sensitive(ev.event_id), 'reconstructed', ev.reconstructed),
    'parent', jsonb_build_object('hop_id', c.parent_hop, 'label', parent_label),
    'node', jsonb_build_object('id', c.node, 'label', coalesce(nd ->> 'label', ripples.att_node_label(c.node)), 'domain', coalesce(nd ->> 'domain', ripples.rm_domain(ch)),
                               'kind', coalesce(nd ->> 'kind', (select cs.kind from ripples.att_channel_stat cs where cs.channel = ch)),
                               'geo', se.geo, 'source', src.source, 'licence', coalesce(src.license_note, src.attribution)),
    'tier', nd ->> 'tier', 'tier_reason', nd -> 'tier_reason', 'provisional', coalesce((nd ->> 'provisional')::boolean, false),
    'look', jsonb_build_object('no', t.look_no, 'of', n_of, 'final', coalesce(t.is_final, false), 'next', case when wclosed then null else nxt end,
                               'window_close', nd -> 'window_close', 'window_closed', wclosed),
    'headline', jsonb_build_object('rho', nd -> 'rho', 'rho_lo', nd -> 'rho_lo', 'rho_hi', nd -> 'rho_hi', 'lag_days', nd -> 'lag_days',
                                   'direction', case when (nd ->> 'rho') is null then null when (nd ->> 'unit') = 'points' then case when (nd ->> 'rho')::float8 < 0 then 'below' else 'above' end
                                                     when (nd ->> 'rho')::float8 < 1 then 'below' else 'above' end,
                                   'parent_label', parent_label),
    'q1_normal', q1,
    'q2_after', jsonb_build_object('parent_onset', coalesce(t.t_u, c.onset), 'node_onset', t.t_v, 'lag_days', ripples.rm_num(to_jsonb(t.lag_days), 0), 'hour_resolved', false,
                                   'order_ok', coalesce(t.lag_ok, true) and not coalesce(t.reversed, false),
                                   'pre_trend', jsonb_build_object('s', ripples.rm_num(to_jsonb(t.s_pre), 2), 'flag', coalesce(t.s_pre, 0) >= 2)),
    'q3_who', jsonb_build_object('channels', chans,
                                 'agree', (select count(*) from jsonb_array_elements(chans) x where (x ->> 'agree')::boolean),
                                 'of', jsonb_array_length(chans),
                                 'excluded', coalesce((select jsonb_agg(jsonb_build_object('code', x, 'label', ripples.rm_channel_word(x), 'why', 'it proposed the link')) from unnest(c.excluded_ch) x), '[]'::jsonb),
                                 'loso_ok', t.loso_ok, 'common_shock', coalesce(t.common_shock, false)),
    'q4_why', jsonb_build_object('path', coalesce(nd -> 'path', ripples.rm_path_public(c.path, parent_label)),
                                 'linkage', jsonb_build_object('kind', coalesce(t.linkage ->> 'kind', t.link_kind), 'measured_flow', null, 'comention', null),
                                 'replication', case when t.replication is not null and (t.replication ->> 'n') is not null then t.replication || jsonb_build_object('text',
                                     format('Seen after %s of %s past %s events.', t.replication ->> 'hits', t.replication ->> 'n',
                                            coalesce((select lower(f.label) from ripples.att_families f where f.family = t.replication ->> 'family'), t.replication ->> 'family'))) end,
                                 'route_ideas', coalesce(lv -> 'route_ideas', '[]'::jsonb),
                                 'rival_note', case when coalesce((t.attribution ->> 'share')::float8, 1) < 0.5 then
                                     'Also consistent with: ' || coalesce((select string_agg(x ->> 'label', ', ') from jsonb_array_elements(t.attribution -> 'rivals') x), 'another event') || ' (active the same week).' end),
    'q5_luck', jsonb_build_object('p', nd -> 'p', 'p_1_in', nd -> 'p_1_in', 'placebo', plc, 'p_floor', ripples.rm_num(to_jsonb(t.p_floor), 5),
                                  'f', nd -> 'f', 'f_1_in', nd -> 'f_1_in', 'f_bin', t.f_bin, 'f_warming', coalesce((nd ->> 'f_warming')::boolean, false), 'q', nd -> 'q',
                                  'bh', jsonb_build_object('m', (bh ->> 'm')::int, 'rank', rank, 'weight', ripples.rm_num(bh -> 'weight', 2)),
                                  'day', jsonb_build_object('tested', (dayln ->> 'tested')::int, 'measured', (dayln ->> 'measured')::int,
                                                            'expected_flukes', ripples.rm_num(dayln -> 'expected_flukes', 2)),
                                  'attribution', jsonb_build_object('share', ripples.rm_num(t.attribution -> 'share', 2),
                                                                    'rivals', coalesce((select jsonb_agg(jsonb_build_object('label', x ->> 'label', 'lr', ripples.rm_num(x -> 'lr', 2)))
                                                                                          from jsonb_array_elements(coalesce(t.attribution -> 'rivals', '[]'::jsonb)) x), '[]'::jsonb)),
                                  'flat_siblings', sib),
    'math', jsonb_build_object('stat_kind', t.stat_kind, 's', ripples.rm_num(best -> 'S', 3), 'rho1', null, 'sigma', ripples.rm_num(to_jsonb(z.sigma), 4),
                               'z_by_source', coalesce((select jsonb_object_agg(k, jsonb_build_object('zhat', ripples.rm_num(v -> 'zhat', 2), 'sources', v -> 'sources',
                                                         'n_series', v -> 'n_series', 'kappa', ripples.rm_num(v -> 'kappa', 2), 'S', ripples.rm_num(v -> 'S', 3), 'sd', ripples.rm_num(v -> 'sd', 3)))
                                                        from jsonb_each(coalesce(t.s_by_channel, '{}'::jsonb)) x(k, v)), '{}'::jsonb),
                               'raw_rho', ripples.rm_num(to_jsonb(t.rho_raw), 3), 'window_days', lc,
                               'weights', coalesce((select jsonb_object_agg(k, ripples.rm_num(v -> 'w', 2)) from jsonb_each(coalesce(t.s_by_channel, '{}'::jsonb)) x(k, v)), '{}'::jsonb),
                               'method', coalesce(lv ->> 'method', '6.0'),
                               'ledger', jsonb_build_object('seq', coalesce(t.ledger_seq, (lv -> 'ledger' ->> 'seq')::bigint),
                                                            'chain_hash', (select l.chain_hash from ripples.att_ledger l where l.seq = coalesce(t.ledger_seq, (lv -> 'ledger' ->> 'seq')::bigint))),
                               'csv', 'https://kffkasnzqcddpystszch.supabase.co/storage/v1/object/public/ripples/v2/hop/' || p_hop || '.csv',
                               'licences', lic, 'q', ripples.rm_num(to_jsonb(t.q_w), 4), 'p_h', ripples.rm_num(to_jsonb(t.fluke), 4),
                               'look_day', t.look_day, 'fails', coalesce(t.detail -> 'fails', '[]'::jsonb)),
    'retracted', coalesce(nd -> 'retracted', 'null'::jsonb),
    'sentence', nd ->> 'sentence',
    'sr_sentence', case when nd ->> 'tier' in ('measured','likely') and (nd ->> 'rho') is not null then
        format('%s: %s, %s %s. %s of %s sources agree. A random pairing looks this strong about 1 in %s times. Measured movement, not proof of cause.',
               nd ->> 'label', ripples.rm_mult_phrase((nd ->> 'rho')::numeric, coalesce(nd ->> 'unit', q1 ->> 'unit'), true),
               ripples.rm_lag_phrase((nd ->> 'lag_days')::float8), parent_label,
               (select count(*) from jsonb_array_elements(chans) x where (x ->> 'agree')::boolean), jsonb_array_length(chans), coalesce(nd ->> 'p_1_in', '?'))
      else nd ->> 'sentence' end);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 7. Open data (v2/data/{date}.csv, CC BY 4.0): GREEN-derived fields only, never a ticker, never Google / Y-provenance
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function ripples.rm_open_data(p_day date) returns jsonb
language sql stable security definer set search_path = '' as $$
  with lines as (select (x ->> 'event_id')::bigint event_id, (x ->> 'version')::int version
                   from ripples.rm_days d, jsonb_array_elements(d.payload -> 'shocks') x where d.day = p_day),
  v as (select v.* from ripples.rm_public_versions v join lines l using (event_id, version)),
  rows as (
    select v.event_id, v.payload -> 'event' ->> 'label' event_label, v.payload -> 'event' ->> 'family' family, (n ->> 'hop_id')::bigint hop_id,
           n ->> 'node' node, n ->> 'label' node_label, n ->> 'domain' domain, n ->> 'tier' tier, n ->> 'rho' rho, n ->> 'rho_lo' rho_lo, n ->> 'rho_hi' rho_hi,
           n ->> 'lag_days' lag_days, n ->> 'onset' onset, n ->> 'p' p, n ->> 'f' f, n ->> 'q' q, n ->> 'window_close' window_close
      from v, jsonb_array_elements(v.payload -> 'nodes') n
    union all
    select v.event_id, v.payload -> 'event' ->> 'label', v.payload -> 'event' ->> 'family', (n ->> 'hop_id')::bigint, n ->> 'node', n ->> 'label', n ->> 'domain',
           'flat', n ->> 'rho', null, null, null, null, null, null, null, null
      from v, jsonb_array_elements(coalesce(v.payload -> 'flat', '[]'::jsonb)) n),
  srcs as (  -- every source that contributes to a row: the node's own source + every source in its latest statistic
    select r.hop_id, array_agg(distinct s) ss from rows r
      cross join lateral (select split_part(r.node, ':', 1) s where r.node !~ '^Q[0-9]+$'
                          union select 'wiki.pv' where r.node ~ '^Q[0-9]+$'
                          union select jsonb_array_elements_text(e.value -> 'sources')
                            from ripples.att_hop_tests t, jsonb_each(coalesce(t.s_by_channel, '{}'::jsonb)) e
                           where t.hop_id = r.hop_id and t.look_no = (select max(look_no) from ripples.att_hop_tests t2 where t2.hop_id = r.hop_id)) x
     group by r.hop_id)
  select jsonb_build_object(
    'date', p_day, 'license', 'CC BY 4.0', 'method', '6.0',
    'citation', 'Knock-On / Ripple Map, bensunter.com/ripples, ' || p_day || ', method v6.0',
    'source', 'Derived only from GREEN sources (official or openly licensed: Wikimedia CC0, US government public domain, Indeed Hiring Lab CC BY, npm, GitHub, Hugging Face, OpenFEMA, GDELT). Rows touching any other source are omitted.',
    'columns', jsonb_build_array('date','event_id','event','family','hop_id','node','node_label','domain','tier','x_normal','x_normal_lo','x_normal_hi','lag_days','onset','p_placebo','fluke_rate','q','window_close'),
    'rows', coalesce(jsonb_agg(jsonb_build_array(p_day, r.event_id, r.event_label, r.family, r.hop_id, r.node, r.node_label, r.domain, r.tier, r.rho, r.rho_lo, r.rho_hi,
                                                 r.lag_days, r.onset, r.p, r.f, r.q, r.window_close) order by r.event_id, r.hop_id), '[]'::jsonb),
    'omitted', (select count(*) from rows r2 join srcs s2 using (hop_id)
                 where exists (select 1 from unnest(s2.ss) s where not exists (select 1 from ripples.att_sources a where a.source = s and a.grade = 'green' and a.engine_channel <> 'MONEY'))))
  from rows r join srcs s using (hop_id)
  where not exists (select 1 from unnest(s.ss) x where not exists (select 1 from ripples.att_sources a where a.source = x and a.grade = 'green' and a.engine_channel <> 'MONEY'))
$$;

-- per-hop CSV rows (the Q1 series): GREEN node sources only; otherwise a header and a note
create or replace function ripples.rm_hop_csv(p_hop bigint) returns text
language plpgsql stable security definer set search_path = '' as $$
declare h jsonb := ripples.rm_hop_evidence(p_hop); out text; q jsonb; g boolean; i int; d date;
begin
  if h is null then return null; end if;
  g := exists (select 1 from ripples.att_sources a where a.source = h -> 'node' ->> 'source' and a.grade = 'green' and a.engine_channel <> 'MONEY');
  out := '# Knock-On / Ripple Map, hop ' || p_hop || ', method v6.0, CC BY 4.0 (derived values; ' || coalesce(h -> 'node' ->> 'licence', '') || ')' || E'\n'
         || 'date,x_normal,band_lo,band_hi,same_days_last_year' || E'\n';
  q := h -> 'q1_normal';
  if not g then return out || '# series withheld: the source is not openly licensed (derived statistics are shown on the evidence card only)' || E'\n'; end if;
  if q is null or q -> 'series' is null then return out; end if;
  for i in 0 .. jsonb_array_length(q -> 'series') - 1 loop
    d := (q ->> 'from')::date + i;
    out := out || d || ',' || coalesce(q -> 'series' ->> i, '') || ',' || coalesce(q -> 'band_lo' ->> i, '') || ',' || coalesce(q -> 'band_hi' ->> i, '') || ','
           || coalesce(q -> 'last_year' ->> i, '') || E'\n';
  end loop;
  return out;
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 8. Public RPCs (anon) — ENGINE §11
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function public.rm_shocks(p_day date default null) returns jsonb
language sql stable security definer set search_path = '' as $$
  select d.payload from ripples.rm_days d
   where (p_day is null and d.day <= (now() at time zone 'utc')::date) or d.day = p_day
   order by d.day desc limit 1
$$;

create or replace function public.rm_cascade(p_event bigint, p_version int default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v jsonb; last record;
begin
  if p_event is null or not ripples.rm_is_public(p_event) then return null; end if;
  -- withheld versions (rm_version_audit) are never served, by number or as the latest
  select x.version, x.payload into last from ripples.rm_public_versions x where x.event_id = p_event order by x.version desc limit 1;
  if p_version is null or p_version = last.version then return last.payload; end if;
  select x.payload into v from ripples.rm_public_versions x where x.event_id = p_event and x.version = p_version;
  if v is null then return null; end if;
  -- an older frozen version: the frozen document plus how far the live line has grown since (EXPERIENCE §7)
  return v || jsonb_build_object('grown_to', jsonb_build_object('version', last.version,
                                   'stops_added', ripples.rm_stops(last.payload) - ripples.rm_stops(v),
                                   'url', 'https://bensunter.com/ripples/line/' || (last.payload -> 'event' ->> 'slug') || '/'));
end $$;

create or replace function public.rm_hop(p_hop bigint) returns jsonb
language sql stable security definer set search_path = '' as $$
  select ripples.rm_hop_evidence(p_hop)
$$;

create or replace function public.rm_lands(p_domain text, p_days int default 30) returns jsonb
language sql stable security definer set search_path = '' as $$
  with ok as (select p_domain d where p_domain in ('reading','chatter','markets','builders','real_world','jobs','institutions','stuff')),
  lv as (select distinct on (v.event_id) v.event_id, v.payload p from ripples.rm_public_versions v
           join ripples.att_events e on e.event_id = v.event_id and e.role in ('real','library','positive_control')
          order by v.event_id, v.version desc),
  h as (select lv.event_id, lv.p, n from lv, jsonb_array_elements(lv.p -> 'nodes') n, ok
         where n ->> 'domain' = ok.d and n ->> 'tier' in ('measured','likely')
           and (n ->> 'onset')::date >= (now() at time zone 'utc')::date - least(greatest(coalesce(p_days, 30), 1), 3650))
  select case when (select d from ok) is null then null else jsonb_build_object('v', 2, 'domain', p_domain,
    'from', (now() at time zone 'utc')::date - least(greatest(coalesce(p_days, 30), 1), 3650), 'to', (now() at time zone 'utc')::date,
    'hops', coalesce((select jsonb_agg(jsonb_build_object(
        'hop_id', (n ->> 'hop_id')::bigint, 'event_id', event_id, 'slug', p -> 'event' ->> 'slug', 'event_label', p -> 'event' ->> 'label', 'emoji', p -> 'event' ->> 'emoji',
        'node', n ->> 'node', 'label', n ->> 'label', 'domain', n ->> 'domain', 'tier', n ->> 'tier', 'provisional', (n ->> 'provisional')::boolean,
        'attention_ripple', (n ->> 'attention_ripple')::boolean, 'rho', n -> 'rho', 'rho_lo', n -> 'rho_lo', 'rho_hi', n -> 'rho_hi', 'lag_days', n -> 'lag_days',
        'unit', coalesce(n ->> 'unit', 'x'),
        'onset', n ->> 'onset', 'reconstructed', (p -> 'event' ->> 'reconstructed')::boolean, 'sensitive', (p -> 'event' ->> 'sensitive')::boolean,
        'retracted', n -> 'retracted')
      order by (n ->> 'tier') = 'measured' desc, n ->> 'onset' desc, (n ->> 'hop_id')::bigint) from (select * from h limit 200) h2), '[]'::jsonb)) end
$$;

-- p_days counts from the line's first publication (so reconstructed lines published at launch are listed); null = all
create or replace function public.rm_archive(p_days int default 90, p_status text default null) returns jsonb
language sql stable security definer set search_path = '' as $$
  with lv as (select distinct on (v.event_id) v.event_id, v.version, v.payload p,
                     (select min(v0.published_at) from ripples.rm_public_versions v0 where v0.event_id = v.event_id) first_pub
                from ripples.rm_public_versions v join ripples.att_events e on e.event_id = v.event_id and e.role in ('real','library','positive_control')
               order by v.event_id, v.version desc)
  select coalesce(jsonb_agg(jsonb_build_object(
      'event_id', event_id, 'slug', p -> 'event' ->> 'slug', 'label', p -> 'event' ->> 'label', 'emoji', p -> 'event' ->> 'emoji', 'family', p -> 'event' ->> 'family',
      'onset', p -> 'event' ->> 'onset', 'status', p ->> 'status', 'reconstructed', (p -> 'event' ->> 'reconstructed')::boolean,
      'stops', ripples.rm_stops(p),
      'watching', (select count(*) from jsonb_array_elements(p -> 'nodes') n where n ->> 'tier' = 'watching'),
      'measured', (select count(*) from jsonb_array_elements(p -> 'nodes') n where n ->> 'tier' = 'measured'),
      'domains', (select coalesce(jsonb_agg(distinct n ->> 'domain'), '[]'::jsonb) from jsonb_array_elements(p -> 'nodes') n where n ->> 'tier' in ('measured','likely')),
      'weakest_tier', p -> 'weakest_tier', 'version', version, 'sensitive', (p -> 'event' ->> 'sensitive')::boolean)
      order by p -> 'event' ->> 'onset', event_id), '[]'::jsonb)
  from lv
  where (p_days is null or first_pub >= now() - make_interval(days => least(greatest(p_days, 1), 36500)))
    and (p_status is null or p ->> 'status' = p_status)
$$;

create or replace function public.rm_week(p_week text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare w jsonb; wk daterange;
begin
  if p_week is null or p_week !~ '^[0-9]{4}-[0-9]{2}$' then return null; end if;
  wk := daterange(to_date(p_week || '-1', 'IYYY-IW-ID'), to_date(p_week || '-1', 'IYYY-IW-ID') + 7);
  if to_regclass('ripples.att_week_editions') is not null then
    execute 'select payload from ripples.att_week_editions where week = $1' into w using p_week;
  end if;
  if w is null then
    return jsonb_build_object('v', 2, 'week', p_week, 'from', lower(wk), 'to', upper(wk) - 1, 'ripple_of_week', null,
                              'rule', 'most Measured stops; ≥ 3 domains; hiddenness breaks ties', 'qualified', false,
                              'note', 'No edition for this week yet.', 'edition', null, 'published_at', null, 'lines', '[]'::jsonb);
  end if;
  -- only public lines, public slugs
  return jsonb_build_object('v', 2, 'week', p_week, 'from', coalesce(w ->> 'from', lower(wk)::text), 'to', coalesce(w ->> 'to', (upper(wk) - 1)::text),
    'ripple_of_week', case when (w -> 'ripple_of_week' -> 'event' ->> 'event_id') is not null
                            and ripples.rm_is_public((w -> 'ripple_of_week' -> 'event' ->> 'event_id')::bigint) then w -> 'ripple_of_week' end,
    'rule', coalesce(w ->> 'rule', 'most Measured stops; ≥ 3 domains; hiddenness breaks ties'), 'qualified', coalesce((w ->> 'qualified')::boolean, false),
    'note', w -> 'note', 'edition', w -> 'edition', 'published_at', w -> 'published_at',
    'lines', coalesce((select jsonb_agg(x || jsonb_build_object('slug', ripples.rm_slug((x ->> 'event_id')::bigint)))
                         from jsonb_array_elements(coalesce(w -> 'lines', '[]'::jsonb)) x where ripples.rm_is_public((x ->> 'event_id')::bigint)), '[]'::jsonb));
end $$;

create or replace function public.rm_calibration() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('v', 2, 'as_of', c.as_of, 'method', '6.0', 'decoy_fdr', null, 'null_ks', null, 'power', '[]'::jsonb, 'controls', null,
                            'receipts', null, 'refire', '[]'::jsonb, 'breaker', '[]'::jsonb, 'retractions', '[]'::jsonb, 'ledger', null, 'model_versions', '[]'::jsonb)
         || c.payload
    from ripples.att_calibration_public c order by c.as_of desc limit 1
$$;

create or replace function public.rm_health() returns jsonb
language sql stable security definer set search_path = '' as $$
  with d as (select day, published_at from ripples.rm_days order by day desc limit 1),
  lg as (select stage, at from ripples.rm_publish_log order by id desc limit 1),
  today as (select (now() at time zone 'utc')::date t)
  select jsonb_build_object('v', 2, 'latest_day', d.day, 'published_at', d.published_at,
    'stale', d.day is null or d.day < (select t from today) - 1 or (d.day < (select t from today) and (now() at time zone 'utc')::time > time '09:00'),
    'stage', coalesce(lg.stage, 'none'),
    'tests_today', (select (v ->> 'tested')::int from ripples.att_state where k = 'engine.day.' || (select t from today)),
    'breaker', coalesce((select jsonb_agg(b.cell order by b.cell) from ripples.att_breaker b where b.tripped_at is not null and b.restored_at is null), '[]'::jsonb),
    'sources_disabled', coalesce((select jsonb_agg(s.source order by s.source) from ripples.att_sources s where not s.enabled and s.tier = 'ship'), '[]'::jsonb),
    'ledger', jsonb_build_object('head', ripples.att_ledger_head(), 'seq', (select max(seq) from ripples.att_ledger),
                                 'days', (select count(distinct l.day) from ripples.att_ledger l)),
    'now', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
  from (select 1) one left join d on true left join lg on true
$$;

-- Count-only share/landing event (EXPERIENCE §9: ko.client for count-only events). Stores per day × kind × src a count and a
-- same-day unique count. The client id is hashed with a daily salt that is deleted with the day; no IP, no page, no user agent.
create or replace function public.rm_event(p_kind text, p_src text, p_client text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare d date := (now() at time zone 'utc')::date; ch text; fresh int := 0; salt text;
begin
  if p_kind is null or p_kind not in ('share_tap','landing') then return jsonb_build_object('ok', false, 'error', 'kind'); end if;
  if p_src is null or p_src !~ '^[a-z0-9_-]{1,24}$' then p_src := 'other'; end if;
  if p_client is null or p_client !~ '^[A-Za-z0-9_-]{8,64}$' then return jsonb_build_object('ok', false, 'error', 'client'); end if;
  -- global daily cap (abuse bound for a public write): 50,000 events a day across all kinds
  if (select coalesce(sum(n), 0) from ripples.rm_event_counts where day = d) >= 50000 then return jsonb_build_object('ok', true, 'capped', true); end if;
  salt := ripples._salt(d);
  ch := encode(extensions.digest(salt || '|rm|' || p_client, 'sha256'), 'hex');
  insert into ripples.rm_event_seen(day, kind, client_hash) values (d, p_kind, ch) on conflict do nothing;
  get diagnostics fresh = row_count;
  insert into ripples.rm_event_counts(day, kind, src, n, uniq) values (d, p_kind, p_src, 1, case when fresh > 0 then 1 else 0 end)
  on conflict (day, kind, src) do update set n = ripples.rm_event_counts.n + 1, uniq = ripples.rm_event_counts.uniq + case when fresh > 0 then 1 else 0 end;
  delete from ripples.rm_event_seen where day < d - 1;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 9. Service RPCs for ripples-publish / ripples-og (service_role only)
-- ---------------------------------------------------------------------------------------------------------------------
-- The publish bundle: freezes (att_publish_cascades) and returns everything the Storage mirror writes. JSON documents are
-- returned as text (jsonb::text) so re-publishing writes byte-identical files.
create or replace function public.rm_publish_bundle_v2(p_as_of date default null, p_events bigint[] default null, p_full boolean default false) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare d date := coalesce(p_as_of, (now() at time zone 'utc')::date); fr jsonb; touched bigint[]; newev bigint[]; casc jsonb; hops jsonb; lands jsonb := '{}'::jsonb;
        dom text; wk text := to_char(d, 'IYYY-IW'); feed jsonb; withdraw jsonb; n_grants int; hop_ids bigint[]; hop_cap int := 400; n_hops_all int;
begin
  n_grants := ripples.rm_enforce_grants();   -- re-revoke anything rm_grant_audit lists (e.g. an older SQL file re-applied)
  fr := ripples.att_publish_cascades(d, p_events);
  select coalesce(array_agg(distinct (x ->> 'event_id')::bigint), '{}') into newev from jsonb_array_elements(fr -> 'lines') x where (x ->> 'unchanged') = 'false';
  -- lines whose files are (re)written: new versions, running lines, lines with a frozen file missing from Storage (a failed or
  -- interrupted upload is retried on every run until it lands), lines with a version withheld in the last two days, or all with p_full
  with lat as (select distinct on (v.event_id) v.event_id, v.version, v.payload from ripples.rm_public_versions v
                 join ripples.att_events e on e.event_id = v.event_id and e.role in ('real','library','positive_control')
                order by v.event_id, v.version desc)
  select coalesce(array_agg(lat.event_id order by lat.event_id), '{}') into touched from lat
   where p_full or lat.event_id = any (newev) or lat.payload ->> 'status' = 'running'
      or not exists (select 1 from storage.objects o where o.bucket_id = 'ripples' and o.name = 'v2/cascade/' || lat.event_id || '.json')
      or exists (select 1 from ripples.rm_public_versions v where v.event_id = lat.event_id
                    and not exists (select 1 from storage.objects o where o.bucket_id = 'ripples' and o.name = 'v2/cascade/' || v.event_id || '/v' || v.version || '.json'))
      or exists (select 1 from ripples.rm_version_audit a where a.event_id = lat.event_id and a.withheld and a.checked_at > now() - interval '2 days');
  select coalesce(jsonb_agg(jsonb_build_object(
           'event_id', t.id, 'latest', public.rm_cascade(t.id, null)::text,
           'versions', (select jsonb_agg(jsonb_build_object('version', v.version, 'published_at', v.published_at,
                                                            'stops', ripples.rm_stops(v.payload), 'status', v.payload ->> 'status',
                                                            'measured', (v.payload -> 'denominators' ->> 'measured')::int,
                                                            'new', v.event_id = any (newev) and v.version = (select max(v3.version) from ripples.att_cascade_versions v3 where v3.event_id = v.event_id),
                                                            'text', case when p_full or (v.event_id = any (newev) and v.version = (select max(v3.version) from ripples.att_cascade_versions v3 where v3.event_id = v.event_id))
                                                                           or not exists (select 1 from storage.objects o where o.bucket_id = 'ripples'
                                                                                            and o.name = 'v2/cascade/' || v.event_id || '/v' || v.version || '.json')
                                                                         then v.payload::text end)
                                           order by v.version)
                          from ripples.rm_public_versions v where v.event_id = t.id),
           -- calendars only for windows that are still open (a closed window is never re-announced)
           'watching', (select coalesce(jsonb_agg(jsonb_build_object('hop_id', n -> 'hop_id', 'label', n ->> 'label', 'window_close', n ->> 'window_close', 'due', n ->> 'due')), '[]'::jsonb)
                          from jsonb_array_elements((select v.payload from ripples.rm_public_versions v where v.event_id = t.id order by v.version desc limit 1) -> 'nodes') n
                         where (n ->> 'tier' = 'watching' or coalesce((n ->> 'provisional')::boolean, false)) and (n ->> 'window_close')::date >= d
                           and not coalesce((n ->> 'window_closed')::boolean, false))) order by t.id), '[]'::jsonb)
    into casc from unnest(touched) t(id);
  -- HopEvidence mirror: at most hop_cap hops per run; hops of lines with a new version first, then the least recently mirrored
  with lat as (select distinct on (v.event_id) v.event_id, v.payload from ripples.rm_public_versions v where v.event_id = any (touched) order by v.event_id, v.version desc),
  h as (select distinct lat.event_id, (n ->> 'hop_id')::bigint id from lat, jsonb_array_elements(lat.payload -> 'nodes') n
        union
        select distinct lat.event_id, (n ->> 'hop_id')::bigint from lat, jsonb_array_elements(coalesce(lat.payload -> 'flat', '[]'::jsonb)) n),
  hh as (select h.id, bool_or(h.event_id = any (newev)) is_new, min(m.mirrored_at) at
           from h left join ripples.rm_hop_mirrored m on m.hop_id = h.id group by h.id)
  select count(*)::int, (select array_agg(x.id order by x.id) from (select hh2.id from hh hh2 order by (p_full or hh2.is_new) desc, hh2.at nulls first, hh2.id limit hop_cap) x)
    into n_hops_all, hop_ids from hh;
  select coalesce(jsonb_agg(jsonb_build_object('hop_id', h.id, 'json', ripples.rm_hop_evidence(h.id)::text, 'csv', ripples.rm_hop_csv(h.id)) order by h.id), '[]'::jsonb)
    into hops from unnest(coalesce(hop_ids, '{}')) h(id);
  insert into ripples.rm_hop_mirrored(hop_id, mirrored_at) select h.id, now() from unnest(coalesce(hop_ids, '{}')) h(id)
  on conflict (hop_id) do update set mirrored_at = excluded.mirrored_at;
  foreach dom in array array['reading','chatter','markets','builders','real_world','jobs','institutions','stuff'] loop
    lands := lands || jsonb_build_object(dom, public.rm_lands(dom, 30)::text);
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('event_id', v.event_id, 'version', v.version, 'label', v.payload -> 'event' ->> 'label', 'emoji', v.payload -> 'event' ->> 'emoji',
                                               'slug', v.payload -> 'event' ->> 'slug', 'published_at', v.published_at, 'stops', ripples.rm_stops(v.payload),
                                               'status', v.payload ->> 'status', 'reconstructed', (v.payload -> 'event' ->> 'reconstructed')::boolean,
                                               'text', v.payload ->> 'text_plain') order by v.published_at desc, v.event_id), '[]'::jsonb)
    into feed from (select * from ripples.rm_public_versions order by published_at desc limit 50) v;
  -- Storage objects that must not stay public: withheld versions (JSON + card), lines with no public version, hops that are no
  -- longer on a public line, calendars of windows that have closed, feeds of lines with no public version
  with lat as (select distinct on (v.event_id) v.event_id, v.payload from ripples.rm_public_versions v
                 join ripples.att_events e on e.event_id = v.event_id and e.role in ('real','library','positive_control')
                order by v.event_id, v.version desc),
  ph as (select (n ->> 'hop_id')::bigint id from lat, jsonb_array_elements(lat.payload -> 'nodes') n
         union select (n ->> 'hop_id')::bigint from lat, jsonb_array_elements(coalesce(lat.payload -> 'flat', '[]'::jsonb)) n),
  ow as (select lat.event_id, (n ->> 'hop_id')::bigint id from lat, jsonb_array_elements(lat.payload -> 'nodes') n
          where (n ->> 'tier' = 'watching' or coalesce((n ->> 'provisional')::boolean, false)) and (n ->> 'window_close')::date >= d
            and not coalesce((n ->> 'window_closed')::boolean, false)),
  wv as (select a.event_id, a.version from ripples.rm_version_audit a where a.withheld),
  o as (select o.name, substring(o.name from '^v2/[a-z]+/(?:line-|hop-|stop-)?([0-9]+)')::bigint id1 from storage.objects o
         where o.bucket_id = 'ripples' and o.name ~ '^v2/(cascade|feed|hop|og|ics)/')
  select coalesce(jsonb_agg(o.name order by o.name), '[]'::jsonb) into withdraw from (
    select o.name from o
     where (o.name ~ '^v2/cascade/[0-9]+/v[0-9]+\.json$' and exists (select 1 from wv where o.name = 'v2/cascade/' || wv.event_id || '/v' || wv.version || '.json'))
        or (o.name ~ '^v2/og/line-[0-9]+-v[0-9]+\.png$' and exists (select 1 from wv where o.name = 'v2/og/line-' || wv.event_id || '-v' || wv.version || '.png'))
        or (o.name ~ '^v2/cascade/[0-9]+\.json$' and o.id1 not in (select lat.event_id from lat))
        or (o.name ~ '^v2/feed/line-[0-9]+\.xml$' and o.id1 not in (select lat.event_id from lat))
        or (o.name ~ '^v2/hop/[0-9]+\.(json|csv)$' and o.id1 not in (select ph.id from ph))
        or (o.name ~ '^v2/og/stop-[0-9]+\.png$' and o.id1 not in (select ph.id from ph))
        or (o.name ~ '^v2/ics/hop-[0-9]+\.ics$' and o.id1 not in (select ow.id from ow))
        or (o.name ~ '^v2/ics/line-[0-9]+\.ics$' and o.id1 not in (select ow.event_id from ow))
     limit 2000) o;
  return jsonb_build_object('as_of', d, 'freeze', fr - 'lines', 'lines_frozen', jsonb_array_length(fr -> 'lines'),
    'held', (select coalesce(jsonb_agg(jsonb_build_object('event_id', x -> 'event_id', 'held', x -> 'held')), '[]'::jsonb) from jsonb_array_elements(fr -> 'lines') x where x ? 'held'),
    'grants_fixed', n_grants,
    'shocks', (select payload::text from ripples.rm_days where day = d), 'shocks_day', d,
    'cascades', casc, 'hops', hops, 'hops_deferred', greatest(coalesce(n_hops_all, 0) - coalesce(cardinality(hop_ids), 0), 0), 'lands', lands,
    'archive', public.rm_archive(null, null)::text, 'calibration', public.rm_calibration()::text,
    'week', jsonb_build_object('week', wk, 'text', public.rm_week(wk)::text), 'health', public.rm_health()::text,
    'feed', feed, 'open_data', ripples.rm_open_data(d), 'withdraw', withdraw,
    'shock_card', (select jsonb_build_object('event_id', x -> 'event_id', 'version', x -> 'version') from ripples.rm_days r, jsonb_array_elements(r.payload -> 'shocks') with ordinality y(x, o)
                    where r.day = d and not (x ->> 'sensitive')::boolean order by o limit 1) );
end $$;

create or replace function public.rm_publish_log(p_as_of date, p_stage text, p_result jsonb) returns bigint
language sql volatile security definer set search_path = '' as $$
  insert into ripples.rm_publish_log(as_of, stage, result) values (p_as_of, p_stage, coalesce(p_result, '{}'::jsonb)) returning id
$$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 10. Contract test: every RPC's live output vs the fixture shapes (keys and JSON types; null matches anything) + coverage + synthetic line
-- ---------------------------------------------------------------------------------------------------------------------
drop function if exists ripples.rm_shape_diff(jsonb, jsonb, text, text[]);
-- p_maps: object paths with data-dependent keys (each value is compared with the fixture's first value);
-- p_opt: key names that are optional annotations (may be missing or extra anywhere)
create or replace function ripples.rm_shape_diff(p_exp jsonb, p_act jsonb, p_path text default '$', p_maps text[] default '{}', p_opt text[] default '{}') returns setof text
language plpgsql stable set search_path = '' as $$
declare k text; te text := jsonb_typeof(p_exp); ta text := jsonb_typeof(p_act); x jsonb; i int := 0;
begin
  if p_exp is null or p_act is null or te = 'null' or ta = 'null' then return; end if;
  if te <> ta then return next p_path || ': type ' || ta || ' (fixture ' || te || ')'; return; end if;
  if te = 'object' then
    if p_path = any (p_maps) then
      for x in select value from jsonb_each(p_act) limit 3 loop
        return query select * from ripples.rm_shape_diff((select value from jsonb_each(p_exp) limit 1), x, p_path || '.*', p_maps, p_opt);
      end loop;
      return;
    end if;
    for k in select jsonb_object_keys(p_exp) loop
      if not (p_act ? k) and k <> all (p_opt) then return next p_path || '.' || k || ': missing'; end if;
    end loop;
    for k in select jsonb_object_keys(p_act) loop
      if not (p_exp ? k) and k <> all (p_opt) then return next p_path || '.' || k || ': extra'; end if;
    end loop;
    for k in select jsonb_object_keys(p_exp) loop
      if p_act ? k then return query select * from ripples.rm_shape_diff(p_exp -> k, p_act -> k, p_path || '.' || k, p_maps, p_opt); end if;
    end loop;
  elsif te = 'array' then
    if jsonb_array_length(p_exp) = 0 then return; end if;
    for x in select value from jsonb_array_elements(p_act) loop
      i := i + 1; exit when i > 5;
      return query select * from ripples.rm_shape_diff(p_exp -> 0, x, p_path || '[]', p_maps, p_opt);
    end loop;
  end if;
end $$;

-- Coverage of a shape check: every fixture leaf that the live output actually filled ('compared') or left null / empty
-- ('vacuous'). rm_shape_diff treats null as a wildcard, so a diff-free result on thin data proves little; the vacuous list says
-- exactly which fields went unchecked. Arrays: a path counts as compared if any of the first 25 live elements fills it.
create or replace function ripples.rm_shape_cover(p_exp jsonb, p_act jsonb, p_path text default '$', p_maps text[] default '{}') returns table(path text, state text)
language plpgsql stable set search_path = '' as $$
declare k text; te text := jsonb_typeof(p_exp); ta text := jsonb_typeof(p_act); x jsonb;
begin
  if p_exp is null or te = 'null' then return; end if;
  if p_act is null or ta = 'null' then path := p_path; state := 'vacuous'; return next; return; end if;
  if te <> ta then return; end if;                                   -- a type mismatch is rm_shape_diff's to report
  if te = 'object' then
    if p_path = any (p_maps) then
      if not exists (select 1 from jsonb_each(p_act)) then path := p_path; state := 'vacuous'; return next; return; end if;
      for x in select value from jsonb_each(p_act) limit 1 loop
        return query select * from ripples.rm_shape_cover((select value from jsonb_each(p_exp) limit 1), x, p_path || '.*', p_maps);
      end loop;
      return;
    end if;
    for k in select jsonb_object_keys(p_exp) loop
      if p_act ? k then return query select * from ripples.rm_shape_cover(p_exp -> k, p_act -> k, p_path || '.' || k, p_maps); end if;
    end loop;
  elsif te = 'array' then
    if jsonb_array_length(p_exp) = 0 then return; end if;
    if jsonb_array_length(p_act) = 0 then path := p_path || '[]'; state := 'vacuous'; return next; return; end if;
    return query select q.path, case when bool_or(q.state = 'compared') then 'compared' else 'vacuous' end
                   from (select c.path, c.state
                           from (select a.value from jsonb_array_elements(p_act) with ordinality a(value, i) where a.i <= 25) a2,
                                lateral ripples.rm_shape_cover(p_exp -> 0, a2.value, p_path || '[]', p_maps) c) q
                  group by q.path;
  else
    path := p_path; state := 'compared'; return next;
  end if;
end $$;

-- The contract test. Part 1 diffs every RPC's live output against its fixture and reports how much of each fixture the live
-- data actually exercised. Part 2 builds a synthetic line from the cascade fixture inside a rolled-back block (Measured, Likely,
-- retracted, provisional depth-2, flat stubs, a rate-unit Measured stop, a closed-window Watching stop, an open one, and an
-- unnamed QID stop with a child) and checks the CascadePayload shape strictly plus the wording rules. Service-only; volatile
-- because part 2 writes and then rolls back (nothing persists, no ledger row, no sequence is used).
drop function if exists ripples.rm_contract_test();
create or replace function ripples.rm_contract_test() returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare r jsonb := '[]'::jsonb; ev bigint; ev_old bigint; hop bigint; wk text; d date; diffs jsonb; fname text; act jsonb; fx jsonb; cov jsonb;
        maps text[] := array['$.math.z_by_source', '$.math.weights', '$.q5_luck.placebo', '$.ripple_of_week.math.z_by_source'];
        -- keys added after 2026-09-26: absent from versions frozen earlier (and from week editions that embed them)
        later text[] := array['window_closed', 'held_back', 'window_close', 'biggest_basis', 'biggest_window_days', 'listed_lines_sum'];
        syn_id bigint := 8999999999999001; syn jsonb; sc jsonb; syn_err text; syn_diffs jsonb; syn_cov jsonb; asserts jsonb := '[]'::jsonb; base jsonb; n0 jsonb;
        t date := (now() at time zone 'utc')::date; nd jsonb; sold jsonb; sold_diffs jsonb; sold_withheld jsonb;
        live_leaks jsonb; live_hop_leaks jsonb; live_past_due int;
begin
  select day into d from ripples.rm_days order by day desc limit 1;
  select v.event_id into ev from ripples.rm_public_versions v join ripples.att_events e using (event_id)
   order by (select count(*) from jsonb_array_elements(v.payload -> 'nodes') n where n ->> 'tier' in ('measured','likely','retracted')) desc, v.version desc limit 1;
  select v.event_id into ev_old from ripples.rm_public_versions v
   where exists (select 1 from ripples.rm_public_versions v2 where v2.event_id = v.event_id and v2.version > v.version) limit 1;
  select (n ->> 'hop_id')::bigint into hop from ripples.rm_public_versions v, jsonb_array_elements(v.payload -> 'nodes') n
   where v.event_id = ev and v.version = (select max(v2.version) from ripples.rm_public_versions v2 where v2.event_id = ev)
   order by n ->> 'tier' in ('measured','likely','retracted') desc, (n ->> 'tier') = 'measured' desc limit 1;
  select week into wk from ripples.att_week_editions order by week desc limit 1;
  for fname, act in
    select 'shocks.json', public.rm_shocks(d)
    union all select 'cascade-1201.json', public.rm_cascade(ev, null)
    union all select 'cascade-1201-v2.json', case when ev_old is not null then public.rm_cascade(ev_old, (select min(v.version) from ripples.rm_public_versions v where v.event_id = ev_old)) end
    union all select 'hop-9001.json', public.rm_hop(hop)
    union all select 'calibration.json', public.rm_calibration()
    union all select 'lands-real_world.json', public.rm_lands('real_world', 3650)
    union all select 'archive.json', public.rm_archive(null, null)
    union all select 'week-2026-39.json', public.rm_week(coalesce(wk, to_char(now(), 'IYYY-IW')))
    union all select 'health.json', public.rm_health()
  loop
    select f.payload into fx from ripples.rm_contract_fixtures f where f.name = fname;
    if fname = 'calibration.json' then fx := fx - 'archive'; act := act - 'archive'; end if;   -- the archive section is WS-E's (att_archive_calibration)
    select coalesce(jsonb_agg(x), '[]'::jsonb) into diffs
      from ripples.rm_shape_diff(fx, act, '$', maps, case when fname in ('cascade-1201-v2.json', 'week-2026-39.json', 'shocks.json') then array['restored'] || later else array['restored'] end) x;
    select jsonb_build_object('compared', count(*) filter (where c.state = 'compared'), 'vacuous', count(*) filter (where c.state = 'vacuous'),
                              'vacuous_sample', coalesce((jsonb_agg(c.path order by c.path) filter (where c.state = 'vacuous')) -> 0, 'null'::jsonb),
                              'vacuous_paths', coalesce(jsonb_agg(c.path order by c.path) filter (where c.state = 'vacuous'), '[]'::jsonb))
      into cov from ripples.rm_shape_cover(fx, act, '$', maps) c;
    -- no older public version on live data yet (a fresh line, or older versions withheld): not a contract failure; part 2 covers it
    r := r || jsonb_build_object('fixture', fname, 'has_fixture', fx is not null, 'has_output', act is not null and jsonb_typeof(act) <> 'null', 'diffs', diffs,
                                 'skipped', case when fname = 'cascade-1201-v2.json' and ev_old is null then 'no older public version on live data; see synthetic.older_version' end,
                                 'coverage', jsonb_build_object('compared', cov -> 'compared', 'vacuous', cov -> 'vacuous',
                                                                'vacuous_paths', (select coalesce(jsonb_agg(p), '[]'::jsonb) from (select p from jsonb_array_elements(cov -> 'vacuous_paths') p limit 12) z)));
  end loop;

  -- ---- part 1b: every public version and every public stop's evidence, through the (full) leak guard ----
  select coalesce(jsonb_agg(jsonb_build_object('event_id', v.event_id, 'version', v.version, 'leaks', to_jsonb(l.x[1:3]))), '[]'::jsonb) into live_leaks
    from ripples.rm_public_versions v, lateral (select ripples.rm_label_leaks(v.payload) x) l where cardinality(l.x) > 0;
  select coalesce(jsonb_agg(jsonb_build_object('hop', h.hop, 'leaks', to_jsonb(l.x[1:3]))), '[]'::jsonb) into live_hop_leaks
    from (select distinct (n ->> 'hop_id')::bigint hop from ripples.rm_public_versions v,
            jsonb_array_elements(coalesce(v.payload -> 'nodes', '[]'::jsonb) || coalesce(v.payload -> 'flat', '[]'::jsonb)) n
           where v.version = (select max(v2.version) from ripples.rm_public_versions v2 where v2.event_id = v.event_id)) h,
         lateral (select ripples.rm_label_leaks(ripples.rm_hop_evidence(h.hop)) x) l where cardinality(l.x) > 0;
  select count(*) into live_past_due from ripples.rm_public_versions v, jsonb_array_elements(v.payload -> 'nodes') n
   where v.version = (select max(v2.version) from ripples.rm_public_versions v2 where v2.event_id = v.event_id)
     and (n ->> 'due')::date < (v.payload ->> 'published_at')::date;

  -- ---- part 2: synthetic line, rolled back ----
  select f.payload into base from ripples.rm_contract_fixtures f where f.name = 'cascade-1201.json';
  n0 := base -> 'nodes' -> 0;
  syn := jsonb_build_object('as_of', t, 'status', 'running', 'method', '6.0', 'event', base -> 'event', 'denominators', base -> 'denominators',
           'weakest_tier', base -> 'weakest_tier', 'depth', base -> 'depth', 'flat', base -> 'flat', 'route_ideas', base -> 'route_ideas',
           'control', base -> 'control', 'rivals', base -> 'rivals',
           'nodes', (base -> 'nodes')
             || jsonb_build_array(
                  n0 || jsonb_build_object('hop_id', 99001, 'node', 'syn:rate', 'label', 'Synthetic rate series', 'unit', 'points', 'rho', 0.4, 'rho_lo', 0.2, 'rho_hi', 0.6),
                  n0 || jsonb_build_object('hop_id', 99002, 'node', 'syn:closed', 'label', 'Synthetic closed window', 'tier', 'watching', 'tier_reason', 'waiting_series',
                                           'window_close', t - 3, 'due', t + 2, 'p_hat', 0.2, 'rho', null),
                  n0 || jsonb_build_object('hop_id', 99003, 'node', 'syn:open', 'label', 'Synthetic open window', 'tier', 'watching', 'tier_reason', null,
                                           'window_close', t + 5, 'due', t + 5, 'p_hat', 0.2, 'rho', null),
                  n0 || jsonb_build_object('hop_id', 99004, 'node', 'Q999999999999', 'label', 'Q999999999999', 'tier', 'watching', 'window_close', t + 5, 'rho', null),
                  n0 || jsonb_build_object('hop_id', 99005, 'node', 'syn:child', 'label', 'Synthetic child', 'tier', 'watching', 'depth', 2, 'parent_hop', 99004,
                                           'window_close', t + 5, 'rho', null),
                  -- a source-local node whose only label is its own key (the 2026-09-26 verification: 'poly.mkt:e:1061358' → 'e:1061358')
                  n0 || jsonb_build_object('hop_id', 99006, 'node', 'syn.src:e:12345', 'label', 'e:12345', 'tier', 'watching', 'window_close', t + 5, 'rho', null),
                  -- a source-local node with a curated public name
                  n0 || jsonb_build_object('hop_id', 99007, 'node', 'fred:DGS10', 'label', 'DGS10', 'tier', 'watching', 'window_close', t + 5, 'rho', null),
                  -- an open window whose due date has already passed (WS-B's payload lagging the day)
                  n0 || jsonb_build_object('hop_id', 99008, 'node', 'syn:due', 'label', 'Synthetic late look', 'tier', 'watching', 'window_close', t + 5,
                                           'due', t - 1, 'rho', null)));
  begin
    insert into ripples.att_events(event_id, as_of, label, family, role, onset, sensitive, reconstructed, status)
    values (syn_id, t, 'Synthetic contract line', coalesce(base -> 'event' ->> 'family', 'hazard.storm'), 'real', t - 5, false, false, 'running');
    insert into ripples.att_cascades(event_id, payload, denominators) values (syn_id, syn, syn -> 'denominators');
    sc := ripples.rm_cascade_content(syn_id, t);
    sc := (sc - '_label_hold') || ripples.rm_share_text(sc, 3)
          || jsonb_build_object('version', 3, 'published_at', '2026-01-01T00:00:00Z', 'payload_hash', 'synthetic', 'grown_since', jsonb_build_object('version', 2, 'stops_added', 1),
                                'grown_to', null, 'ledger', jsonb_build_object('seq', 1, 'chain_hash', 'synthetic'));
    -- older-version path: v1 withheld, v2 public, v3 latest; rm_cascade(e, 2) must add grown_to, rm_cascade(e, 1) must be null
    insert into ripples.att_cascade_versions(event_id, version, payload, payload_hash)
    values (syn_id, 1, sc || '{"version": 1}'::jsonb, 'syn1'), (syn_id, 2, sc || '{"version": 2}'::jsonb, 'syn2'), (syn_id, 3, sc, 'syn3');
    insert into ripples.rm_version_audit(event_id, version, leaks, sample, withheld, reason) values (syn_id, 1, 1, '{Q1}', true, 'synthetic');
    sold := public.rm_cascade(syn_id, 2);
    sold_withheld := to_jsonb(public.rm_cascade(syn_id, 1) is null);
    raise exception using errcode = 'P0001', message = 'rm_contract_test rollback';
  exception when others then
    if sqlerrm <> 'rm_contract_test rollback' then syn_err := sqlerrm; end if;
  end;
  if sc is not null then
    select coalesce(jsonb_agg(x), '[]'::jsonb) into syn_diffs from ripples.rm_shape_diff(base, sc, '$', maps, '{}') x;
    select jsonb_build_object('compared', count(*) filter (where c.state = 'compared'), 'vacuous', count(*) filter (where c.state = 'vacuous'),
                              'vacuous_paths', coalesce(jsonb_agg(c.path order by c.path) filter (where c.state = 'vacuous'), '[]'::jsonb))
      into syn_cov from ripples.rm_shape_cover(base, sc, '$', maps) c;
    select x into nd from jsonb_array_elements(sc -> 'nodes') x where (x ->> 'hop_id')::int = 99001;
    asserts := asserts || jsonb_build_object('check', 'rate stop reads in points, never as a multiple', 'ok', nd ->> 'sentence' like '%0.40 points above its normal%' and nd ->> 'sentence' not like '%×%', 'got', nd ->> 'sentence');
    select x into nd from jsonb_array_elements(sc -> 'nodes') x where (x ->> 'hop_id')::int = 99002;
    asserts := asserts || jsonb_build_object('check', 'closed Watching window reads in the past tense and is not due', 'ok',
                 (nd ->> 'window_closed')::boolean and nd ->> 'sentence' like '%window closed%' and nd ->> 'sentence' not like '%closes%'
                 and nd ->> 'sentence' not like '%We expect%' and (nd ->> 'due') is null, 'got', nd ->> 'sentence');
    select x into nd from jsonb_array_elements(sc -> 'nodes') x where (x ->> 'hop_id')::int = 99003;
    asserts := asserts || jsonb_build_object('check', 'open Watching window keeps the ENGINE §8 template', 'ok',
                 not (nd ->> 'window_closed')::boolean and nd ->> 'sentence' like '%Window closes%' and nd ->> 'sentence' like '%We expect a move by then%', 'got', nd ->> 'sentence');
    asserts := asserts || jsonb_build_object('check', 'an unnamed QID stop and its child, and a source key with no name, are held back, not shown', 'ok',
                 (sc -> 'held_back' ->> 'stops')::int = 3 and not exists (select 1 from jsonb_array_elements(sc -> 'nodes') x where (x ->> 'hop_id')::int in (99004, 99005, 99006)),
                 'got', sc -> 'held_back');
    select x into nd from jsonb_array_elements(sc -> 'nodes') x where (x ->> 'hop_id')::int = 99007;
    asserts := asserts || jsonb_build_object('check', 'a source key with a curated name is shown under that name, never the key', 'ok',
                 nd ->> 'label' = '10-year Treasury yield' and not exists (select 1 from jsonb_array_elements(sc -> 'nodes') x, jsonb_array_elements(x -> 'path') pth
                                                                         where pth ->> 'text' like '%→ DGS10%'), 'got', nd ->> 'label');
    select x into nd from jsonb_array_elements(sc -> 'nodes') x where (x ->> 'hop_id')::int = 99008;
    asserts := asserts || jsonb_build_object('check', 'no published due date is in the past', 'ok',
                 nd is not null and not exists (select 1 from jsonb_array_elements(sc -> 'nodes') x where (x ->> 'due')::date < t), 'got', nd -> 'due');
    asserts := asserts || jsonb_build_object('check', 'the leak guard catches source keys (label, arrow path, sentence) and passes names', 'ok',
                 ripples.rm_label_leaks('{"nodes":[{"node":"poly.mkt:e:1061358","label":"e:1061358","path":[{"text":"Xi Jinping → e:1061358"}],"sentence":"e:1061358 ran 2.00× its normal"},{"node":"fred:DGS10","label":"DGS10"},{"node":"iem.warn:__total__","label":"Storm → __total__"}]}'::jsonb)
                   = array['DGS10', 'Storm → __total__', 'Xi Jinping → e:1061358', 'e:1061358', 'e:1061358 ran 2.00× its normal']
                 and cardinality(ripples.rm_label_leaks('{"nodes":[{"node":"fred:DGS10","label":"10-year Treasury yield","path":[{"text":"Oil → 10-year Treasury yield","source":"mechanism library v6.0"}],"sentence":"The mechanism exists (mechanism library v6.0); no measurable move yet. Window closes 2026-10-05."},{"node":"npm.dl:openai","label":"npm downloads of openai"}]}'::jsonb)) = 0,
                 'got', to_jsonb(ripples.rm_label_leaks('{"nodes":[{"node":"poly.mkt:e:1061358","label":"e:1061358","path":[{"text":"Xi Jinping → e:1061358"}],"sentence":"e:1061358 ran 2.00× its normal"},{"node":"fred:DGS10","label":"DGS10"},{"node":"iem.warn:__total__","label":"Storm → __total__"}]}'::jsonb)));
    asserts := asserts || jsonb_build_object('check', 'no raw identifier anywhere in public text', 'ok', cardinality(ripples.rm_label_leaks(sc)) = 0, 'got', to_jsonb(ripples.rm_label_leaks(sc)));
    select x into nd from jsonb_array_elements(sc -> 'nodes') x where x ->> 'tier' = 'measured' and (x ->> 'hop_id')::int <> 99001 limit 1;
    asserts := asserts || jsonb_build_object('check', 'Measured sentence carries both fluke labels and the footer', 'ok',
                 nd ->> 'sentence' like '%A random pairing looks this strong about 1 in%' and nd ->> 'sentence' like '%turn out to be flukes about 1 in%'
                 and nd ->> 'sentence' like '%Measured movement, not proof of cause.%' and nd ->> 'sentence' not similar to '%(caused|drove|because of)%', 'got', nd ->> 'sentence');
    select coalesce(jsonb_agg(x), '[]'::jsonb) into sold_diffs
      from ripples.rm_shape_diff((select f.payload from ripples.rm_contract_fixtures f where f.name = 'cascade-1201-v2.json'), sold, '$', maps, '{}') x;
    asserts := asserts || jsonb_build_object('check', 'an older public version matches cascade-1201-v2.json and carries grown_to', 'ok',
                 sold is not null and jsonb_array_length(sold_diffs) = 0 and (sold -> 'grown_to' ->> 'version')::int = 3, 'got', sold_diffs);
    asserts := asserts || jsonb_build_object('check', 'a withheld version is never served', 'ok', coalesce(sold_withheld = 'true'::jsonb, false), 'got', sold_withheld);
    asserts := asserts || jsonb_build_object('check', 'the rolled-back rows are gone', 'ok',
                 not exists (select 1 from ripples.att_events where event_id = syn_id) and not exists (select 1 from ripples.att_cascades where event_id = syn_id)
                 and not exists (select 1 from ripples.att_cascade_versions where event_id = syn_id) and not exists (select 1 from ripples.rm_version_audit where event_id = syn_id), 'got', null);
  end if;
  return jsonb_build_object('day', d, 'event', ev, 'event_old', ev_old, 'hop', hop, 'week', wk, 'results', r,
                            'live_ok', not exists (select 1 from jsonb_array_elements(r) x where jsonb_array_length(x -> 'diffs') > 0 or (not (x ->> 'has_output')::boolean and x ->> 'skipped' is null)),
                            'live_vacuous', (select sum((x -> 'coverage' ->> 'vacuous')::int) from jsonb_array_elements(r) x),
                            'live_leaks', jsonb_build_object('versions', live_leaks, 'hops', live_hop_leaks, 'past_due_at_publish', live_past_due),
                            'synthetic', jsonb_build_object('error', syn_err, 'diffs', coalesce(syn_diffs, '[]'::jsonb), 'coverage', syn_cov, 'asserts', asserts),
                            'ok', not exists (select 1 from jsonb_array_elements(r) x where jsonb_array_length(x -> 'diffs') > 0 or (not (x ->> 'has_output')::boolean and x ->> 'skipped' is null))
                                  and syn_err is null and sc is not null and jsonb_array_length(coalesce(syn_diffs, '[]'::jsonb)) = 0
                                  and jsonb_array_length(live_leaks) = 0 and jsonb_array_length(live_hop_leaks) = 0 and live_past_due = 0
                                  and not exists (select 1 from jsonb_array_elements(asserts) a where not (a ->> 'ok')::boolean));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 11. Grants (revoke-then-grant; this project's default privileges grant EXECUTE on new public functions to anon directly)
-- ---------------------------------------------------------------------------------------------------------------------
revoke execute on all functions in schema ripples from public, anon, authenticated;
revoke execute on function public.rm_shocks(date)                 from public, anon, authenticated;
revoke execute on function public.rm_cascade(bigint, int)         from public, anon, authenticated;
revoke execute on function public.rm_hop(bigint)                  from public, anon, authenticated;
revoke execute on function public.rm_lands(text, int)             from public, anon, authenticated;
revoke execute on function public.rm_archive(int, text)           from public, anon, authenticated;
revoke execute on function public.rm_week(text)                   from public, anon, authenticated;
revoke execute on function public.rm_calibration()                from public, anon, authenticated;
revoke execute on function public.rm_health()                     from public, anon, authenticated;
revoke execute on function public.rm_event(text, text, text)      from public, anon, authenticated;
revoke execute on function public.rm_publish_bundle_v2(date, bigint[], boolean) from public, anon, authenticated;
revoke execute on function public.rm_publish_log(date, text, jsonb) from public, anon, authenticated;
grant execute on function public.rm_shocks(date)                  to anon, authenticated, service_role;
grant execute on function public.rm_cascade(bigint, int)          to anon, authenticated, service_role;
grant execute on function public.rm_hop(bigint)                   to anon, authenticated, service_role;
grant execute on function public.rm_lands(text, int)              to anon, authenticated, service_role;
grant execute on function public.rm_archive(int, text)            to anon, authenticated, service_role;
grant execute on function public.rm_week(text)                    to anon, authenticated, service_role;
grant execute on function public.rm_calibration()                 to anon, authenticated, service_role;
grant execute on function public.rm_health()                      to anon, authenticated, service_role;
grant execute on function public.rm_event(text, text, text)       to anon, authenticated, service_role;
grant execute on function public.rm_publish_bundle_v2(date, bigint[], boolean) to service_role;
grant execute on function public.rm_publish_log(date, text, jsonb) to service_role;
grant execute on all functions in schema ripples to service_role;

-- v5 game write/read RPCs leave the public surface (EXPERIENCE §9; tables stay, dormant)
revoke execute on function public.ripples_submit_play(text, int, jsonb, numeric) from public, anon, authenticated;
revoke execute on function public.ripples_submit_call(text, int, text)          from public, anon, authenticated;
revoke execute on function public.ripples_stats(int)                            from public, anon, authenticated;
grant execute on function public.ripples_submit_play(text, int, jsonb, numeric) to service_role;
grant execute on function public.ripples_submit_call(text, int, text)          to service_role;
grant execute on function public.ripples_stats(int)                            to service_role;

-- Grants audit for the v6 surface: must return zero rows
create or replace function ripples.rm_grant_audit() returns table(fn text, role text)
language sql stable security definer set search_path = '' as $$
  select p.oid::regprocedure::text, r.rolname::text
    from pg_catalog.pg_proc p cross join (values ('anon'), ('authenticated')) r(rolname)
   where p.pronamespace = 'public'::regnamespace
     and (p.proname like 'rm\_%' or p.proname like 'ripples\_%')
     and p.proname not in ('rm_shocks','rm_cascade','rm_hop','rm_lands','rm_archive','rm_week','rm_calibration','rm_health','rm_event',
                           'ripples_latest','ripples_puzzle','ripples_reveal','ripples_callit','ripples_board','ripples_archive',
                           'ripples_brief','ripples_health','ripples_join','ripples_track_record')
     and pg_catalog.has_function_privilege(r.rolname, p.oid, 'EXECUTE')
   order by 1, 2
$$;
revoke execute on function ripples.rm_grant_audit() from public, anon, authenticated;
-- Self-healing: revoke whatever the audit lists (run by every publish; returns how many grants it removed)
create or replace function ripples.rm_enforce_grants() returns int
language plpgsql security definer set search_path = '' as $$
declare r record; n int := 0;
begin
  for r in select distinct a.fn from ripples.rm_grant_audit() a loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.fn);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function ripples.rm_enforce_grants() from public, anon, authenticated;
grant execute on function ripples.rm_enforce_grants() to service_role;

-- ---------------------------------------------------------------------------------------------------------------------
-- 12. Cron (ENGINE §10.3: att-publish-cascades 08:25 and 08:40, after att-finalize-engine 08:20). Migration wsc_rm_publish_cron.
--     ripples-publish {"v2": true} calls rm_publish_bundle_v2 (freeze + bundle), mirrors Storage v2/, feeds, ics, open data, OG.
-- ---------------------------------------------------------------------------------------------------------------------
select cron.unschedule(jobname) from cron.job where jobname in ('rm-publish-0825', 'rm-publish-0840');
select cron.schedule('rm-publish-0825', '25 8 * * *', $$select public.call_collector('ripples-publish', '{"v2": true}'::jsonb)$$);
select cron.schedule('rm-publish-0840', '40 8 * * *', $$select public.call_collector('ripples-publish', '{"v2": true}'::jsonb)$$);
