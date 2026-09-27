-- 18_att_mech_graph (v6 WS-A, 2026-09-25; applied as migrations att_mech_graph_core, att_mech_graph_build)
-- The typed mechanism graph of ENGINE_SPEC §2.1 / §10.2: att_mech_edges (tables created by WS-B from the §10.2 DDL;
-- this file adds the unique/lookup indexes, the seeds and the builder), att_mech_templates v6.0, att_edge_priors seed,
-- the Wikidata claims cache (fetched by att-wikidata via Special:EntityData), the curated industry / geography maps and
-- att_build_graph(p_version), which rebuilds MAP / MECH / WD edges and hashes the graph version into att_ledger.
--
-- Node naming (att_mech_edges.from_node / to_node):
--   'Q123'                      Wikidata item (topic, place, organisation, industry ...)
--   '<source>:<key>'            a series node = att_series (source, key); e.g. 'eia.930:ERCO', 'fred:TXICLAIMS',
--                               'dol.claims:TX', 'noaa.ghcnd:USW00012960', 'tsa.pax:checkpoint', 'twelvedata:XLE'
--   'family:<family>'           event family (att_families)
--   'geo:US-TX'                 U.S. state / DC / PR
--   'naics:<prefix>'  'bea:<code>'   industries (curated NAICS prefix map; BEA 2017 detailed codes)
--   'hiringlab.postings:<sector>'    Indeed Hiring Lab category series
-- Edge types: MAP (identifier / mapper edges that reach series), MECH (mechanism-library template instantiations),
-- WD (whitelisted Wikidata properties, unsigned, strength 0.6), IO (BEA 2017 direct requirements a_ij >= 0.005 and the
-- top-5 Leontief route ideas: meta.render_only = true, meta.never_test = true; IO never generates a test, ENGINE §2.1).

-- ------------------------------------------------------------------ indexes (ENGINE §10.2 unique key, expression form)
create unique index if not exists att_mech_edges_uq
  on ripples.att_mech_edges (from_node, to_node, etype, coalesce(prop, ''), coalesce(template, ''), version);
create index if not exists att_mech_edges_from_live on ripples.att_mech_edges (from_node, etype) where valid_to is null;
create index if not exists att_mech_edges_to_live on ripples.att_mech_edges (to_node, etype) where valid_to is null;

-- ------------------------------------------------------------------ curated maps
create table if not exists ripples.att_naics_map (      -- NAICS prefix -> Hiring Lab categories + sector ETFs (longest prefix wins)
  prefix text primary key, hl_sectors text[] not null default '{}', etfs text[] not null default '{}', label text
);
create table if not exists ripples.att_naics_ces (      -- NAICS 4-digit -> BEA 2017 detail code(s) -> CES series (local crosswalk)
  n4 text primary key, bea text, ces text not null, sector text
);
create table if not exists ripples.att_geo_nodes (      -- U.S. states: Wikidata QID (curated until P300 verifies it) + EIA-930 BAs
  geo text primary key check (geo ~ '^US-[A-Z]{2}$'), label text not null, qid text,
  qid_status text not null default 'curated' check (qid_status in ('curated','verified','mismatch')),
  bas text[] not null default '{}'
);
create table if not exists ripples.att_wd_props (       -- property whitelist (ENGINE §2.1): wd = WD edge, map = MAP edge, fact = kept only
  prop text primary key check (prop ~ '^P[0-9]+$'), label text not null, kind text not null check (kind in ('wd','map','fact'))
);
create table if not exists ripples.att_wd_claims (      -- Special:EntityData cache (90 days); values only, no text
  qid text primary key check (qid ~ '^Q[0-9]+$'),
  fetched_at timestamptz not null default now(),
  status text not null default 'ok' check (status in ('ok','missing','redirect','error')),
  redirect_to text,
  label_en text,
  enwiki text,
  depth smallint not null default 0,                  -- 0 topic, 1 neighbour, 9 geography seed
  claims jsonb not null default '{}'::jsonb           -- {"P176":["Q.."],"P414":[{"v":"Q13677","t":"XYZ"}],"P300":["US-TX"],"P577":["2024-03-01"]}
);
create index if not exists att_wd_claims_fetched on ripples.att_wd_claims (fetched_at);
do $$ begin
  execute 'alter table ripples.att_naics_map enable row level security';
  execute 'alter table ripples.att_naics_ces enable row level security';
  execute 'alter table ripples.att_geo_nodes enable row level security';
  execute 'alter table ripples.att_wd_props enable row level security';
  execute 'alter table ripples.att_wd_claims enable row level security';
end $$;
revoke all on ripples.att_naics_map, ripples.att_naics_ces, ripples.att_geo_nodes, ripples.att_wd_props, ripples.att_wd_claims
  from public, anon, authenticated;

insert into ripples.att_wd_props(prop, label, kind) values
 ('P176','manufacturer','wd'),('P452','industry','wd'),('P17','country','wd'),('P131','located in the administrative territorial entity','wd'),
 ('P127','owned by','wd'),('P1056','product or material produced','wd'),('P361','part of','wd'),('P527','has part','wd'),
 ('P178','developer','wd'),('P170','creator','wd'),('P272','production company','wd'),('P449','original broadcaster','wd'),
 ('P1830','owner of','wd'),('P355','subsidiary','wd'),('P749','parent organization','wd'),('P2283','uses','wd'),
 ('P138','named after','wd'),('P1344','participant in','wd'),('P710','participant','wd'),('P1891','signatory','wd'),
 ('P3320','board member','wd'),('P8047','country of registry','wd'),
 ('P414','stock exchange (qualifier P249 ticker symbol)','map'),('P249','ticker symbol','map'),('P1324','source code repository URL','map'),
 ('P856','official website','map'),('P1733','Steam application ID','map'),('P8729','AniList anime ID','map'),
 ('P31','instance of','fact'),('P300','ISO 3166-2 code','fact'),('P577','publication date','fact'),('P585','point in time','fact'),
 ('P580','start time','fact'),('P571','inception','fact')
on conflict (prop) do update set label = excluded.label, kind = excluded.kind;

-- State QIDs are curated (not yet verified: Wikidata is unreachable while the UA contact gate is closed); att-wikidata
-- fetches them first (depth 9) and att_build_graph flips qid_status to verified / mismatch from their P300 claim.
insert into ripples.att_geo_nodes(geo, label, qid, bas) values
 ('US-AL','Alabama','Q173',array['SOCO','TVA']),('US-AK','Alaska','Q797','{}'),('US-AZ','Arizona','Q816',array['AZPS','SRP','TEPC','WALC']),
 ('US-AR','Arkansas','Q1612',array['MISO','SWPP']),('US-CA','California','Q99',array['CISO','BANC','LDWP','IID','TIDC']),
 ('US-CO','Colorado','Q1261',array['PSCO','WACM']),('US-CT','Connecticut','Q779',array['ISNE']),('US-DE','Delaware','Q1393',array['PJM']),
 ('US-DC','District of Columbia','Q61',array['PJM']),
 ('US-FL','Florida','Q812',array['FPL','FPC','TEC','JEA','SEC','TAL','GVL','FMPP','HST']),('US-GA','Georgia','Q1428',array['SOCO']),
 ('US-HI','Hawaii','Q782','{}'),('US-ID','Idaho','Q1221',array['IPCO','BPAT','PACE']),('US-IL','Illinois','Q1204',array['MISO','PJM']),
 ('US-IN','Indiana','Q1415',array['MISO','PJM']),('US-IA','Iowa','Q1546',array['MISO']),('US-KS','Kansas','Q1558',array['SWPP']),
 ('US-KY','Kentucky','Q1603',array['LGEE','TVA','PJM']),('US-LA','Louisiana','Q1588',array['MISO']),('US-ME','Maine','Q724',array['ISNE']),
 ('US-MD','Maryland','Q1391',array['PJM']),('US-MA','Massachusetts','Q771',array['ISNE']),('US-MI','Michigan','Q1166',array['MISO']),
 ('US-MN','Minnesota','Q1527',array['MISO']),('US-MS','Mississippi','Q1494',array['MISO','SOCO','TVA']),
 ('US-MO','Missouri','Q1581',array['MISO','SWPP','AECI']),('US-MT','Montana','Q1212',array['NWMT']),('US-NE','Nebraska','Q1553',array['SWPP']),
 ('US-NV','Nevada','Q1227',array['NEVP']),('US-NH','New Hampshire','Q759',array['ISNE']),('US-NJ','New Jersey','Q1408',array['PJM']),
 ('US-NM','New Mexico','Q1522',array['PNM','EPE']),('US-NY','New York','Q1384',array['NYIS']),
 ('US-NC','North Carolina','Q1454',array['DUK','CPLE','CPLW']),('US-ND','North Dakota','Q1207',array['MISO','SWPP']),
 ('US-OH','Ohio','Q1397',array['PJM']),('US-OK','Oklahoma','Q1649',array['SWPP']),('US-OR','Oregon','Q824',array['PGE','PACW','BPAT']),
 ('US-PA','Pennsylvania','Q1400',array['PJM']),('US-PR','Puerto Rico','Q1183','{}'),('US-RI','Rhode Island','Q1387',array['ISNE']),
 ('US-SC','South Carolina','Q1456',array['SC','SCEG','DUK','CPLE']),('US-SD','South Dakota','Q1211',array['SWPP','MISO']),
 ('US-TN','Tennessee','Q1509',array['TVA']),('US-TX','Texas','Q1439',array['ERCO','SWPP','MISO','EPE']),('US-UT','Utah','Q829',array['PACE']),
 ('US-VT','Vermont','Q16551',array['ISNE']),('US-VA','Virginia','Q1370',array['PJM']),
 ('US-WA','Washington','Q1223',array['BPAT','PSEI','SCL','TPWR','AVA','CHPD','DOPD','GCPD']),('US-WV','West Virginia','Q1371',array['PJM']),
 ('US-WI','Wisconsin','Q1537',array['MISO']),('US-WY','Wyoming','Q1214',array['PACE','WACM'])
on conflict (geo) do update set label = excluded.label, bas = excluded.bas,
  qid = case when ripples.att_geo_nodes.qid_status = 'verified' then ripples.att_geo_nodes.qid else excluded.qid end;
-- Florida (Q812, P31 Q35657) and OpenAI (Q21708200) were cross-checked against ripples.articles on 2026-09-25.
update ripples.att_geo_nodes set qid_status = 'verified' where geo = 'US-FL' and qid = 'Q812';
insert into ripples.att_naics_map(prefix, hl_sectors, etfs, label) values
 ('11', array['production_and_manufacturing']::text[], '{}'::text[], 'Agriculture, forestry, fishing'),
 ('21', array['installation_and_maintenance','production_and_manufacturing']::text[], array['XLE','XOP']::text[], 'Mining, oil and gas'),
 ('211', array['installation_and_maintenance']::text[], array['XOP','XLE']::text[], 'Oil and gas extraction'),
 ('212', array['installation_and_maintenance']::text[], array['XME']::text[], 'Mining (except oil and gas)'),
 ('213', array['installation_and_maintenance']::text[], array['XLE']::text[], 'Support activities for mining'),
 ('22', array['electrical_engineering','installation_and_maintenance']::text[], array['XLU']::text[], 'Utilities'),
 ('23', array['construction','civil_engineering','architecture']::text[], array['ITB','XHB']::text[], 'Construction'),
 ('31', array['production_and_manufacturing']::text[], array['XLP']::text[], 'Food, beverage, textile manufacturing'),
 ('32', array['production_and_manufacturing','industrial_engineering']::text[], array['XLB']::text[], 'Wood, paper, chemical manufacturing'),
 ('3254', array['scientific_research_and_development','pharmacy']::text[], array['IBB','XLV']::text[], 'Pharmaceutical manufacturing'),
 ('324', array['production_and_manufacturing']::text[], array['XLE']::text[], 'Petroleum and coal products'),
 ('33', array['production_and_manufacturing','mechanical_engineering','industrial_engineering']::text[], array['XLI']::text[], 'Metal, machinery, equipment manufacturing'),
 ('331', array['production_and_manufacturing']::text[], array['XME']::text[], 'Primary metals'),
 ('334', array['electrical_engineering','production_and_manufacturing']::text[], array['SMH','XLK']::text[], 'Computer and electronic products'),
 ('3344', array['electrical_engineering']::text[], array['SMH']::text[], 'Semiconductors'),
 ('335', array['electrical_engineering']::text[], array['XLI']::text[], 'Electrical equipment'),
 ('336', array['mechanical_engineering','production_and_manufacturing']::text[], array['XLY','XLI']::text[], 'Transportation equipment'),
 ('3364', array['mechanical_engineering','aviation']::text[], array['XLI']::text[], 'Aerospace'),
 ('42', array['sales','loading_and_stocking']::text[], '{}'::text[], 'Wholesale trade'),
 ('44', array['retail','loading_and_stocking']::text[], array['XRT']::text[], 'Retail trade'),
 ('45', array['retail','loading_and_stocking']::text[], array['XRT']::text[], 'Retail trade'),
 ('4A', array['retail']::text[], array['XRT']::text[], 'Other retail'),
 ('4B', array['retail']::text[], array['XRT']::text[], 'All other retail'),
 ('48', array['logistic_support','driving','loading_and_stocking']::text[], array['IYT']::text[], 'Transportation'),
 ('481', array['aviation']::text[], array['JETS']::text[], 'Air transportation'),
 ('484', array['driving']::text[], array['IYT']::text[], 'Truck transportation'),
 ('49', array['logistic_support','loading_and_stocking','driving']::text[], array['IYT']::text[], 'Couriers and warehousing'),
 ('51', array['media_and_communications','it_systems_and_solutions']::text[], array['XLC']::text[], 'Information'),
 ('511', array['software_development']::text[], array['IGV']::text[], 'Publishing and software'),
 ('5112', array['software_development']::text[], array['IGV']::text[], 'Software publishers'),
 ('512', array['arts_and_entertainment','media_and_communications']::text[], array['XLC']::text[], 'Motion picture and sound recording'),
 ('515', array['media_and_communications']::text[], array['XLC']::text[], 'Broadcasting'),
 ('517', array['it_infrastructure_operations_and_support']::text[], array['XLC']::text[], 'Telecommunications'),
 ('518', array['it_infrastructure_operations_and_support']::text[], array['XLK']::text[], 'Data processing, hosting'),
 ('519', array['media_and_communications','data_and_analytics']::text[], array['XLC']::text[], 'Other information services'),
 ('52', array['banking_and_finance']::text[], array['XLF']::text[], 'Finance'),
 ('522', array['banking_and_finance']::text[], array['KRE','XLF']::text[], 'Credit intermediation'),
 ('523', array['banking_and_finance']::text[], array['XLF']::text[], 'Securities and investments'),
 ('524', array['insurance']::text[], array['KIE']::text[], 'Insurance'),
 ('53', array['sales','administrative_assistance']::text[], array['XLRE']::text[], 'Real estate and rental'),
 ('5411', array['legal']::text[], '{}'::text[], 'Legal services'),
 ('5412', array['accounting']::text[], '{}'::text[], 'Accounting services'),
 ('5413', array['architecture','civil_engineering']::text[], '{}'::text[], 'Architectural and engineering services'),
 ('5415', array['software_development','it_systems_and_solutions']::text[], array['IGV','XLK']::text[], 'Computer systems design'),
 ('5416', array['management','project_management']::text[], '{}'::text[], 'Management consulting'),
 ('5417', array['scientific_research_and_development']::text[], '{}'::text[], 'Scientific R&D'),
 ('5418', array['marketing']::text[], '{}'::text[], 'Advertising'),
 ('54', array['data_and_analytics','management']::text[], '{}'::text[], 'Professional services'),
 ('55', array['management']::text[], '{}'::text[], 'Management of companies'),
 ('56', array['administrative_assistance','cleaning_and_sanitation','security_and_public_safety']::text[], '{}'::text[], 'Administrative and support'),
 ('5613', array['human_resources']::text[], '{}'::text[], 'Employment services'),
 ('61', array['education_and_instruction']::text[], '{}'::text[], 'Educational services'),
 ('62', array['nursing','medical_technician']::text[], array['XLV']::text[], 'Health care'),
 ('621', array['physicians_and_surgeons','medical_technician','therapy']::text[], array['XLV']::text[], 'Ambulatory health care'),
 ('6212', array['dental']::text[], '{}'::text[], 'Dentists'),
 ('622', array['nursing','physicians_and_surgeons']::text[], array['XLV']::text[], 'Hospitals'),
 ('623', array['nursing','personal_care_and_home_health']::text[], '{}'::text[], 'Nursing and residential care'),
 ('624', array['community_and_social_service','childcare']::text[], '{}'::text[], 'Social assistance'),
 ('6244', array['childcare']::text[], '{}'::text[], 'Child day care'),
 ('71', array['arts_and_entertainment']::text[], array['PEJ']::text[], 'Arts, entertainment, recreation'),
 ('721', array['hospitality_and_tourism']::text[], array['PEJ']::text[], 'Accommodation'),
 ('722', array['food_preparation_and_service']::text[], array['PEJ']::text[], 'Food services'),
 ('81', array['installation_and_maintenance','personal_care_and_home_health']::text[], '{}'::text[], 'Other services'),
 ('811', array['installation_and_maintenance']::text[], '{}'::text[], 'Repair and maintenance'),
 ('812', array['personal_care_and_home_health']::text[], '{}'::text[], 'Personal and laundry services'),
 ('G', array['security_and_public_safety','administrative_assistance']::text[], '{}'::text[], 'Government'),
 ('S', array['administrative_assistance']::text[], '{}'::text[], 'Government enterprises / other')
on conflict (prefix) do update set hl_sectors = excluded.hl_sectors, etfs = excluded.etfs, label = excluded.label;
-- NAICS 4-digit -> BEA 2017 detail code(s) -> CES series id (local crosswalk naics4_exposure.csv, 277 rows)
insert into ripples.att_naics_ces(n4, bea, ces, sector)
select split_part(x, '|', 1), split_part(x, '|', 2), split_part(x, '|', 3), split_part(x, '|', 4)
  from unnest(string_to_array('1133|113000|CES1011330001|Farming & forestry;2111|211000|CES1021110001|Mining;2121|212100|CES1021210001|Mining;2122|212230,2122A0|CES1021220001|Mining;2123|212310,2123A0|CES1021230001|Mining;2131|213111,21311A|CES1021310001|Mining;2211|221100|CES4422110001|Utilities;2212|221200|CES4422120001|Utilities;2213|221300|CES4422130001|Utilities;2361|230302,233411,233412,2334A0|CES2023610001|Construction;2362|230301,233210,233230,233262,2332A0,2332D0|CES2023620001|Construction;2371|233240|CES2023710001|Construction;2372|233210,233230,233240,233262,2332A0,2332C0,2332D0,233411,233412,2334A0|CES2023720001|Construction;2373|2332C0|CES2023730001|Construction;2379|2332D0|CES2023790001|Construction;2381|230301,230302,233210,233230,233240,233262,2332A0,2332D0,233411,233412,2334A0|CES2023810001|Construction;2382|230301,230302,233210,233230,233240,233262,2332A0,2332D0,233411,233412,2334A0|CES2023820001|Construction;2383|230301,230302,233210,233230,233240,233262,2332A0,2332D0,233411,233412,2334A0|CES2023830001|Construction;2389|230301,230302,233210,233230,233240,233262,2332A0,2332D0,233411,233412,2334A0|CES2023890001|Construction;3111|311111,311119|CES3231110001|Manufacturing;3112|311210,311221,311224,311225,311230|CES3231120001|Manufacturing;3113|311300|CES3231130001|Manufacturing;3114|311410,311420|CES3231140001|Manufacturing;3115|311513,311514,31151A,311520|CES3231150001|Manufacturing;3116|311615,31161A|CES3231160001|Manufacturing;3117|311700|CES3231170001|Manufacturing;3118|311810,3118A0|CES3231180001|Manufacturing;3119|311910,311920,311930,311940,311990|CES3231190001|Manufacturing;3121|312110,312120,312130,312140|CES3231210001|Manufacturing;3122|312200|CES3231220001|Manufacturing;3131|313100|CES3231310001|Manufacturing;3132|313200|CES3231320001|Manufacturing;3133|313300|CES3231330001|Manufacturing;3141|314110,314120|CES3231410001|Manufacturing;3149|314900|CES3231490001|Manufacturing;3211|321100|CES3132110001|Manufacturing;3212|321200|CES3132120001|Manufacturing;3219|321910,3219A0|CES3132190001|Manufacturing;3221|322110,322120,322130|CES3232210001|Manufacturing;3222|322210,322220,322230,322291,322299|CES3232220001|Manufacturing;3231|323110,323120|CES3232310001|Manufacturing;3241|324110,324121,324122,324190|CES3232410001|Manufacturing;3251|325110,325120,325130,325180,325190|CES3232510001|Manufacturing;3252|325211,3252A0|CES3232520001|Manufacturing;3253|325310,325320|CES3232530001|Manufacturing;3254|325411,325412,325413,325414|CES3232540001|Manufacturing;3255|325510,325520|CES3232550001|Manufacturing;3256|325610,325620|CES3232560001|Manufacturing;3259|325910,3259A0|CES3232590001|Manufacturing;3261|326110,326120,326130,326140,326150,326160,326190|CES3232610001|Manufacturing;3262|326210,326220,326290|CES3232620001|Manufacturing;3271|327100|CES3132710001|Manufacturing;3272|327200|CES3132720001|Manufacturing;3273|327310,327320,327330,327390|CES3132730001|Manufacturing;3274|327400|CES3132740001|Manufacturing;3279|327910,327991,327992,327993,327999|CES3132790001|Manufacturing;3311|331110|CES3133110001|Manufacturing;3312|331200|CES3133120001|Manufacturing;3313|331313,331314,33131B|CES3133130001|Manufacturing;3314|331410,331420,331490|CES3133140001|Manufacturing;3315|331510,331520|CES3133150001|Manufacturing;3321|332114,332119,33211A|CES3133210001|Manufacturing;3322|332200|CES3133220001|Manufacturing;3323|332310,332320|CES3133230001|Manufacturing;3324|332410,332420,332430|CES3133240001|Manufacturing;3325|332500|CES3133250001|Manufacturing;3326|332600|CES3133260001|Manufacturing;3327|332710,332720|CES3133270001|Manufacturing;3328|332800|CES3133280001|Manufacturing;3329|332913,33291A,332991,332996,332999,33299A|CES3133290001|Manufacturing;3331|333111,333112,333120,333130|CES3133310001|Manufacturing;3332|333242,33329A|CES3133320001|Manufacturing;3333|333314,333316,333318|CES3133330001|Manufacturing;3334|333413,333414,333415|CES3133340001|Manufacturing;3335|333511,333514,333517,33351B|CES3133350001|Manufacturing;3336|333611,333612,333613,333618|CES3133360001|Manufacturing;3339|333912,333914,333920,333991,333993,333994,33399A,33399B|CES3133390001|Manufacturing;3341|334111,334112,334118|CES3133410001|Manufacturing;3342|334210,334220,334290|CES3133420001|Manufacturing;3344|334413,334418,33441A|CES3133440001|Manufacturing;3345|334510,334511,334512,334513,334514,334515,334516,334517,33451A|CES3133450001|Manufacturing;3351|335110,335120|CES3133510001|Manufacturing;3352|335210,335220|CES3133520001|Manufacturing;3353|335311,335312,335313,335314|CES3133530001|Manufacturing;3359|335911,335912,335920,335930,335991,335999|CES3133590001|Manufacturing;3361|336111,336112,336120|CES3133610001|Manufacturing;3362|336211,336212,336213,336214|CES3133620001|Manufacturing;3363|336310,336320,336350,336360,336370,336390,3363A0|CES3133630001|Manufacturing;3364|336411,336412,336413,336414,33641A|CES3133640001|Manufacturing;3365|336500|CES3133650001|Manufacturing;3366|336611,336612|CES3133660001|Manufacturing;3369|336991,336992,336999|CES3133690001|Manufacturing;3371|337110,337121,337122,337127,33712N|CES3133710001|Manufacturing;3372|337215,33721A|CES3133720001|Manufacturing;3379|337900|CES3133790001|Manufacturing;3391|339112,339113,339114,339115,339116|CES3133910001|Manufacturing;3399|339910,339920,339930,339940,339950,339990|CES3133990001|Manufacturing;4231|423100|CES4142310001|Wholesale;4232|423A00|CES4142320001|Wholesale;4233|423A00|CES4142330001|Wholesale;4234|423400|CES4142340001|Wholesale;4235|423A00|CES4142350001|Wholesale;4236|423600|CES4142360001|Wholesale;4237|423A00|CES4142370001|Wholesale;4238|423800|CES4142380001|Wholesale;4239|423A00|CES4142390001|Wholesale;4241|424A00|CES4142410001|Wholesale;4242|424200|CES4142420001|Wholesale;4243|424A00|CES4142430001|Wholesale;4244|424400|CES4142440001|Wholesale;4245|424A00|CES4142450001|Wholesale;4246|424A00|CES4142460001|Wholesale;4247|424700|CES4142470001|Wholesale;4248|424A00|CES4142480001|Wholesale;4249|424A00|CES4142490001|Wholesale;4251|425000|CES4142510001|Wholesale;4411|441000|CES4244110001|Retail;4412|441000|CES4244120001|Retail;4413|441000|CES4244130001|Retail;4421|4B0000|CES4244210001|Retail;4422|4B0000|CES4244220001|Retail;4431|4B0000|CES4244310001|Retail;4441|444000|CES4244410001|Retail;4442|444000|CES4244420001|Retail;4451|445000|CES4244510001|Retail;4452|445000|CES4244520001|Retail;4453|445000|CES4244530001|Retail;4461|446000|CES4244610001|Retail;4471|447000|CES4244710001|Retail;4481|448000|CES4244810001|Retail;4482|448000|CES4244820001|Retail;4483|448000|CES4244830001|Retail;4511|4B0000|CES4245110001|Retail;4512|4B0000|CES4245120001|Retail;4522|452000|CES4245220001|Retail;4523|452000|CES4245230001|Retail;4531|4B0000|CES4245310001|Retail;4532|4B0000|CES4245320001|Retail;4533|4B0000|CES4245330001|Retail;4539|4B0000|CES4245390001|Retail;4541|454000|CES4245410001|Retail;4542|454000|CES4245420001|Retail;4543|454000|CES4245430001|Retail;4811|481000|CES4348110001|Transport & warehousing;4812|481000|CES4348120001|Transport & warehousing;4821|482000|CES4348210001|Transport & warehousing;4831|483000|CES4348310001|Transport & warehousing;4832|483000|CES4348320001|Transport & warehousing;4841|484000|CES4348410001|Transport & warehousing;4842|484000|CES4348420001|Transport & warehousing;4851|485000|CES4348510001|Transport & warehousing;4852|485000|CES4348520001|Transport & warehousing;4853|485000|CES4348530001|Transport & warehousing;4854|485000|CES4348540001|Transport & warehousing;4855|485000|CES4348550001|Transport & warehousing;4859|485000|CES4348590001|Transport & warehousing;4861|486000|CES4348610001|Transport & warehousing;4862|486000|CES4348620001|Transport & warehousing;4869|486000|CES4348690001|Transport & warehousing;4871|48A000|CES4348710001|Transport & warehousing;4872|48A000|CES4348720001|Transport & warehousing;4879|48A000|CES4348790001|Transport & warehousing;4881|48A000|CES4348810001|Transport & warehousing;4882|48A000|CES4348820001|Transport & warehousing;4883|48A000|CES4348830001|Transport & warehousing;4884|48A000|CES4348840001|Transport & warehousing;4885|48A000|CES4348850001|Transport & warehousing;4889|48A000|CES4348890001|Transport & warehousing;4911|491000|CES4349110001|Government;4921|492000|CES4349210001|Transport & warehousing;4922|492000|CES4349220001|Transport & warehousing;4931|493000|CES4349310001|Transport & warehousing;5111|511110,511120,511130,5111A0|CES5051110001|Information;5112|511200|CES5051120001|Information;5121|512100|CES5051210001|Information;5122|512200|CES5051220001|Information;5151|515100|CES5051510001|Information;5152|515200|CES5051520001|Information;5173|517110,517210|CES5051730001|Information;5174|517A00|CES5051740001|Information;5179|517A00|CES5051790001|Information;5182|518200|CES5051820001|Information;5191|519130,5191A0|CES5051910001|Information;5211|52A000|CES5552110001|Finance & real estate;5221|52A000|CES5552210001|Finance & real estate;5222|522A00|CES5552220001|Finance & real estate;5223|522A00|CES5552230001|Finance & real estate;5231|523A00|CES5552310001|Finance & real estate;5232|523A00|CES5552320001|Finance & real estate;5239|523900|CES5552390001|Finance & real estate;5241|524113,5241XX|CES5552410001|Finance & real estate;5242|524200|CES5552420001|Finance & real estate;5251|525000|CES5552510001|Finance & real estate;5259|525000|CES5552590001|Finance & real estate;5311|531HSO,531HST,531ORE|CES5553110001|Finance & real estate;5312|531ORE|CES5553120001|Finance & real estate;5313|531ORE|CES5553130001|Finance & real estate;5321|532100|CES5553210001|Finance & real estate;5322|532A00|CES5553220001|Finance & real estate;5323|532A00|CES5553230001|Finance & real estate;5324|532400|CES5553240001|Finance & real estate;5331|533000|CES5553310001|Finance & real estate;5411|541100|CES6054110001|Professional services;5412|541200|CES6054120001|Professional services;5413|541300|CES6054130001|Professional services;5414|541400|CES6054140001|Professional services;5415|541511,541512,54151A|CES6054150001|Professional services;5416|541610,5416A0|CES6054160001|Professional services;5417|541700|CES6054170001|Professional services;5418|541800|CES6054180001|Professional services;5419|541920,541940,5419A0|CES6054190001|Professional services;5511|550000|CES6055110001|Professional services;5611|561100|CES6056110001|Professional services;5612|561200|CES6056120001|Professional services;5613|561300|CES6056130001|Professional services;5614|561400|CES6056140001|Professional services;5615|561500|CES6056150001|Professional services;5616|561600|CES6056160001|Professional services;5617|561700|CES6056170001|Professional services;5619|561900|CES6056190001|Professional services;5621|562000|CES6056210001|Professional services;5622|562000|CES6056220001|Professional services;5629|562000|CES6056290001|Professional services;6111|611100|CES6561110001|Education & health;6112|611A00|CES6561120001|Education & health;6113|611A00|CES6561130001|Education & health;6114|611B00|CES6561140001|Education & health;6115|611B00|CES6561150001|Education & health;6116|611B00|CES6561160001|Education & health;6117|611B00|CES6561170001|Education & health;6211|621100|CES6562110001|Education & health;6212|621200|CES6562120001|Education & health;6213|621300|CES6562130001|Education & health;6214|621400|CES6562140001|Education & health;6215|621500|CES6562150001|Education & health;6216|621600|CES6562160001|Education & health;6219|621900|CES6562190001|Education & health;6221|622000|CES6562210001|Education & health;6222|622000|CES6562220001|Education & health;6223|622000|CES6562230001|Education & health;6231|623A00|CES6562310001|Education & health;6232|623B00|CES6562320001|Education & health;6233|623A00|CES6562330001|Education & health;6239|623B00|CES6562390001|Education & health;6241|624100|CES6562410001|Education & health;6242|624A00|CES6562420001|Education & health;6243|624A00|CES6562430001|Education & health;6244|624400|CES6562440001|Education & health;7111|711100|CES7071110001|Arts, food & lodging;7112|711200|CES7071120001|Arts, food & lodging;7113|711A00|CES7071130001|Arts, food & lodging;7114|711A00|CES7071140001|Arts, food & lodging;7115|711500|CES7071150001|Arts, food & lodging;7121|712000|CES7071210001|Arts, food & lodging;7131|713100|CES7071310001|Arts, food & lodging;7132|713200|CES7071320001|Arts, food & lodging;7139|713900|CES7071390001|Arts, food & lodging;7211|721000|CES7072110001|Arts, food & lodging;7212|721000|CES7072120001|Arts, food & lodging;7213|721000|CES7072130001|Arts, food & lodging;7223|722A00|CES7072230001|Arts, food & lodging;7224|722A00|CES7072240001|Arts, food & lodging;7225|722110,722211,722A00|CES7072250001|Arts, food & lodging;8111|811100|CES8081110001|Other services;8112|811200|CES8081120001|Other services;8113|811300|CES8081130001|Other services;8114|811400|CES8081140001|Other services;8121|812100|CES8081210001|Other services;8122|812200|CES8081220001|Other services;8123|812300|CES8081230001|Other services;8129|812900|CES8081290001|Other services;8131|813100|CES8081310001|Other services;8132|813A00|CES8081320001|Other services;8133|813A00|CES8081330001|Other services;8134|813B00|CES8081340001|Other services;8139|813B00|CES8081390001|Other services;8141|814000|CES8081410001|Other services', ';')) x
on conflict (n4) do update set bea = excluded.bea, ces = excluded.ces, sector = excluded.sector;

-- ------------------------------------------------------------------ mechanism library v6.0 (ENGINE §2.1 MECH)
-- target_pattern: {"nodes":[series nodes]} static targets; {"pattern":"eia.930:{BA}","geo_from":"place_ba"} resolved from
-- the event's place (P131 chain -> geo:US-XX -> MAP edges); {"source":"npm.dl","topic_keys":true} resolved from the
-- event topic's own keys. demean "aggregate" = regional series demeaned by the named aggregate (ENGINE §3.5).
-- Channel MONEY templates exist for completeness but MONEY is inactive in att_channel_stat (lead decision pending, D-10).
insert into ripples.att_mech_templates(template, family, target_pattern, sign, channel, l_days, rationale, version) values
 ('storm_air_travel','hazard.storm','{"nodes":["tsa.pax:checkpoint"]}',-1,'PHYS',7,'Storm warnings and airport closures -> cancelled and avoided flights; national checkpoint count dips','v6.0'),
 ('storm_transit','hazard.storm','{"nodes":["mta.ridership:subway","mta.ridership:bus","mta.ridership:lirr","mta.ridership:mnr"],"geo_filter":["US-NY","US-NJ","US-CT"]}',-1,'PHYS',7,'Storms over the New York metro -> transit ridership dips (only when the event geography includes the metro)','v6.0'),
 ('storm_fema_decl','hazard.storm','{"nodes":["fema.decl:DR","fema.decl:EM"],"pattern":"fema.decl:st:{ST}","geo_from":"place_state"}',1,'INST',90,'Damage -> federal emergency / major-disaster declarations','v6.0'),
 ('storm_nws_warnings','hazard.storm','{"nodes":["iem.warn:TO.W","iem.warn:SV.W","iem.warn:FF.W","iem.warn:EW.W","iem.warn:__total__"]}',1,'INST',7,'Severe weather -> NWS storm-based warnings (IEM archive)','v6.0'),
 ('storm_claims','hazard.storm','{"patterns":["fred:{ST}ICLAIMS","dol.claims:{ST}"],"geo_from":"place_state","demean":"aggregate","agg":"fred:ICNSA"}',1,'JOBS',28,'Business closures after a storm -> state initial unemployment claims','v6.0'),
 ('storm_grid_demand','hazard.storm','{"pattern":"eia.930:{BA}","geo_from":"place_ba","demean":"aggregate","agg":"eia.930:US48SUM"}',-1,'PHYS',7,'Outages and closures -> lower electricity demand in the affected balancing authorities','v6.0'),
 ('storm_gasoline','hazard.storm','{"nodes":["fred:GASREGW","fred:DJFUELUSGULF"],"geo_filter":["US-TX","US-LA","US-MS","US-AL","US-FL"]}',0,'ECON',14,'Gulf Coast refinery and port disruption -> fuel prices (Gulf landfalls only)','v6.0'),
 ('flood_fema_decl','hazard.flood','{"nodes":["fema.decl:DR","fema.decl:it:flood"],"pattern":"fema.decl:st:{ST}","geo_from":"place_state"}',1,'INST',90,'Flood damage -> federal declarations','v6.0'),
 ('flood_nws_warnings','hazard.flood','{"nodes":["iem.warn:FF.W","iem.warn:FA.Y","iem.warn:FL.W"]}',1,'INST',7,'Flooding -> NWS flood warnings','v6.0'),
 ('flood_claims','hazard.flood','{"patterns":["fred:{ST}ICLAIMS","dol.claims:{ST}"],"geo_from":"place_state","demean":"aggregate","agg":"fred:ICNSA"}',1,'JOBS',28,'Flood closures -> state initial claims','v6.0'),
 ('wildfire_fema_decl','hazard.wildfire','{"nodes":["fema.decl:it:fire","fema.decl:FM"],"pattern":"fema.decl:st:{ST}","geo_from":"place_state"}',1,'INST',90,'Wildfires -> fire-management assistance and disaster declarations','v6.0'),
 ('wildfire_nws_warnings','hazard.wildfire','{"nodes":["iem.warn:__total__"]}',1,'INST',7,'Wildfire weather -> NWS warnings. Limited: red-flag and air-quality alerts are zone-based and not in the IEM storm-based feed','v6.0'),
 ('heat_grid_demand','hazard.heat','{"pattern":"eia.930:{BA}","geo_from":"place_ba","demean":"aggregate","agg":"eia.930:US48SUM"}',1,'PHYS',7,'Heat -> air-conditioning load -> electricity demand in the affected balancing authorities','v6.0'),
 ('heat_gas_price','hazard.heat','{"nodes":["fred:DHHNGSP"]}',1,'ECON',4,'Power burn for cooling -> Henry Hub spot gas price','v6.0'),
 ('heat_cpi_electricity','hazard.heat','{"nodes":["bls.cpi_items:CUSR0000SEHF01"]}',1,'ECON',90,'Sustained heat -> electricity prices in the next CPI release (release look)','v6.0'),
 ('cold_grid_demand','hazard.cold','{"pattern":"eia.930:{BA}","geo_from":"place_ba","demean":"aggregate","agg":"eia.930:US48SUM"}',1,'PHYS',7,'Cold -> heating load -> electricity demand','v6.0'),
 ('cold_gas_price','hazard.cold','{"nodes":["fred:DHHNGSP"]}',1,'ECON',4,'Heating demand and freeze-offs -> Henry Hub spot gas price','v6.0'),
 ('cold_air_travel','hazard.cold','{"nodes":["tsa.pax:checkpoint"]}',-1,'PHYS',7,'Winter storms -> cancelled flights','v6.0'),
 ('quake_fema_decl','hazard.quake','{"nodes":["fema.decl:DR","fema.decl:it:earthquake"],"pattern":"fema.decl:st:{ST}","geo_from":"place_state"}',1,'INST',90,'Damaging U.S. earthquakes -> federal declarations','v6.0'),
 ('model_release_npm','tech.model_release','{"nodes":["npm.dl:openai","npm.dl:@anthropic-ai/sdk","npm.dl:ollama","npm.dl:langchain","npm.dl:@modelcontextprotocol/sdk"],"source":"npm.dl","topic_keys":true}',1,'BLD',14,'New model -> developers install client SDKs','v6.0'),
 ('model_release_pypi','tech.model_release','{"nodes":["pypi.dl:openai","pypi.dl:anthropic","pypi.dl:transformers","pypi.dl:torch","pypi.dl:langchain"],"source":"pypi.dl","topic_keys":true}',1,'BLD',14,'New model -> Python SDK and framework downloads','v6.0'),
 ('model_release_hf','tech.model_release','{"source":"hf.trending","topic_keys":true}',1,'BLD',14,'Open-weight release -> Hugging Face trending','v6.0'),
 ('model_release_hn','tech.model_release','{"source":"hn.algolia","topic_keys":true}',1,'SOC',2,'Release -> Hacker News discussion (attention channel)','v6.0'),
 ('model_release_se','tech.model_release','{"source":"se.api","topic_keys":true}',1,'SOC',2,'Release -> developer questions on Stack Exchange','v6.0'),
 ('model_release_pm','tech.model_release','{"source":"poly.mkt","topic_keys":true}',0,'PM',4,'Release -> repricing of AI prediction markets tied to the topic','v6.0'),
 ('software_release_se','tech.software_release','{"source":"se.api","topic_keys":true}',1,'SOC',2,'New software version -> questions on Stack Exchange','v6.0'),
 ('software_release_npm','tech.software_release','{"source":"npm.dl","topic_keys":true}',1,'BLD',14,'New version -> package downloads','v6.0'),
 ('macro_release_rates','policy.macro_release','{"nodes":["fred:DGS2","fred:DGS10","fred:T10YIE","fred:DEXUSEU","fred:DTWEXBGS"]}',0,'ECON',4,'Scheduled data surprise -> Treasury yields, breakevens and the dollar','v6.0'),
 ('macro_release_pm','policy.macro_release','{"source":"poly.mkt","topic_keys":true,"also":["kalshi.mkt"]}',0,'PM',4,'Data release -> rate-path prediction markets','v6.0'),
 ('policy_decision_pm','policy.decision','{"source":"poly.mkt","topic_keys":true,"also":["kalshi.mkt"]}',0,'PM',4,'Decision -> repricing of markets tagged with it','v6.0'),
 ('policy_decision_fred','policy.decision','{"nodes":["fred:DGS2","fred:DGS10","fred:DEXUSEU","fred:DTWEXBGS","fred:DCOILWTICO"]}',0,'ECON',4,'Decision naming a rate, tariff or currency -> rates / FX / oil','v6.0'),
 ('policy_decision_spending','policy.decision','{"source":"usasp.spend","topic_keys":true}',1,'INST',90,'Programme decision -> federal obligations (monthly)','v6.0'),
 ('film_consumption','media.film','{"sources":["apple.rss","anilist"],"topic_keys":true}',1,'CONS',14,'Premiere -> soundtrack / app / anime chart moves','v6.0'),
 ('game_consumption','media.game','{"sources":["steamspy"],"topic_keys":true}',1,'CONS',14,'Game launch -> concurrent players','v6.0'),
 ('series_consumption','media.series','{"sources":["anilist","apple.rss"],"topic_keys":true}',1,'CONS',14,'Season premiere -> tracking and chart moves','v6.0'),
 ('storm_insurers_equity','hazard.storm','{"nodes":["twelvedata:KIE"]}',0,'MONEY',4,'Insured losses -> insurer ETF abnormal volume/return (derived z only; MONEY inactive)','v6.0'),
 ('storm_airlines_equity','hazard.storm','{"nodes":["twelvedata:JETS"]}',0,'MONEY',4,'Cancellations -> airline ETF (derived z only; MONEY inactive)','v6.0'),
 ('heat_utilities_equity','hazard.heat','{"nodes":["twelvedata:XLU","twelvedata:UNG"]}',0,'MONEY',4,'Load and gas burn -> utilities / natural-gas ETFs (derived z only; MONEY inactive)','v6.0'),
 ('model_release_semis_equity','tech.model_release','{"nodes":["twelvedata:SMH","twelvedata:IGV","twelvedata:XLK"]}',0,'MONEY',4,'Model release -> semiconductor / software ETFs (derived z only; MONEY inactive)','v6.0'),
 ('macro_release_banks_equity','policy.macro_release','{"nodes":["twelvedata:KRE","twelvedata:XLF","twelvedata:SPY"]}',0,'MONEY',4,'Rates surprise -> bank ETFs (derived z only; MONEY inactive)','v6.0')
on conflict (template) do update set family = excluded.family, target_pattern = excluded.target_pattern, sign = excluded.sign,
  channel = excluded.channel, l_days = excluded.l_days, rationale = excluded.rationale, version = excluded.version;

-- ------------------------------------------------------------------ seeded path priors (ENGINE §2.1: until >= 30 resolved hops per cell)
insert into ripples.att_edge_priors(etype, channel, family, tested, measured, prior, seeded, fitted_to, version)
select e.etype, c.channel, 'any', 0, 0, e.prior, true, null::date, 'v6.0-seed'
  from (values ('MAP',0.20::real),('MECH',0.25),('WD',0.10),('CS',0.15),('GK',0.10)) e(etype, prior)
  cross join (select channel from ripples.att_channel_stat) c
union all select 'WIKI', 'READ', 'any', 0, 0, 0.15::real, true, null::date, 'v6.0-seed'
on conflict (etype, channel, family, version) do update set prior = excluded.prior, seeded = true;

-- ------------------------------------------------------------------ Wikidata claims cache: queue + upsert (att-wikidata)
-- Queue order: geography seeds (depth 9) -> topic QIDs (depth 0) never fetched or older than 90 days -> depth-1
-- neighbours (QID values of whitelisted 'wd' properties of fetched topics). Serial fetch, <= 250 calls/day (bucket wikidata).
create or replace function ripples.att_wd_queue(p_limit int default 80) returns jsonb
language sql stable security definer set search_path = '' as $$
  with fresh as (select qid from ripples.att_wd_claims where fetched_at > now() - interval '90 days'),
  seeds as (select g.qid, 9 as depth, 0 as pri from ripples.att_geo_nodes g where g.qid is not null and g.qid not in (select qid from fresh)),
  topics as (select t.qid, 0 as depth, 1 as pri from ripples.att_topics t
              where t.qid ~ '^Q[0-9]+$' and t.status in ('active','panel') and t.qid not in (select qid from fresh)),
  neigh as (select distinct v.val as qid, 1 as depth, 2 as pri
              from ripples.att_wd_claims c
              cross join lateral jsonb_each(c.claims) p(prop, vals)
              join ripples.att_wd_props w on w.prop = p.prop and w.kind = 'wd'
              cross join lateral jsonb_array_elements_text(case when jsonb_typeof(p.vals) = 'array' then p.vals else '[]'::jsonb end) v(val)
             where c.depth = 0 and c.status = 'ok' and v.val ~ '^Q[0-9]+$' and v.val not in (select qid from fresh)),
  q as (select qid, min(depth) depth, min(pri) pri from (select * from seeds union all select * from topics union all select * from neigh) z group by qid)
  select coalesce(jsonb_agg(jsonb_build_object('qid', qid, 'depth', depth) order by pri, qid), '[]'::jsonb)
    from (select * from q order by pri, qid limit greatest(1, least(p_limit, 250))) x;
$$;

create or replace function ripples.att_wd_claims_upsert(p_rows jsonb) returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  insert into ripples.att_wd_claims(qid, fetched_at, status, redirect_to, label_en, enwiki, depth, claims)
  select r->>'qid', now(), coalesce(r->>'status','ok'), nullif(r->>'redirect_to',''),
         left(nullif(r->>'label_en',''), 200), left(nullif(r->>'enwiki',''), 200),
         coalesce((r->>'depth')::smallint, 0), coalesce(r->'claims', '{}'::jsonb)
    from jsonb_array_elements(p_rows) r
   where r->>'qid' ~ '^Q[0-9]+$' and coalesce(r->>'status','ok') in ('ok','missing','redirect','error')
  on conflict (qid) do update set fetched_at = now(), status = excluded.status, redirect_to = excluded.redirect_to,
    label_en = excluded.label_en, enwiki = excluded.enwiki, depth = least(ripples.att_wd_claims.depth, excluded.depth),
    claims = excluded.claims;
  get diagnostics n = row_count;
  return n;
end $$;

-- ------------------------------------------------------------------ equities watch list (att-equities): tickers mapped by MAP edges
create or replace function ripples.att_equity_symbols(p_max int default 30) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(t order by t), '[]'::jsonb) from (
    select distinct substr(to_node, 12) t from ripples.att_mech_edges
     where etype = 'MAP' and valid_to is null and to_node like 'twelvedata:%' and prop = 'P414'
     order by 1 limit greatest(0, least(p_max, 60))) z;
$$;

-- ------------------------------------------------------------------ ledger append (formula of SPEC §10 / ripples._ledger_write)
-- chain_hash = sha256(prev_hash || payload_hash); first prev_hash = ripples.ledger head (zeros while that ledger is empty).
-- If WS-B's ripples.att_ledger_append(date,text,jsonb,text) exists it is used instead (same table, same formula).
create or replace function ripples._att_ledger_append_wsa(p_day date, p_kind text, p_ref jsonb, p_payload_hash text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare prev text; ch text; s bigint;
begin
  if to_regprocedure('ripples.att_ledger_append(date,text,jsonb,text)') is not null then
    execute 'select ripples.att_ledger_append($1,$2,$3,$4)::bigint' into s using p_day, p_kind, p_ref, p_payload_hash;
    return s;
  end if;
  lock table ripples.att_ledger in share row exclusive mode;
  prev := coalesce((select l.chain_hash from ripples.att_ledger l order by l.seq desc limit 1),
                   (select l.chain_hash from ripples.ledger l order by l.seq desc limit 1), repeat('0', 64));
  ch := encode(extensions.digest(prev || p_payload_hash, 'sha256'), 'hex');
  insert into ripples.att_ledger(day, kind, ref, payload_hash, prev_hash, chain_hash)
  values (p_day, p_kind, p_ref, p_payload_hash, prev, ch) returning seq into s;
  return s;
end $$;

-- ------------------------------------------------------------------ IO loader (render-only edges, never tested)
create or replace function ripples.att_load_io(p_rows jsonb, p_version text default 'v6.0') returns int
language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  insert into ripples.att_mech_edges(from_node, to_node, etype, prop, template, sign, strength, meta, version)
  select r->>'f', r->>'t', 'IO', null, nullif(r->>'tpl',''), 0, least(1, greatest(0.0001, (r->>'s')::real)),
         coalesce(r->'m', '{}'::jsonb) || '{"render_only": true, "never_test": true, "builder": "att_load_io"}'::jsonb, p_version
    from jsonb_array_elements(p_rows) r
   where r->>'f' ~ '^bea:' and (r->>'t' ~ '^bea:' or r->>'t' ~ '^hiringlab\.postings:')
  on conflict (from_node, to_node, etype, coalesce(prop, ''), coalesce(template, ''), version) do update
    set strength = excluded.strength, meta = excluded.meta, valid_to = null;
  get diagnostics n = row_count;
  return n;
end $$;

-- ------------------------------------------------------------------ att_build_graph (ENGINE §10.3)
-- Rebuilds MAP / MECH / WD edges of p_version from the templates, curated maps, att_series and the Wikidata cache.
-- Edges are upserted (valid_from kept; an edge that disappears gets valid_to = today instead of being deleted, so the
-- graph as of any past day stays reconstructable: WHERE valid_from <= t_u - 1 AND (valid_to IS NULL OR valid_to > t_u - 1)).
-- IO edges are loaded separately (att_load_io) and only hashed here. The graph hash (all live edges of the version),
-- the template hash and the prior-seed hash go to att_ledger (kind model_version) whenever the graph hash changes.
create or replace function ripples.att_build_graph(p_version text default 'v6.0') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_counts jsonb; v_hash text; v_tpl text; v_pri text; v_prev text; v_seq bigint := null; v_closed int; v_up int;
begin
  -- geography QIDs verified by their ISO 3166-2 claim once Wikidata has been fetched
  update ripples.att_geo_nodes g
     set qid_status = case when (c.claims->'P300') @> to_jsonb(array[g.geo]) then 'verified' else 'mismatch' end
    from ripples.att_wd_claims c
   where c.qid = g.qid and c.status = 'ok' and c.claims ? 'P300';

  drop table if exists pg_temp._g_nodes;
  create temp table _g_nodes on commit drop as select distinct source || ':' || key as node from ripples.att_series;
  create index on _g_nodes (node);
  drop table if exists pg_temp._e;
  create temp table _e (from_node text, to_node text, etype text, prop text, template text, sign smallint, strength real, meta jsonb) on commit drop;

  -- 1. MECH: static targets of each template
  insert into _e
  select 'family:' || t.family, n.node, 'MECH', null, t.template, t.sign, 1.0,
         jsonb_strip_nulls(jsonb_build_object('channel', t.channel, 'l_days', t.l_days, 'geo_filter', t.target_pattern->'geo_filter',
           'demean', t.target_pattern->>'demean', 'agg', t.target_pattern->>'agg', 'builder', 'att_build_graph'))
    from ripples.att_mech_templates t
    cross join lateral jsonb_array_elements_text(coalesce(t.target_pattern->'nodes', '[]'::jsonb)) n(node)
   where t.version = p_version;
  -- 1b. MECH: balancing-authority pattern, one edge per BA that owns a series (resolved per event through geo MAP edges)
  insert into _e
  select 'family:' || t.family, replace(t.target_pattern->>'pattern', '{BA}', b.ba), 'MECH', null, t.template, t.sign, 1.0,
         jsonb_strip_nulls(jsonb_build_object('channel', t.channel, 'l_days', t.l_days, 'geo_from', 'place_ba',
           'demean', t.target_pattern->>'demean', 'agg', t.target_pattern->>'agg', 'builder', 'att_build_graph'))
    from ripples.att_mech_templates t
    cross join (select distinct unnest(bas) ba from ripples.att_geo_nodes) b
   where t.version = p_version and t.target_pattern->>'pattern' like '%{BA}%'
     and exists (select 1 from _g_nodes x where x.node = replace(t.target_pattern->>'pattern', '{BA}', b.ba));
  -- 1c. MECH: state patterns ({ST})
  insert into _e
  select 'family:' || t.family, replace(p.pat, '{ST}', substr(g.geo, 4)), 'MECH', null, t.template, t.sign, 1.0,
         jsonb_strip_nulls(jsonb_build_object('channel', t.channel, 'l_days', t.l_days, 'geo_from', 'place_state',
           'demean', t.target_pattern->>'demean', 'agg', t.target_pattern->>'agg', 'builder', 'att_build_graph'))
    from ripples.att_mech_templates t
    cross join lateral (select t.target_pattern->>'pattern' as pat
                        union all select x from jsonb_array_elements_text(coalesce(t.target_pattern->'patterns', '[]'::jsonb)) x) p
    cross join ripples.att_geo_nodes g
   where t.version = p_version and p.pat like '%{ST}%'
     and exists (select 1 from _g_nodes x where x.node = replace(p.pat, '{ST}', substr(g.geo, 4)));

  -- 2. MAP: geography -> regional series
  insert into _e
  select 'geo:' || g.geo, 'eia.930:' || b.ba, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'state_ba', 'primary', b.ord = 1, 'builder', 'att_build_graph')
    from ripples.att_geo_nodes g cross join lateral unnest(g.bas) with ordinality b(ba, ord)
   where exists (select 1 from _g_nodes x where x.node = 'eia.930:' || b.ba);
  insert into _e
  select distinct on (s.geo, s.source, s.key) 'geo:' || s.geo, s.source || ':' || s.key, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'state_series', 'builder', 'att_build_graph')
    from ripples.att_series s
   where s.source in ('fred','dol.claims','noaa.ghcnd','census.bfs','fema.decl') and s.geo ~ '^US-[A-Z]{2}$'
     and s.geo in (select geo from ripples.att_geo_nodes);
  insert into _e
  select g.qid, 'geo:' || g.geo, 'MAP', 'P300', null, 0, 1.0,
         jsonb_build_object('kind', 'qid_geo', 'qid_status', g.qid_status, 'builder', 'att_build_graph')
    from ripples.att_geo_nodes g where g.qid ~ '^Q[0-9]+$' and g.qid_status <> 'mismatch';

  -- 3. MAP: topic -> its own outcome series (Polymarket / Kalshi markets, packages, repos, charts ...)
  insert into _e
  select distinct t.qid, s.source || ':' || s.key, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'topic_series', 'channel', src.engine_channel, 'builder', 'att_build_graph')
    from ripples.att_series s
    join ripples.att_topics t on t.topic_id = s.topic_id
    join ripples.att_sources src on src.source = s.source
    join ripples.att_channel_stat c on c.channel = src.engine_channel
   where c.kind = 'outcome' and t.qid ~ '^Q[0-9]+$';

  -- 4. MAP: industry crosswalks (NAICS -> CES series, NAICS -> Hiring Lab category, NAICS -> sector ETF, BEA -> NAICS)
  insert into _e
  select 'naics:' || n.n4, 'bls.ces:' || n.ces, 'MAP', null, null, 0, 1.0, jsonb_build_object('kind', 'naics_ces', 'builder', 'att_build_graph')
    from ripples.att_naics_ces n where exists (select 1 from _g_nodes x where x.node = 'bls.ces:' || n.ces);
  insert into _e
  select 'naics:' || m.prefix, 'hiringlab.postings:' || h.s, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'naics_hiringlab', 'curated', true, 'builder', 'att_build_graph')
    from ripples.att_naics_map m cross join lateral unnest(m.hl_sectors) h(s)
   where exists (select 1 from _g_nodes x where x.node = 'hiringlab.postings:' || h.s);
  insert into _e
  select 'naics:' || m.prefix, 'twelvedata:' || e.s, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'naics_etf', 'channel', 'MONEY', 'curated', true, 'builder', 'att_build_graph')
    from ripples.att_naics_map m cross join lateral unnest(m.etfs) e(s);
  insert into _e
  select distinct on (b.code) 'bea:' || b.code, 'naics:' || m.prefix, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'bea_naics', 'builder', 'att_build_graph')
    from (select distinct substr(from_node, 5) code from ripples.att_mech_edges where etype = 'IO' and from_node like 'bea:%') b
    join ripples.att_naics_map m on b.code like m.prefix || '%'
   order by b.code, length(m.prefix) desc;

  -- 5. Wikidata: WD edges (whitelisted QID-valued properties) and identifier MAP edges
  insert into _e
  select c.qid, v.val, 'WD', p.prop, null, 0, 0.6, jsonb_build_object('depth', c.depth, 'builder', 'att_build_graph')
    from ripples.att_wd_claims c
    cross join lateral jsonb_each(c.claims) p(prop, vals)
    join ripples.att_wd_props w on w.prop = p.prop and w.kind = 'wd'
    cross join lateral jsonb_array_elements_text(case when jsonb_typeof(p.vals) = 'array' then p.vals else '[]'::jsonb end) v(val)
   where c.status = 'ok' and v.val ~ '^Q[0-9]+$' and v.val <> c.qid;
  insert into _e   -- P414 stock exchange with P249 ticker qualifier, NYSE (Q13677) / Nasdaq (Q82059) only
  select distinct c.qid, 'twelvedata:' || upper(x->>'t'), 'MAP', 'P414', null, 0, 1.0,
         jsonb_build_object('kind', 'ticker', 'exchange', x->>'v', 'channel', 'MONEY', 'builder', 'att_build_graph')
    from ripples.att_wd_claims c cross join lateral jsonb_array_elements(case when jsonb_typeof(c.claims->'P414') = 'array' then c.claims->'P414' else '[]'::jsonb end) x
   where c.status = 'ok' and x->>'v' in ('Q13677','Q82059') and upper(x->>'t') ~ '^[A-Z][A-Z0-9.\-]{0,9}$';
  insert into _e
  select distinct c.qid, s.source || ':' || s.key, 'MAP', p.prop, null, 0, 1.0,
         jsonb_build_object('kind', 'identifier', 'builder', 'att_build_graph')
    from ripples.att_wd_claims c
    cross join lateral (values ('P1733', 'steamspy'), ('P8729', 'anilist')) p(prop, source)
    cross join lateral jsonb_array_elements_text(case when jsonb_typeof(c.claims->p.prop) = 'array' then c.claims->p.prop else '[]'::jsonb end) v(val)
    join ripples.att_series s on s.source = p.source and s.key = v.val
   where c.status = 'ok';
  insert into _e   -- P856 official website -> Tranco rank series of that registrable domain
  select distinct c.qid, s.source || ':' || s.key, 'MAP', 'P856', null, 0, 1.0, jsonb_build_object('kind', 'domain', 'builder', 'att_build_graph')
    from ripples.att_wd_claims c
    cross join lateral jsonb_array_elements_text(case when jsonb_typeof(c.claims->'P856') = 'array' then c.claims->'P856' else '[]'::jsonb end) v(val)
    join ripples.att_series s on s.source = 'tranco.rank'
     and s.key = regexp_replace(lower(substring(v.val from '^[a-z]+://([^/:?#]+)')), '^www\.', '')
   where c.status = 'ok';
  insert into _e   -- P452 industry -> Hiring Lab category / sector ETF by the industry item's English label (keyword map)
  select distinct c.qid, k.node, 'MAP', 'P452', null, 0, 1.0,
         jsonb_build_object('kind', 'industry_keyword', 'industry', i.qid, 'curated', true, 'builder', 'att_build_graph')
    from ripples.att_wd_claims c
    cross join lateral jsonb_array_elements_text(case when jsonb_typeof(c.claims->'P452') = 'array' then c.claims->'P452' else '[]'::jsonb end) v(val)
    join ripples.att_wd_claims i on i.qid = v.val and i.label_en is not null
    join (values
      ('software|computer program|saas|cloud comput', array['hiringlab.postings:software_development','twelvedata:IGV']),
      ('artificial intelligence|machine learning', array['hiringlab.postings:software_development','twelvedata:SMH']),
      ('semiconductor|integrated circuit|microchip', array['hiringlab.postings:electrical_engineering','twelvedata:SMH']),
      ('automotive|motor vehicle|car manufactur|electric vehicle', array['hiringlab.postings:mechanical_engineering','twelvedata:XLY']),
      ('airline|aviation|air transport', array['hiringlab.postings:aviation','twelvedata:JETS']),
      ('bank|financial service', array['hiringlab.postings:banking_and_finance','twelvedata:KRE']),
      ('insurance', array['hiringlab.postings:insurance','twelvedata:KIE']),
      ('petroleum|oil and gas|natural gas|oil industry', array['hiringlab.postings:installation_and_maintenance','twelvedata:XLE']),
      ('electric utility|electric power|electricity', array['hiringlab.postings:electrical_engineering','twelvedata:XLU']),
      ('retail|e-commerce|supermarket', array['hiringlab.postings:retail','twelvedata:XRT']),
      ('pharmaceutical|biotechnology|drug', array['hiringlab.postings:scientific_research_and_development','twelvedata:IBB']),
      ('film|entertainment|television|broadcast|mass media', array['hiringlab.postings:arts_and_entertainment','twelvedata:XLC']),
      ('restaurant|fast food|food service', array['hiringlab.postings:food_preparation_and_service','twelvedata:PEJ']),
      ('hotel|hospitality|tourism|travel', array['hiringlab.postings:hospitality_and_tourism','twelvedata:PEJ']),
      ('construction|homebuild|real estate development', array['hiringlab.postings:construction','twelvedata:ITB']),
      ('telecommunication', array['hiringlab.postings:it_infrastructure_operations_and_support','twelvedata:XLC']),
      ('health care|hospital|medical', array['hiringlab.postings:nursing','twelvedata:XLV']),
      ('mining|metal', array['hiringlab.postings:installation_and_maintenance','twelvedata:XME']),
      ('logistics|shipping|freight|trucking|delivery', array['hiringlab.postings:logistic_support','twelvedata:IYT']),
      ('social media|internet|social network', array['hiringlab.postings:software_development','twelvedata:XLC'])
    ) kw(pattern, nodes) on lower(i.label_en) ~ kw.pattern
    cross join lateral unnest(kw.nodes) k(node)
   where c.status = 'ok' and (k.node like 'twelvedata:%' or exists (select 1 from _g_nodes x where x.node = k.node));

  -- 6. upsert live edges; close edges the builder no longer produces
  insert into ripples.att_mech_edges(from_node, to_node, etype, prop, template, sign, strength, meta, version)
  select distinct on (from_node, to_node, etype, coalesce(prop, ''), coalesce(template, ''))
         from_node, to_node, etype, prop, template, sign, strength, meta, p_version
    from _e where from_node is not null and to_node is not null and from_node <> to_node
   order by from_node, to_node, etype, coalesce(prop, ''), coalesce(template, ''), strength desc
  on conflict (from_node, to_node, etype, coalesce(prop, ''), coalesce(template, ''), version) do update
    set sign = excluded.sign, strength = excluded.strength, meta = excluded.meta,
        valid_from = case when ripples.att_mech_edges.valid_to is not null then current_date else ripples.att_mech_edges.valid_from end,
        valid_to = null
   where ripples.att_mech_edges.valid_to is not null or ripples.att_mech_edges.meta is distinct from excluded.meta
      or ripples.att_mech_edges.sign is distinct from excluded.sign or ripples.att_mech_edges.strength is distinct from excluded.strength;
  get diagnostics v_up = row_count;
  update ripples.att_mech_edges m set valid_to = current_date
   where m.version = p_version and m.valid_to is null and m.etype in ('MAP','MECH','WD') and m.meta->>'builder' = 'att_build_graph'
     and not exists (select 1 from _e e where e.from_node = m.from_node and e.to_node = m.to_node and e.etype = m.etype
                        and coalesce(e.prop, '') = coalesce(m.prop, '') and coalesce(e.template, '') = coalesce(m.template, ''));
  get diagnostics v_closed = row_count;

  -- 7. counts, hashes, ledger
  select jsonb_object_agg(k, n) into v_counts from (
    select etype || coalesce('.' || (meta->>'kind'), '') k, count(*) n from ripples.att_mech_edges
     where version = p_version and valid_to is null group by 1) z;
  select encode(extensions.digest(coalesce(string_agg(from_node || '|' || to_node || '|' || etype || '|' || coalesce(prop, '') || '|'
           || coalesce(template, '') || '|' || sign || '|' || strength, E'\n'
           order by from_node, to_node, etype, coalesce(prop, ''), coalesce(template, '')), ''), 'sha256'), 'hex')
    into v_hash from ripples.att_mech_edges where version = p_version and valid_to is null;
  select encode(extensions.digest(coalesce(string_agg(template || '|' || family || '|' || target_pattern::text || '|' || sign || '|' || channel
           || '|' || coalesce(l_days::text, ''), E'\n' order by template), ''), 'sha256'), 'hex')
    into v_tpl from ripples.att_mech_templates where version = p_version;
  select encode(extensions.digest(coalesce(string_agg(etype || '|' || channel || '|' || family || '|' || prior, E'\n'
           order by etype, channel, family), ''), 'sha256'), 'hex')
    into v_pri from ripples.att_edge_priors where version = 'v6.0-seed';
  select v->>'graph_hash' into v_prev from ripples.att_state where k = 'graph.hash:' || p_version;
  if v_prev is distinct from v_hash then
    v_seq := ripples._att_ledger_append_wsa((now() at time zone 'utc')::date, 'model_version',
      jsonb_build_object('object', 'mech_graph', 'version', p_version, 'graph_hash', v_hash, 'templates_hash', v_tpl,
                         'priors_hash', v_pri, 'prior_cutoff', '2026-01-01', 'counts', v_counts), v_hash);
    insert into ripples.att_state(k, v) values ('graph.hash:' || p_version,
      jsonb_build_object('graph_hash', v_hash, 'templates_hash', v_tpl, 'priors_hash', v_pri, 'ledger_seq', v_seq, 'at', now(), 'counts', v_counts))
    on conflict (k) do update set v = excluded.v, updated_at = now();
  end if;
  return jsonb_build_object('version', p_version, 'upserted', v_up, 'closed', v_closed, 'counts', v_counts,
    'graph_hash', v_hash, 'templates_hash', v_tpl, 'priors_hash', v_pri, 'ledger_seq', v_seq,
    'ledger', case when v_seq is null then 'unchanged' else 'appended' end);
end $$;

-- public wrappers (service_role only) for att-wikidata / att-equities
create or replace function public.att_wd_queue(p_limit int default 80) returns jsonb
language sql stable security definer set search_path = '' as $$ select ripples.att_wd_queue(p_limit) $$;
create or replace function public.att_wd_claims_upsert(p_rows jsonb) returns int
language sql security definer set search_path = '' as $$ select ripples.att_wd_claims_upsert(p_rows) $$;
create or replace function public.att_equity_symbols(p_max int default 30) returns jsonb
language sql stable security definer set search_path = '' as $$ select ripples.att_equity_symbols(p_max) $$;
revoke all on function ripples.att_wd_queue(int), ripples.att_wd_claims_upsert(jsonb), ripples.att_equity_symbols(int),
  ripples._att_ledger_append_wsa(date, text, jsonb, text), ripples.att_load_io(jsonb, text), ripples.att_build_graph(text),
  public.att_wd_queue(int), public.att_wd_claims_upsert(jsonb), public.att_equity_symbols(int) from public, anon, authenticated;
grant execute on function public.att_wd_queue(int), public.att_wd_claims_upsert(jsonb), public.att_equity_symbols(int) to service_role;

-- ------------------------------------------------------------------ BEA 2017 detailed industries + compact IO loader
-- Data load (execute_sql, 2026-09-25): att_bea_industries from io_model.json (402 codes, names, sectors, in io_A.npy
-- order); IO edges = every a_ij >= 0.005 (i != j) of io_A.npy (7,531 edges, strength = a_ij, meta.a); route ideas = for
-- each industry j the top-5 suppliers k != j by the Leontief inverse (I - A)^-1 [k, j], mapped to a Hiring Lab category
-- through att_naics_map (2,000 edges after dropping routes with Leontief l < 0.001; 'bea:j' -> 'hiringlab.postings:<cat>', template 'route:bea:<k>', meta.route_idea).
-- All IO edges: meta.render_only = true, meta.never_test = true (ENGINE §2.1: IO generates no test; route ideas are
-- rendered as grey "hypothesis, not measured" text). Compact encoding: "i,k,a*1e4;..." and "j,k,l,rank,cat_idx;...".
create table if not exists ripples.att_bea_industries (
  idx int primary key, code text not null unique, name text not null, sector text
);
alter table ripples.att_bea_industries enable row level security;
revoke all on ripples.att_bea_industries from public, anon, authenticated;

create or replace function ripples.att_load_io_compact(p_io text, p_routes text, p_cats text, p_version text default 'v6.0') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n_io int := 0; n_rt int := 0; cats text[] := string_to_array(p_cats, ',');
begin
  if p_io is not null and p_io <> '' then
    insert into ripples.att_mech_edges(from_node, to_node, etype, sign, strength, meta, version)
    select 'bea:' || a.code, 'bea:' || b.code, 'IO', 0, split_part(x, ',', 3)::real / 10000,
           jsonb_build_object('a', split_part(x, ',', 3)::real / 10000, 'direction', 'supplier_to_buyer',
             'src', 'BEA 2017 detailed direct requirements', 'render_only', true, 'never_test', true, 'builder', 'att_load_io'),
           p_version
      from unnest(string_to_array(p_io, ';')) x
      join ripples.att_bea_industries a on a.idx = split_part(x, ',', 1)::int
      join ripples.att_bea_industries b on b.idx = split_part(x, ',', 2)::int
    on conflict (from_node, to_node, etype, coalesce(prop, ''), coalesce(template, ''), version) do update
      set strength = excluded.strength, meta = excluded.meta, valid_to = null;
    get diagnostics n_io = row_count;
  end if;
  if p_routes is not null and p_routes <> '' then
    insert into ripples.att_mech_edges(from_node, to_node, etype, template, sign, strength, meta, version)
    select 'bea:' || j.code, 'hiringlab.postings:' || cats[split_part(x, ',', 5)::int + 1], 'IO', 'route:bea:' || k.code, 0,
           least(1, split_part(x, ',', 3)::real),
           jsonb_build_object('route_idea', true, 'via', 'bea:' || k.code, 'via_label', k.name, 'label', j.name,
             'leontief', split_part(x, ',', 3)::real, 'rank', split_part(x, ',', 4)::int,
             'text', j.name || ' -> ' || k.name || ' (input-output link)', 'status', 'hypothesis, not measured',
             'src', 'BEA 2017 IO table, (I - A)^-1', 'render_only', true, 'never_test', true, 'builder', 'att_load_io'),
           p_version
      from unnest(string_to_array(p_routes, ';')) x
      join ripples.att_bea_industries j on j.idx = split_part(x, ',', 1)::int
      join ripples.att_bea_industries k on k.idx = split_part(x, ',', 2)::int
    on conflict (from_node, to_node, etype, coalesce(prop, ''), coalesce(template, ''), version) do update
      set strength = excluded.strength, meta = excluded.meta, valid_to = null;
    get diagnostics n_rt = row_count;
  end if;
  return jsonb_build_object('io', n_io, 'routes', n_rt);
end $$;
revoke all on function ripples.att_load_io_compact(text, text, text, text) from public, anon, authenticated;

-- =====================================================================================================================
-- Addendum (migration att_wsa_r2_graph, 2026-09-25 ~20:45 UTC) — verifier round 2 fixes (mechanism graph)
-- 1. No dead edges: MAP / MECH edges are built only to nodes that own >= 1 series of an ENABLED source. twelvedata
--    (robots Disallow /, disabled) therefore gets no edge; sector-ETF edges point at alphavantage:<ETF> where that
--    derived-z series exists (channel MONEY: inactive, never tested). bls.cpi_items edges appear once CPI series exist.
-- 2. No circular / duplicate targets: geo -> noaa.ghcnd MAP edges are dropped (NOAA station temperature DEFINES the
--    hazard.heat / hazard.cold library events; it is an upstream-shock source, never a tested outcome). State claims have
--    ONE target, fred.claims:<ST>ICLAIMS (first-release values); dol.claims (same DOL data, revised) is a cross-check
--    only, so the two can never count as two agreeing sources. quake_felt_reports is removed (USGS felt reports define
--    the quake library events).
-- 3. MONEY templates keep their rows (completeness, D-10) but get no WS-B primary key, so att_resolve_targets never
--    proposes a MONEY node while the channel is inactive.
-- 4. valid_from = knowable-from date. For MAP / MECH edges into series: the first observation day of the target
--    series (a Polymarket market or package that did not exist before day d is not an edge before d: no look-ahead when
--    the graph is read as of t_u - 1). Structural facts (state QID -> geo, BEA -> NAICS crosswalk) : 2015-07-01, the data
--    horizon of the project (meta.valid_from_basis = 'structural_fact'). WD edges keep their claim-fetch date. The first
--    build date is kept in meta.first_built. Templates were authored on 2026-09-25 (v6.0): applying them to past events
--    is a reconstruction (att_events.reconstructed = true, labelled on every surface), stated in meta.hindsight.
-- 5. Route ideas reachable from events: IO edges 'family:<family>' -> 'hiringlab.postings:<category>' (top-5 by the
--    Leontief weight over the family's directly exposed BEA industries, att_family_industries), render-only / never-test,
--    so WS-C's finalize (from_node in (qid, 'family:'||family)) finds them.
-- 6. Ledger: a model_version row is appended when the graph hash, the template hash OR the prior-seed hash changes
--    (before: graph hash only). The graph hash now includes valid_from.
-- 7. Counts separate MAP edges that reach an outcome series (map_into_series) from structural MAP edges.
delete from ripples.att_mech_templates where template = 'quake_felt_reports';
update ripples.att_mech_templates set target_pattern =
  '{"pattern":"fred.claims:{ST}ICLAIMS","geo_from":"place_state","demean":"aggregate","agg":"fred.claims:ICNSA"}'::jsonb
 where template in ('storm_claims', 'flood_claims');
update ripples.att_mech_templates set target_pattern =
  '{"nodes":["fred.weekly:GASREGW","fred:DJFUELUSGULF"],"geo_filter":["US-TX","US-LA","US-MS","US-AL","US-FL"]}'::jsonb
 where template = 'storm_gasoline';
update ripples.att_mech_templates t set target_pattern = jsonb_build_object('nodes', v.nodes::jsonb)
  from (values
    ('storm_insurers_equity', '["alphavantage:KIE","twelvedata:KIE"]'),
    ('storm_airlines_equity', '["alphavantage:JETS","twelvedata:JETS"]'),
    ('heat_utilities_equity', '["alphavantage:XLU","twelvedata:XLU","twelvedata:UNG"]'),
    ('model_release_semis_equity', '["alphavantage:SMH","twelvedata:SMH","twelvedata:IGV","twelvedata:XLK"]'),
    ('macro_release_banks_equity', '["alphavantage:KRE","twelvedata:KRE","twelvedata:XLF","twelvedata:SPY"]')) v(template, nodes)
 where t.template = v.template;

-- family mapper sync: MONEY templates get no primary key (never resolved while MONEY is inactive)
create or replace function ripples.att_family_sync(p_version text default 'v6.0') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare n_t int; n_f int;
begin
  update ripples.att_mech_templates t
     set target_pattern = (t.target_pattern - 'node' - 'node_pattern' - 'meta_key' - 'keys_from') || case
       when t.channel = 'MONEY' then '{}'::jsonb
       when coalesce((t.target_pattern->>'topic_keys')::boolean, false)
            and coalesce(t.target_pattern->>'source', t.target_pattern->'sources'->>0) is not null
         then jsonb_build_object('source', coalesce(t.target_pattern->>'source', t.target_pattern->'sources'->>0), 'keys_from', 'topic_keys')
       when jsonb_array_length(coalesce(t.target_pattern->'nodes', '[]'::jsonb)) > 0
         then jsonb_build_object('node', t.target_pattern->'nodes'->>0)
       when coalesce(t.target_pattern->>'pattern', t.target_pattern->'patterns'->>0) is not null
         then jsonb_build_object(
           'node_pattern', replace(replace(coalesce(t.target_pattern->>'pattern', t.target_pattern->'patterns'->>0), '{ST}', '{}'), '{BA}', '{}'),
           'meta_key', case when coalesce(t.target_pattern->>'pattern', t.target_pattern->'patterns'->>0) like '%{BA}%' then 'ba' else 'state' end)
       else '{}'::jsonb end
   where t.version = p_version;
  get diagnostics n_t = row_count;
  with t as (select * from ripples.att_mech_templates where version = p_version and channel <> 'MONEY'),
  pats as (
    select t.template, z.pat, z.i from t
    cross join lateral jsonb_array_elements_text(
      (case when t.target_pattern ? 'pattern' then jsonb_build_array(t.target_pattern->'pattern') else '[]'::jsonb end)
      || coalesce(t.target_pattern->'patterns', '[]'::jsonb)) with ordinality z(pat, i)),
  items as (
    select t.family, t.template, 1 ord, n.i,
           jsonb_strip_nulls(jsonb_build_object('node', n.node, 'sign', t.sign, 'template', t.template, 'geo_filter', t.target_pattern->'geo_filter')) item
      from t cross join lateral jsonb_array_elements_text(coalesce(t.target_pattern->'nodes', '[]'::jsonb)) with ordinality n(node, i)
     where n.node is distinct from t.target_pattern->>'node'
    union all
    select t.family, t.template, 2, p.i,
           jsonb_build_object('node_pattern', replace(replace(p.pat, '{ST}', '{}'), '{BA}', '{}'),
                              'meta_key', case when p.pat like '%{BA}%' then 'ba' else 'state' end, 'sign', t.sign, 'template', t.template)
      from t join pats p on p.template = t.template
     where replace(replace(p.pat, '{ST}', '{}'), '{BA}', '{}') is distinct from t.target_pattern->>'node_pattern'
    union all
    select t.family, t.template, 3, s.i,
           jsonb_build_object('source', s.src, 'keys_from', 'topic_keys', 'sign', t.sign, 'template', t.template)
      from t cross join lateral jsonb_array_elements_text(coalesce(t.target_pattern->'sources', '[]'::jsonb) || coalesce(t.target_pattern->'also', '[]'::jsonb))
             with ordinality s(src, i)
     where coalesce((t.target_pattern->>'topic_keys')::boolean, false) and s.src is distinct from t.target_pattern->>'source')
  update ripples.att_families f
     set mapper = coalesce((select jsonb_agg(item order by ord, template, i) from items where items.family = f.family), '[]'::jsonb)
   where f.family not in ('person', 'other');
  get diagnostics n_f = row_count;
  return jsonb_build_object('templates', n_t, 'families', n_f,
    'mapper_items', (select sum(jsonb_array_length(mapper)) from ripples.att_families));
end $$;

-- directly exposed BEA 2017 industries per family (curated) -> route ideas (render-only)
create table if not exists ripples.att_family_industries (
  family text not null, bea text not null, note text, primary key (family, bea)
);
alter table ripples.att_family_industries enable row level security;
revoke all on ripples.att_family_industries from public, anon, authenticated;
insert into ripples.att_family_industries(family, bea, note) values
 ('hazard.storm','481000','air transportation'), ('hazard.storm','5241XX','property and casualty insurance'),
 ('hazard.storm','221100','electric power'), ('hazard.storm','230301','nonresidential repair'),
 ('hazard.flood','5241XX','property and casualty insurance'), ('hazard.flood','230301','nonresidential repair'), ('hazard.flood','484000','trucking'),
 ('hazard.wildfire','113000','forestry and logging'), ('hazard.wildfire','5241XX','property and casualty insurance'), ('hazard.wildfire','221100','electric power'),
 ('hazard.heat','221100','electric power'), ('hazard.heat','221200','natural gas distribution'),
 ('hazard.cold','221200','natural gas distribution'), ('hazard.cold','221100','electric power'), ('hazard.cold','481000','air transportation'),
 ('hazard.quake','5241XX','property and casualty insurance'), ('hazard.quake','230301','nonresidential repair'),
 ('tech.model_release','518200','data processing and hosting'), ('tech.model_release','511200','software publishers'), ('tech.model_release','334413','semiconductors'),
 ('tech.software_release','511200','software publishers'), ('tech.software_release','541511','custom programming'),
 ('policy.macro_release','52A000','banking'), ('policy.macro_release','523A00','securities brokerage'),
 ('policy.decision','52A000','banking'), ('policy.decision','523A00','securities brokerage'),
 ('media.film','512100','motion pictures'), ('media.film','515100','broadcasting'),
 ('media.game','511200','software publishers'), ('media.game','713900','amusement and recreation'),
 ('media.series','515100','broadcasting'), ('media.series','512100','motion pictures')
on conflict (family, bea) do update set note = excluded.note;

create or replace function ripples.att_build_graph(p_version text default 'v6.0') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_counts jsonb; v_hash text; v_tpl text; v_pri text; v_prev jsonb; v_seq bigint := null; v_closed int; v_up int; v_vf int;
  v_into int; v_struct int;
begin
  update ripples.att_geo_nodes g
     set qid_status = case when (c.claims->'P300') @> to_jsonb(array[g.geo]) then 'verified' else 'mismatch' end
    from ripples.att_wd_claims c
   where c.qid = g.qid and c.status = 'ok' and c.claims ? 'P300';

  -- series nodes of ENABLED sources (an edge to a node without such a series is dead and is not built)
  drop table if exists pg_temp._g_nodes;
  create temp table _g_nodes on commit drop as
    select s.source || ':' || s.key as node, bool_or(src.engine_channel = 'MONEY') money
      from ripples.att_series s join ripples.att_sources src on src.source = s.source
     where src.enabled
     group by 1;
  create index on _g_nodes (node);
  drop table if exists pg_temp._e;
  create temp table _e (from_node text, to_node text, etype text, prop text, template text, sign smallint, strength real, meta jsonb) on commit drop;

  -- 1. MECH: static targets (with series)
  insert into _e
  select 'family:' || t.family, n.node, 'MECH', null, t.template, t.sign, 1.0,
         jsonb_strip_nulls(jsonb_build_object('channel', t.channel, 'l_days', t.l_days, 'geo_filter', t.target_pattern->'geo_filter',
           'demean', t.target_pattern->>'demean', 'agg', t.target_pattern->>'agg', 'builder', 'att_build_graph',
           'hindsight', 'template v6.0 authored 2026-09-25'))
    from ripples.att_mech_templates t
    cross join lateral jsonb_array_elements_text(coalesce(t.target_pattern->'nodes', '[]'::jsonb)) n(node)
   where t.version = p_version and exists (select 1 from _g_nodes x where x.node = n.node);
  -- 1b. MECH: balancing-authority pattern
  insert into _e
  select 'family:' || t.family, replace(t.target_pattern->>'pattern', '{BA}', b.ba), 'MECH', null, t.template, t.sign, 1.0,
         jsonb_strip_nulls(jsonb_build_object('channel', t.channel, 'l_days', t.l_days, 'geo_from', 'place_ba',
           'demean', t.target_pattern->>'demean', 'agg', t.target_pattern->>'agg', 'builder', 'att_build_graph',
           'hindsight', 'template v6.0 authored 2026-09-25'))
    from ripples.att_mech_templates t
    cross join (select distinct unnest(bas) ba from ripples.att_geo_nodes) b
   where t.version = p_version and t.target_pattern->>'pattern' like '%{BA}%'
     and exists (select 1 from _g_nodes x where x.node = replace(t.target_pattern->>'pattern', '{BA}', b.ba));
  -- 1c. MECH: state patterns ({ST})
  insert into _e
  select 'family:' || t.family, replace(p.pat, '{ST}', substr(g.geo, 4)), 'MECH', null, t.template, t.sign, 1.0,
         jsonb_strip_nulls(jsonb_build_object('channel', t.channel, 'l_days', t.l_days, 'geo_from', 'place_state',
           'demean', t.target_pattern->>'demean', 'agg', t.target_pattern->>'agg', 'builder', 'att_build_graph',
           'hindsight', 'template v6.0 authored 2026-09-25'))
    from ripples.att_mech_templates t
    cross join lateral (select t.target_pattern->>'pattern' as pat
                        union all select x from jsonb_array_elements_text(coalesce(t.target_pattern->'patterns', '[]'::jsonb)) x) p
    cross join ripples.att_geo_nodes g
   where t.version = p_version and p.pat like '%{ST}%'
     and exists (select 1 from _g_nodes x where x.node = replace(p.pat, '{ST}', substr(g.geo, 4)));

  -- 2. MAP: geography -> regional outcome series
  insert into _e
  select 'geo:' || g.geo, 'eia.930:' || b.ba, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'state_ba', 'channel', 'PHYS', 'primary', b.ord = 1, 'builder', 'att_build_graph')
    from ripples.att_geo_nodes g cross join lateral unnest(g.bas) with ordinality b(ba, ord)
   where exists (select 1 from _g_nodes x where x.node = 'eia.930:' || b.ba);
  insert into _e
  select distinct on (s.geo, s.source, s.key) 'geo:' || s.geo, s.source || ':' || s.key, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'state_series', 'channel', src.engine_channel, 'builder', 'att_build_graph')
    from ripples.att_series s join ripples.att_sources src on src.source = s.source
   where src.enabled and s.geo ~ '^US-[A-Z]{2}$' and s.geo in (select geo from ripples.att_geo_nodes)
     and ((s.source = 'fred.claims' and s.key ~ '^[A-Z]{2}ICLAIMS$')
          or (s.source = 'fema.decl' and s.key like 'st:%')
          or s.source in ('census.bfs', 'mta.ridership', 'citibike.trips'));
  insert into _e
  select g.qid, 'geo:' || g.geo, 'MAP', 'P300', null, 0, 1.0,
         jsonb_build_object('kind', 'qid_geo', 'structural', true, 'qid_status', g.qid_status, 'builder', 'att_build_graph')
    from ripples.att_geo_nodes g where g.qid ~ '^Q[0-9]+$' and g.qid_status <> 'mismatch';

  -- 3. MAP: topic -> its own outcome series (enabled sources, MONEY excluded)
  insert into _e
  select distinct t.qid, s.source || ':' || s.key, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'topic_series', 'channel', src.engine_channel, 'builder', 'att_build_graph')
    from ripples.att_series s
    join ripples.att_topics t on t.topic_id = s.topic_id
    join ripples.att_sources src on src.source = s.source
    join ripples.att_channel_stat c on c.channel = src.engine_channel
   where c.kind = 'outcome' and c.active and src.enabled and t.qid ~ '^Q[0-9]+$';

  -- 4. MAP: industry crosswalks
  insert into _e
  select 'naics:' || n.n4, 'bls.ces:' || n.ces, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'naics_ces', 'channel', 'JOBS', 'builder', 'att_build_graph')
    from ripples.att_naics_ces n where exists (select 1 from _g_nodes x where x.node = 'bls.ces:' || n.ces);
  insert into _e
  select 'naics:' || m.prefix, 'hiringlab.postings:' || h.s, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'naics_hiringlab', 'channel', 'JOBS', 'curated', true, 'builder', 'att_build_graph')
    from ripples.att_naics_map m cross join lateral unnest(m.hl_sectors) h(s)
   where exists (select 1 from _g_nodes x where x.node = 'hiringlab.postings:' || h.s);
  insert into _e
  select distinct 'naics:' || m.prefix, x.node, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'naics_etf', 'channel', 'MONEY', 'curated', true, 'builder', 'att_build_graph')
    from ripples.att_naics_map m cross join lateral unnest(m.etfs) e(s)
    join _g_nodes x on x.node in ('alphavantage:' || e.s, 'twelvedata:' || e.s);
  insert into _e
  select distinct on (b.code) 'bea:' || b.code, 'naics:' || m.prefix, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'bea_naics', 'structural', true, 'builder', 'att_build_graph')
    from (select distinct substr(from_node, 5) code from ripples.att_mech_edges where etype = 'IO' and from_node like 'bea:%') b
    join ripples.att_naics_map m on b.code like m.prefix || '%'
   order by b.code, length(m.prefix) desc;

  -- 5. Wikidata: WD edges and identifier MAP edges (identifier edges only to nodes with series)
  insert into _e
  select c.qid, v.val, 'WD', p.prop, null, 0, 0.6, jsonb_build_object('depth', c.depth, 'builder', 'att_build_graph')
    from ripples.att_wd_claims c
    cross join lateral jsonb_each(c.claims) p(prop, vals)
    join ripples.att_wd_props w on w.prop = p.prop and w.kind = 'wd'
    cross join lateral jsonb_array_elements_text(case when jsonb_typeof(p.vals) = 'array' then p.vals else '[]'::jsonb end) v(val)
   where c.status = 'ok' and v.val ~ '^Q[0-9]+$' and v.val <> c.qid;
  insert into _e
  select distinct c.qid, x.node, 'MAP', 'P414', null, 0, 1.0,
         jsonb_build_object('kind', 'ticker', 'exchange', t->>'v', 'channel', 'MONEY', 'builder', 'att_build_graph')
    from ripples.att_wd_claims c
    cross join lateral jsonb_array_elements(case when jsonb_typeof(c.claims->'P414') = 'array' then c.claims->'P414' else '[]'::jsonb end) t
    join _g_nodes x on x.node in ('alphavantage:' || upper(t->>'t'), 'twelvedata:' || upper(t->>'t'))
   where c.status = 'ok' and t->>'v' in ('Q13677','Q82059') and upper(t->>'t') ~ '^[A-Z][A-Z0-9.\-]{0,9}$';
  insert into _e
  select distinct c.qid, s.source || ':' || s.key, 'MAP', p.prop, null, 0, 1.0,
         jsonb_build_object('kind', 'identifier', 'builder', 'att_build_graph')
    from ripples.att_wd_claims c
    cross join lateral (values ('P1733', 'steamspy'), ('P8729', 'anilist')) p(prop, source)
    cross join lateral jsonb_array_elements_text(case when jsonb_typeof(c.claims->p.prop) = 'array' then c.claims->p.prop else '[]'::jsonb end) v(val)
    join ripples.att_series s on s.source = p.source and s.key = v.val
   where c.status = 'ok';
  insert into _e
  select distinct c.qid, s.source || ':' || s.key, 'MAP', 'P856', null, 0, 1.0, jsonb_build_object('kind', 'domain', 'builder', 'att_build_graph')
    from ripples.att_wd_claims c
    cross join lateral jsonb_array_elements_text(case when jsonb_typeof(c.claims->'P856') = 'array' then c.claims->'P856' else '[]'::jsonb end) v(val)
    join ripples.att_series s on s.source = 'tranco.rank'
     and s.key = regexp_replace(lower(substring(v.val from '^[a-z]+://([^/:?#]+)')), '^www\.', '')
   where c.status = 'ok';
  insert into _e
  select distinct c.qid, x.node, 'MAP', 'P452', null, 0, 1.0,
         jsonb_build_object('kind', 'industry_keyword', 'industry', i.qid, 'curated', true, 'builder', 'att_build_graph')
    from ripples.att_wd_claims c
    cross join lateral jsonb_array_elements_text(case when jsonb_typeof(c.claims->'P452') = 'array' then c.claims->'P452' else '[]'::jsonb end) v(val)
    join ripples.att_wd_claims i on i.qid = v.val and i.label_en is not null
    join (values
      ('software|computer program|saas|cloud comput', array['hiringlab.postings:software_development','IGV']),
      ('artificial intelligence|machine learning', array['hiringlab.postings:software_development','SMH']),
      ('semiconductor|integrated circuit|microchip', array['hiringlab.postings:electrical_engineering','SMH']),
      ('automotive|motor vehicle|car manufactur|electric vehicle', array['hiringlab.postings:mechanical_engineering','XLY']),
      ('airline|aviation|air transport', array['hiringlab.postings:aviation','JETS']),
      ('bank|financial service', array['hiringlab.postings:banking_and_finance','KRE']),
      ('insurance', array['hiringlab.postings:insurance','KIE']),
      ('petroleum|oil and gas|natural gas|oil industry', array['hiringlab.postings:installation_and_maintenance','XLE']),
      ('electric utility|electric power|electricity', array['hiringlab.postings:electrical_engineering','XLU']),
      ('retail|e-commerce|supermarket', array['hiringlab.postings:retail','XRT']),
      ('pharmaceutical|biotechnology|drug', array['hiringlab.postings:scientific_research_and_development','IBB']),
      ('film|entertainment|television|broadcast|mass media', array['hiringlab.postings:arts_and_entertainment','XLC']),
      ('restaurant|fast food|food service', array['hiringlab.postings:food_preparation_and_service','PEJ']),
      ('hotel|hospitality|tourism|travel', array['hiringlab.postings:hospitality_and_tourism','PEJ']),
      ('construction|homebuild|real estate development', array['hiringlab.postings:construction','ITB']),
      ('telecommunication', array['hiringlab.postings:it_infrastructure_operations_and_support','XLC']),
      ('health care|hospital|medical', array['hiringlab.postings:nursing','XLV']),
      ('mining|metal', array['hiringlab.postings:installation_and_maintenance','XME']),
      ('logistics|shipping|freight|trucking|delivery', array['hiringlab.postings:logistic_support','IYT']),
      ('social media|internet|social network', array['hiringlab.postings:software_development','XLC'])
    ) kw(pattern, nodes) on lower(i.label_en) ~ kw.pattern
    cross join lateral unnest(kw.nodes) k(n)
    join _g_nodes x on x.node in (k.n, 'alphavantage:' || k.n, 'twelvedata:' || k.n)
   where c.status = 'ok';

  -- 5b. IO route ideas reachable from the family node (render-only, never tested)
  insert into _e
  select from_node, to_node, 'IO', null, template, 0, strength, meta from (
    select 'family:' || fi.family from_node, r.to_node, 'route:family:' || fi.bea || '>' || coalesce(r.meta->>'via', r.template) template,
           r.strength,
           jsonb_build_object('route_idea', true, 'family_industry', 'bea:' || fi.bea, 'via', r.meta->>'via', 'leontief', r.meta->'leontief',
             'text', coalesce(r.meta->>'label', fi.bea) || ' -> ' || coalesce(r.meta->>'via_label', r.meta->>'via', '?') || ' (input-output link)',
             'status', 'hypothesis, not measured', 'src', 'BEA 2017 IO table, (I - A)^-1',
             'render_only', true, 'never_test', true, 'builder', 'att_build_graph') meta,
           row_number() over (partition by fi.family order by r.strength desc, r.to_node) rn,
           row_number() over (partition by fi.family, r.to_node order by r.strength desc) rn_to
      from ripples.att_family_industries fi
      join ripples.att_mech_edges r on r.from_node = 'bea:' || fi.bea and r.etype = 'IO' and r.valid_to is null
       and coalesce((r.meta->>'route_idea')::boolean, false) and r.meta->>'builder' = 'att_load_io') z
   where rn_to = 1;
  delete from _e e where e.etype = 'IO' and (e.from_node, e.to_node) not in (
    select from_node, to_node from (select from_node, to_node, row_number() over (partition by from_node order by strength desc, to_node) rn
                                      from _e where etype = 'IO') q where rn <= 5);

  -- 6. upsert live edges; close edges the builder no longer produces (MAP / MECH / WD / its own IO route ideas)
  insert into ripples.att_mech_edges(from_node, to_node, etype, prop, template, sign, strength, meta, version)
  select distinct on (from_node, to_node, etype, coalesce(prop, ''), coalesce(template, ''))
         from_node, to_node, etype, prop, template, sign, strength, meta, p_version
    from _e where from_node is not null and to_node is not null and from_node <> to_node
   order by from_node, to_node, etype, coalesce(prop, ''), coalesce(template, ''), strength desc
  on conflict (from_node, to_node, etype, coalesce(prop, ''), coalesce(template, ''), version) do update
    set sign = excluded.sign, strength = excluded.strength,
        meta = excluded.meta || jsonb_strip_nulls(jsonb_build_object('first_built', ripples.att_mech_edges.meta->'first_built',
                                                                     'valid_from_basis', ripples.att_mech_edges.meta->'valid_from_basis')),
        valid_from = case when ripples.att_mech_edges.valid_to is not null then current_date else ripples.att_mech_edges.valid_from end,
        valid_to = null
   where ripples.att_mech_edges.valid_to is not null
      or (ripples.att_mech_edges.meta - 'first_built' - 'valid_from_basis') is distinct from excluded.meta
      or ripples.att_mech_edges.sign is distinct from excluded.sign or ripples.att_mech_edges.strength is distinct from excluded.strength;
  get diagnostics v_up = row_count;
  update ripples.att_mech_edges m set valid_to = current_date
   where m.version = p_version and m.valid_to is null and m.etype in ('MAP','MECH','WD','IO') and m.meta->>'builder' = 'att_build_graph'
     and not exists (select 1 from _e e where e.from_node = m.from_node and e.to_node = m.to_node and e.etype = m.etype
                        and coalesce(e.prop, '') = coalesce(m.prop, '') and coalesce(e.template, '') = coalesce(m.template, ''));
  get diagnostics v_closed = row_count;

  -- 7. valid_from = knowable-from date (see header). first_built keeps the first build day.
  drop table if exists pg_temp._fo;
  create temp table _fo on commit drop as
    select s.source || ':' || s.key node, min(f.d) d
      from ripples.att_series s
      cross join lateral (select o.day d from ripples.attention_obs o where o.series_id = s.series_id order by o.day limit 1) f
     where (s.source || ':' || s.key) in (select to_node from ripples.att_mech_edges
                                            where version = p_version and valid_to is null and etype in ('MAP','MECH') and meta->>'builder' = 'att_build_graph')
     group by 1;
  update ripples.att_mech_edges m
     set valid_from = f.d,
         meta = m.meta || jsonb_build_object('valid_from_basis', 'target_first_obs', 'first_built', coalesce(m.meta->>'first_built', m.valid_from::text))
    from _fo f
   where m.version = p_version and m.valid_to is null and m.etype in ('MAP','MECH') and m.meta->>'builder' = 'att_build_graph'
     and f.node = m.to_node and (m.valid_from is distinct from f.d or m.meta->>'valid_from_basis' is null);
  get diagnostics v_vf = row_count;
  update ripples.att_mech_edges m
     set valid_from = date '2015-07-01',
         meta = m.meta || jsonb_build_object('valid_from_basis', 'structural_fact', 'first_built', coalesce(m.meta->>'first_built', m.valid_from::text))
   where m.version = p_version and m.valid_to is null and m.etype = 'MAP' and m.meta->>'builder' = 'att_build_graph'
     and coalesce((m.meta->>'structural')::boolean, false) and m.meta->>'valid_from_basis' is null;
  update ripples.att_mech_edges m
     set meta = m.meta || jsonb_build_object('valid_from_basis', 'claim_fetch_date', 'first_built', coalesce(m.meta->>'first_built', m.valid_from::text))
   where m.version = p_version and m.valid_to is null and m.etype = 'WD' and m.meta->>'valid_from_basis' is null;

  -- 8. counts, hashes, ledger
  select jsonb_object_agg(k, n) into v_counts from (
    select etype || coalesce('.' || (meta->>'kind'), '') k, count(*) n from ripples.att_mech_edges
     where version = p_version and valid_to is null group by 1) z;
  select count(*) filter (where m.etype = 'MAP' and not coalesce((m.meta->>'structural')::boolean, false)
                            and coalesce(m.meta->>'channel', '') <> 'MONEY' and exists (select 1 from _g_nodes x where x.node = m.to_node)),
         count(*) filter (where m.etype = 'MAP' and coalesce((m.meta->>'structural')::boolean, false))
    into v_into, v_struct
    from ripples.att_mech_edges m where m.version = p_version and m.valid_to is null;
  v_counts := v_counts || jsonb_build_object('map_into_series', v_into, 'map_structural', v_struct);
  select encode(extensions.digest(coalesce(string_agg(from_node || '|' || to_node || '|' || etype || '|' || coalesce(prop, '') || '|'
           || coalesce(template, '') || '|' || sign || '|' || strength || '|' || valid_from, E'\n'
           order by from_node, to_node, etype, coalesce(prop, ''), coalesce(template, '')), ''), 'sha256'), 'hex')
    into v_hash from ripples.att_mech_edges where version = p_version and valid_to is null;
  select encode(extensions.digest(coalesce(string_agg(template || '|' || family || '|' || target_pattern::text || '|' || sign || '|' || channel
           || '|' || coalesce(l_days::text, ''), E'\n' order by template), ''), 'sha256'), 'hex')
    into v_tpl from ripples.att_mech_templates where version = p_version;
  select encode(extensions.digest(coalesce(string_agg(etype || '|' || channel || '|' || family || '|' || prior, E'\n'
           order by etype, channel, family), ''), 'sha256'), 'hex')
    into v_pri from ripples.att_edge_priors where version = 'v6.0-seed';
  select v into v_prev from ripples.att_state where k = 'graph.hash:' || p_version;
  if v_prev is null or v_prev->>'graph_hash' is distinct from v_hash or v_prev->>'templates_hash' is distinct from v_tpl
     or v_prev->>'priors_hash' is distinct from v_pri then
    v_seq := ripples._att_ledger_append_wsa((now() at time zone 'utc')::date, 'model_version',
      jsonb_build_object('object', 'mech_graph', 'version', p_version, 'graph_hash', v_hash, 'templates_hash', v_tpl,
                         'priors_hash', v_pri, 'prior_cutoff', '2026-01-01', 'counts', v_counts,
                         'hash_formula', 'sha256 over live edges: from|to|etype|prop|template|sign|strength|valid_from, ordered'),
      encode(extensions.digest(v_hash || '|' || v_tpl || '|' || v_pri, 'sha256'), 'hex'));
    insert into ripples.att_state(k, v) values ('graph.hash:' || p_version,
      jsonb_build_object('graph_hash', v_hash, 'templates_hash', v_tpl, 'priors_hash', v_pri, 'ledger_seq', v_seq, 'at', now(), 'counts', v_counts))
    on conflict (k) do update set v = excluded.v, updated_at = now();
  end if;
  return jsonb_build_object('version', p_version, 'upserted', v_up, 'closed', v_closed, 'valid_from_set', v_vf, 'counts', v_counts,
    'graph_hash', v_hash, 'templates_hash', v_tpl, 'priors_hash', v_pri, 'ledger_seq', v_seq,
    'ledger', case when v_seq is null then 'unchanged' else 'appended' end);
end $$;
revoke all on function ripples.att_build_graph(text), ripples.att_family_sync(text) from public, anon, authenticated;

-- equities watch list: P414 ticker edges now point at equity nodes with series; keep the legacy function shape
create or replace function ripples.att_equity_symbols(p_max int default 30) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(t order by t), '[]'::jsonb) from (
    select distinct split_part(to_node, ':', 2) t from ripples.att_mech_edges
     where etype = 'MAP' and valid_to is null and prop = 'P414' and (to_node like 'twelvedata:%' or to_node like 'alphavantage:%')
     order by 1 limit greatest(0, least(p_max, 60))) z;
$$;

-- =====================================================================================================================
-- Addendum (migration att_wsa_r3_graph, 2026-09-25 ~21:30 UTC) — verifier round 3 fixes (look-ahead, preregistration)
-- 1. valid_from = REGISTRATION date, never back-dated. Round 2 set valid_from on MAP / MECH edges to the target series'
--    first observation (MECH as early as 2016-01-01) although every v6.0 template and map was written on 2026-09-25
--    with the library and positive-control events visible; ENGINE §3.9 linkage ("a MECH / MAP edge registered before
--    onset") would then pass for every historical event by construction. Now: valid_from = the day the edge entered the
--    live graph (insert default current_date; the reopen day for an edge that was closed and comes back), for MAP, MECH
--    and WD alike (structural facts included). meta.first_built = first registration day; meta.data_from = first
--    observation of the target (informational only); meta.evidence states the consequence. Every library / control /
--    backtest result for an event with onset <= valid_from is RETROSPECTIVE.
-- 2. Preregistration cutoff (att_state 'prereg:<version>'): the day the current template set AND the current library
--    selection rules (SQL function sources + _att_library_rules(), which records the att-library TS thresholds) were
--    registered. It moves to the current day whenever either hash changes (att_prereg_check, called by att_build_graph
--    and att_library_sweep). att_family_events (trigger, see 19_att_families.sql r3): in_replication_set = library event
--    with onset > cutoff (prospective); the 126 events with onset in [prior_cutoff, cutoff] move to in_retro_holdout
--    ("held out from the prior fit, NOT preregistered"); evidence_mode = retrospective | prospective.
-- 3. att_mech_edges_asof(day, version): the graph as it was registered on a day (valid_from <= day and not yet closed),
--    for WS-B's freeze (t_u - 1).
-- 4. MAP naics_price (curated att_naics_price): an industry -> the price series of its own output (CPI item indexes,
--    FRED energy prices). Built only to series that exist; CPI edges appear when the CPI drain lands.

create table if not exists ripples.att_naics_price (
  prefix text primary key, nodes text[] not null, note text not null
);
alter table ripples.att_naics_price enable row level security;
revoke all on ripples.att_naics_price from public, anon, authenticated;
insert into ripples.att_naics_price(prefix, nodes, note) values
 ('11',  array['bls.cpi_items:CUSR0000SAF113','bls.cpi_items:CUUR0000SAF113','bls.cpi_items:CUSR0000SAF112','bls.cpi_items:CUUR0000SAF112'], 'farm output -> CPI fruits & vegetables, meats/poultry/fish/eggs'),
 ('21',  array['fred:DCOILWTICO'], 'mining, oil and gas -> WTI crude spot'),
 ('211', array['fred:DCOILWTICO','fred:DCOILBRENTEU','fred:DHHNGSP','bls.cpi_items:CUSR0000SEHE','bls.cpi_items:CUUR0000SEHE'], 'oil and gas extraction -> crude / Henry Hub spot, CPI fuel oil'),
 ('22',  array['bls.cpi_items:CUSR0000SEHF','bls.cpi_items:CUUR0000SEHF','bls.cpi_items:CUSR0000SEHF01','bls.cpi_items:CUUR0000SEHF01','bls.cpi_items:CUSR0000SEHF02','bls.cpi_items:CUUR0000SEHF02','bls.cpi_items:CUSR0000SEHG','bls.cpi_items:CUUR0000SEHG'], 'utilities -> CPI energy services, electricity, piped gas, water/sewer/trash'),
 ('31',  array['bls.cpi_items:CUSR0000SAF11','bls.cpi_items:CUUR0000SAF11','bls.cpi_items:CUSR0000SAF116','bls.cpi_items:CUUR0000SAF116','bls.cpi_items:CUSR0000SAA','bls.cpi_items:CUUR0000SAA'], 'food, beverage, textile manufacturing -> CPI food at home, alcoholic beverages, apparel'),
 ('324', array['bls.cpi_items:CUSR0000SETB01','bls.cpi_items:CUUR0000SETB01','bls.cpi_items:CUSR0000SS47014','bls.cpi_items:CUUR0000SS47014','bls.cpi_items:CUSR0000SEHE','bls.cpi_items:CUUR0000SEHE','fred.weekly:GASREGW','fred.weekly:GASDESW','fred:DJFUELUSGULF'], 'petroleum refining -> CPI gasoline, fuel oil; retail gasoline / diesel; Gulf Coast jet fuel'),
 ('334', array['bls.cpi_items:CUSR0000SEEE01','bls.cpi_items:CUUR0000SEEE01','bls.cpi_items:CUSR0000SERA01','bls.cpi_items:CUUR0000SERA01'], 'computer and electronic products -> CPI computers, televisions'),
 ('336', array['bls.cpi_items:CUSR0000SETA01','bls.cpi_items:CUUR0000SETA01','bls.cpi_items:CUSR0000SETC','bls.cpi_items:CUUR0000SETC'], 'transportation equipment -> CPI new vehicles, vehicle parts'),
 ('44',  array['bls.cpi_items:CUSR0000SETA01','bls.cpi_items:CUUR0000SETA01','bls.cpi_items:CUSR0000SETA02','bls.cpi_items:CUUR0000SETA02','bls.cpi_items:CUSR0000SAF11','bls.cpi_items:CUUR0000SAF11'], 'retail (vehicle dealers, food stores) -> CPI new / used vehicles, food at home'),
 ('481', array['bls.cpi_items:CUSR0000SETG01','bls.cpi_items:CUUR0000SETG01'], 'air transportation -> CPI airline fares'),
 ('524', array['bls.cpi_items:CUSR0000SETE','bls.cpi_items:CUUR0000SETE'], 'insurance -> CPI motor vehicle insurance'),
 ('53',  array['bls.cpi_items:CUSR0000SAH1','bls.cpi_items:CUUR0000SAH1','bls.cpi_items:CUSR0000SEHA','bls.cpi_items:CUUR0000SEHA','bls.cpi_items:CUSR0000SEHC','bls.cpi_items:CUUR0000SEHC'], 'real estate and rental -> CPI shelter, rent, owners'' equivalent rent'),
 ('61',  array['bls.cpi_items:CUSR0000SEEB01','bls.cpi_items:CUUR0000SEEB01'], 'educational services -> CPI college tuition'),
 ('62',  array['bls.cpi_items:CUSR0000SAM','bls.cpi_items:CUUR0000SAM'], 'health care -> CPI medical care'),
 ('621', array['bls.cpi_items:CUSR0000SEMC01','bls.cpi_items:CUUR0000SEMC01'], 'ambulatory care -> CPI physicians'' services'),
 ('622', array['bls.cpi_items:CUSR0000SEMD','bls.cpi_items:CUUR0000SEMD'], 'hospitals -> CPI hospital services'),
 ('71',  array['bls.cpi_items:CUSR0000SAR','bls.cpi_items:CUUR0000SAR'], 'arts, entertainment, recreation -> CPI recreation'),
 ('721', array['bls.cpi_items:CUSR0000SEHB','bls.cpi_items:CUUR0000SEHB'], 'accommodation -> CPI lodging away from home'),
 ('722', array['bls.cpi_items:CUSR0000SEFV','bls.cpi_items:CUUR0000SEFV'], 'food services -> CPI food away from home'),
 ('811', array['bls.cpi_items:CUSR0000SETD','bls.cpi_items:CUUR0000SETD'], 'repair and maintenance -> CPI vehicle maintenance and repair'),
 ('812', array['bls.cpi_items:CUSR0000SAG1','bls.cpi_items:CUUR0000SAG1'], 'personal services -> CPI personal care')
on conflict (prefix) do update set nodes = excluded.nodes, note = excluded.note;

-- library selection rules that live in the att-library edge function (TS). Bump 'version' whenever that code changes.
create or replace function ripples._att_library_rules() returns jsonb
language sql immutable set search_path = '' as $$
  select '{"version":"lib-rules-2026-09-25.r3","fema":"DisasterDeclarationsSummaries by year; FEMA incident type -> family; same (type,title) with begin dates within 7 days = one event; named storms -> storm-<name>-<year>","usgs":"felt reports >= 1000, 2019+","gdacs":"storm events, 2019+","noaa_extremes":"att_library_noaa_extremes (SQL)","macro":"att_library_macro (SQL calendar)","curated":"att_library_curated (SQL, 68 dates, not verified against primary sources)","control_twin":"att_control_overlap (SQL): same family, onset within 14 days and shared state, or same storm name and year within 30 days","prior_cutoff":"2026-01-01"}'::jsonb
$$;

create or replace function ripples.att_prereg_cutoff(p_version text default 'v6.0') returns date
language sql stable security definer set search_path = '' as $$
  select coalesce((select (v->>'cutoff')::date from ripples.att_state where k = 'prereg:' || p_version),
                  (now() at time zone 'utc')::date)
$$;

-- moves the preregistration cutoff to today when the template set or the library selection rules changed
create or replace function ripples.att_prereg_check(p_version text default 'v6.0') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_tpl text; v_rules text; v_prev jsonb; v_day date := (now() at time zone 'utc')::date; n int := 0;
begin
  select encode(extensions.digest(coalesce(string_agg(template || '|' || family || '|' || target_pattern::text || '|' || sign || '|' || channel
           || '|' || coalesce(l_days::text, ''), E'\n' order by template), ''), 'sha256'), 'hex')
    into v_tpl from ripples.att_mech_templates where version = p_version;
  select encode(extensions.digest(ripples._att_library_rules()::text || E'\n' || coalesce(string_agg(p.proname || ':' || md5(p.prosrc), E'\n' order by p.proname), ''), 'sha256'), 'hex')
    into v_rules
    from pg_proc p join pg_namespace n2 on n2.oid = p.pronamespace
   where n2.nspname = 'ripples' and p.proname in ('att_library_upsert', 'att_library_recluster_storms', 'att_library_noaa_extremes',
                                                   'att_library_macro', 'att_library_curated', 'att_control_overlap', 'att_storm_name',
                                                   'att_lib_defined_by', 'att_proposing_channels', 'att_family_target_sources');
  select v into v_prev from ripples.att_state where k = 'prereg:' || p_version;
  if v_prev is null or v_prev->>'templates_hash' is distinct from v_tpl or v_prev->>'rules_hash' is distinct from v_rules then
    insert into ripples.att_state(k, v) values ('prereg:' || p_version,
      jsonb_build_object('cutoff', v_day, 'templates_hash', v_tpl, 'rules_hash', v_rules, 'rules', ripples._att_library_rules(),
        'set_at', now(), 'previous_cutoff', v_prev->'cutoff',
        'meaning', 'events with onset > cutoff are prospective (templates and library selection rules fixed before onset); onset <= cutoff is retrospective'))
    on conflict (k) do update set v = excluded.v, updated_at = now();
    update ripples.att_family_events set onset = onset;  -- trigger recomputes the sets against the new cutoff
    get diagnostics n = row_count;
    return jsonb_build_object('cutoff', v_day, 'moved', true, 'family_events_reflagged', n);
  end if;
  return jsonb_build_object('cutoff', v_prev->>'cutoff', 'moved', false);
end $$;

create or replace function ripples.att_mech_edges_asof(p_day date, p_version text default 'v6.0')
returns setof ripples.att_mech_edges
language sql stable security definer set search_path = '' as $$
  select * from ripples.att_mech_edges m
   where m.version = p_version and m.valid_from <= p_day and (m.valid_to is null or m.valid_to > p_day)
$$;
revoke all on function ripples._att_library_rules(), ripples.att_prereg_cutoff(text), ripples.att_prereg_check(text),
  ripples.att_mech_edges_asof(date, text) from public, anon, authenticated;

-- att_build_graph r3 (applied as migration att_wsa_r3_build_graph: a DO block patching the r2 body hunk by hunk; the
-- resulting definition is exactly this one, minus comments, which the migration tool strips).
create or replace function ripples.att_build_graph(p_version text default 'v6.0') returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_counts jsonb; v_hash text; v_tpl text; v_pri text; v_prev jsonb; v_seq bigint := null; v_closed int; v_up int; v_vf int;
  v_into int; v_struct int; v_pre jsonb;
begin
  update ripples.att_geo_nodes g
     set qid_status = case when (c.claims->'P300') @> to_jsonb(array[g.geo]) then 'verified' else 'mismatch' end
    from ripples.att_wd_claims c
   where c.qid = g.qid and c.status = 'ok' and c.claims ? 'P300';

  -- series nodes of ENABLED sources (an edge to a node without such a series is dead and is not built)
  drop table if exists pg_temp._g_nodes;
  create temp table _g_nodes on commit drop as
    select s.source || ':' || s.key as node, bool_or(src.engine_channel = 'MONEY') money
      from ripples.att_series s join ripples.att_sources src on src.source = s.source
     where src.enabled
     group by 1;
  create index on _g_nodes (node);
  drop table if exists pg_temp._e;
  create temp table _e (from_node text, to_node text, etype text, prop text, template text, sign smallint, strength real, meta jsonb) on commit drop;

  -- 1. MECH: static targets (with series)
  insert into _e
  select 'family:' || t.family, n.node, 'MECH', null, t.template, t.sign, 1.0,
         jsonb_strip_nulls(jsonb_build_object('channel', t.channel, 'l_days', t.l_days, 'geo_filter', t.target_pattern->'geo_filter',
           'demean', t.target_pattern->>'demean', 'agg', t.target_pattern->>'agg', 'builder', 'att_build_graph',
           'hindsight', 'template v6.0 authored 2026-09-25 with the library and control events visible'))
    from ripples.att_mech_templates t
    cross join lateral jsonb_array_elements_text(coalesce(t.target_pattern->'nodes', '[]'::jsonb)) n(node)
   where t.version = p_version and exists (select 1 from _g_nodes x where x.node = n.node);
  -- 1b. MECH: balancing-authority pattern
  insert into _e
  select 'family:' || t.family, replace(t.target_pattern->>'pattern', '{BA}', b.ba), 'MECH', null, t.template, t.sign, 1.0,
         jsonb_strip_nulls(jsonb_build_object('channel', t.channel, 'l_days', t.l_days, 'geo_from', 'place_ba',
           'demean', t.target_pattern->>'demean', 'agg', t.target_pattern->>'agg', 'builder', 'att_build_graph',
           'hindsight', 'template v6.0 authored 2026-09-25 with the library and control events visible'))
    from ripples.att_mech_templates t
    cross join (select distinct unnest(bas) ba from ripples.att_geo_nodes) b
   where t.version = p_version and t.target_pattern->>'pattern' like '%{BA}%'
     and exists (select 1 from _g_nodes x where x.node = replace(t.target_pattern->>'pattern', '{BA}', b.ba));
  -- 1c. MECH: state patterns ({ST})
  insert into _e
  select 'family:' || t.family, replace(p.pat, '{ST}', substr(g.geo, 4)), 'MECH', null, t.template, t.sign, 1.0,
         jsonb_strip_nulls(jsonb_build_object('channel', t.channel, 'l_days', t.l_days, 'geo_from', 'place_state',
           'demean', t.target_pattern->>'demean', 'agg', t.target_pattern->>'agg', 'builder', 'att_build_graph',
           'hindsight', 'template v6.0 authored 2026-09-25 with the library and control events visible'))
    from ripples.att_mech_templates t
    cross join lateral (select t.target_pattern->>'pattern' as pat
                        union all select x from jsonb_array_elements_text(coalesce(t.target_pattern->'patterns', '[]'::jsonb)) x) p
    cross join ripples.att_geo_nodes g
   where t.version = p_version and p.pat like '%{ST}%'
     and exists (select 1 from _g_nodes x where x.node = replace(p.pat, '{ST}', substr(g.geo, 4)));

  -- 2. MAP: geography -> regional outcome series
  insert into _e
  select 'geo:' || g.geo, 'eia.930:' || b.ba, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'state_ba', 'channel', 'PHYS', 'primary', b.ord = 1, 'builder', 'att_build_graph')
    from ripples.att_geo_nodes g cross join lateral unnest(g.bas) with ordinality b(ba, ord)
   where exists (select 1 from _g_nodes x where x.node = 'eia.930:' || b.ba);
  insert into _e
  select distinct on (s.geo, s.source, s.key) 'geo:' || s.geo, s.source || ':' || s.key, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'state_series', 'channel', src.engine_channel, 'builder', 'att_build_graph')
    from ripples.att_series s join ripples.att_sources src on src.source = s.source
   where src.enabled and s.geo ~ '^US-[A-Z]{2}$' and s.geo in (select geo from ripples.att_geo_nodes)
     and ((s.source = 'fred.claims' and s.key ~ '^[A-Z]{2}ICLAIMS$')
          or (s.source = 'fema.decl' and s.key like 'st:%')
          or s.source in ('census.bfs', 'mta.ridership', 'citibike.trips'));
  insert into _e
  select g.qid, 'geo:' || g.geo, 'MAP', 'P300', null, 0, 1.0,
         jsonb_build_object('kind', 'qid_geo', 'structural', true, 'qid_status', g.qid_status, 'builder', 'att_build_graph')
    from ripples.att_geo_nodes g where g.qid ~ '^Q[0-9]+$' and g.qid_status <> 'mismatch';

  -- 3. MAP: topic -> its own outcome series (enabled sources, MONEY excluded)
  insert into _e
  select distinct t.qid, s.source || ':' || s.key, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'topic_series', 'channel', src.engine_channel, 'builder', 'att_build_graph')
    from ripples.att_series s
    join ripples.att_topics t on t.topic_id = s.topic_id
    join ripples.att_sources src on src.source = s.source
    join ripples.att_channel_stat c on c.channel = src.engine_channel
   where c.kind = 'outcome' and c.active and src.enabled and t.qid ~ '^Q[0-9]+$';

  -- 4. MAP: industry crosswalks
  insert into _e
  select 'naics:' || n.n4, 'bls.ces:' || n.ces, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'naics_ces', 'channel', 'JOBS', 'builder', 'att_build_graph')
    from ripples.att_naics_ces n where exists (select 1 from _g_nodes x where x.node = 'bls.ces:' || n.ces);
  insert into _e
  select 'naics:' || m.prefix, 'hiringlab.postings:' || h.s, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'naics_hiringlab', 'channel', 'JOBS', 'curated', true, 'builder', 'att_build_graph')
    from ripples.att_naics_map m cross join lateral unnest(m.hl_sectors) h(s)
   where exists (select 1 from _g_nodes x where x.node = 'hiringlab.postings:' || h.s);
  insert into _e
  select distinct 'naics:' || m.prefix, x.node, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'naics_etf', 'channel', 'MONEY', 'curated', true, 'builder', 'att_build_graph')
    from ripples.att_naics_map m cross join lateral unnest(m.etfs) e(s)
    join _g_nodes x on x.node in ('alphavantage:' || e.s, 'twelvedata:' || e.s);
  insert into _e
  select distinct on (b.code) 'bea:' || b.code, 'naics:' || m.prefix, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'bea_naics', 'structural', true, 'builder', 'att_build_graph')
    from (select distinct substr(from_node, 5) code from ripples.att_mech_edges where etype = 'IO' and from_node like 'bea:%') b
    join ripples.att_naics_map m on b.code like m.prefix || '%'
   order by b.code, length(m.prefix) desc;

  -- 4b. MAP: industry -> price series of its output (curated, att_naics_price; only to series that exist)
  insert into _e
  select distinct 'naics:' || p.prefix, x.node, 'MAP', null, null, 0, 1.0,
         jsonb_build_object('kind', 'naics_price', 'channel', src.engine_channel, 'curated', true, 'note', p.note, 'builder', 'att_build_graph')
    from ripples.att_naics_price p
    join _g_nodes x on x.node = any(p.nodes)
    join ripples.att_sources src on src.source = split_part(x.node, ':', 1)
   where not x.money;

  -- 5. Wikidata: WD edges and identifier MAP edges (identifier edges only to nodes with series)
  insert into _e
  select c.qid, v.val, 'WD', p.prop, null, 0, 0.6, jsonb_build_object('depth', c.depth, 'builder', 'att_build_graph')
    from ripples.att_wd_claims c
    cross join lateral jsonb_each(c.claims) p(prop, vals)
    join ripples.att_wd_props w on w.prop = p.prop and w.kind = 'wd'
    cross join lateral jsonb_array_elements_text(case when jsonb_typeof(p.vals) = 'array' then p.vals else '[]'::jsonb end) v(val)
   where c.status = 'ok' and v.val ~ '^Q[0-9]+$' and v.val <> c.qid;
  insert into _e
  select distinct c.qid, x.node, 'MAP', 'P414', null, 0, 1.0,
         jsonb_build_object('kind', 'ticker', 'exchange', t->>'v', 'channel', 'MONEY', 'builder', 'att_build_graph')
    from ripples.att_wd_claims c
    cross join lateral jsonb_array_elements(case when jsonb_typeof(c.claims->'P414') = 'array' then c.claims->'P414' else '[]'::jsonb end) t
    join _g_nodes x on x.node in ('alphavantage:' || upper(t->>'t'), 'twelvedata:' || upper(t->>'t'))
   where c.status = 'ok' and t->>'v' in ('Q13677','Q82059') and upper(t->>'t') ~ '^[A-Z][A-Z0-9.\-]{0,9}$';
  insert into _e
  select distinct c.qid, s.source || ':' || s.key, 'MAP', p.prop, null, 0, 1.0,
         jsonb_build_object('kind', 'identifier', 'builder', 'att_build_graph')
    from ripples.att_wd_claims c
    cross join lateral (values ('P1733', 'steamspy'), ('P8729', 'anilist')) p(prop, source)
    cross join lateral jsonb_array_elements_text(case when jsonb_typeof(c.claims->p.prop) = 'array' then c.claims->p.prop else '[]'::jsonb end) v(val)
    join ripples.att_series s on s.source = p.source and s.key = v.val
   where c.status = 'ok';
  insert into _e
  select distinct c.qid, s.source || ':' || s.key, 'MAP', 'P856', null, 0, 1.0, jsonb_build_object('kind', 'domain', 'builder', 'att_build_graph')
    from ripples.att_wd_claims c
    cross join lateral jsonb_array_elements_text(case when jsonb_typeof(c.claims->'P856') = 'array' then c.claims->'P856' else '[]'::jsonb end) v(val)
    join ripples.att_series s on s.source = 'tranco.rank'
     and s.key = regexp_replace(lower(substring(v.val from '^[a-z]+://([^/:?#]+)')), '^www\.', '')
   where c.status = 'ok';
  insert into _e
  select distinct c.qid, x.node, 'MAP', 'P452', null, 0, 1.0,
         jsonb_build_object('kind', 'industry_keyword', 'industry', i.qid, 'curated', true, 'builder', 'att_build_graph')
    from ripples.att_wd_claims c
    cross join lateral jsonb_array_elements_text(case when jsonb_typeof(c.claims->'P452') = 'array' then c.claims->'P452' else '[]'::jsonb end) v(val)
    join ripples.att_wd_claims i on i.qid = v.val and i.label_en is not null
    join (values
      ('software|computer program|saas|cloud comput', array['hiringlab.postings:software_development','IGV']),
      ('artificial intelligence|machine learning', array['hiringlab.postings:software_development','SMH']),
      ('semiconductor|integrated circuit|microchip', array['hiringlab.postings:electrical_engineering','SMH']),
      ('automotive|motor vehicle|car manufactur|electric vehicle', array['hiringlab.postings:mechanical_engineering','XLY']),
      ('airline|aviation|air transport', array['hiringlab.postings:aviation','JETS']),
      ('bank|financial service', array['hiringlab.postings:banking_and_finance','KRE']),
      ('insurance', array['hiringlab.postings:insurance','KIE']),
      ('petroleum|oil and gas|natural gas|oil industry', array['hiringlab.postings:installation_and_maintenance','XLE']),
      ('electric utility|electric power|electricity', array['hiringlab.postings:electrical_engineering','XLU']),
      ('retail|e-commerce|supermarket', array['hiringlab.postings:retail','XRT']),
      ('pharmaceutical|biotechnology|drug', array['hiringlab.postings:scientific_research_and_development','IBB']),
      ('film|entertainment|television|broadcast|mass media', array['hiringlab.postings:arts_and_entertainment','XLC']),
      ('restaurant|fast food|food service', array['hiringlab.postings:food_preparation_and_service','PEJ']),
      ('hotel|hospitality|tourism|travel', array['hiringlab.postings:hospitality_and_tourism','PEJ']),
      ('construction|homebuild|real estate development', array['hiringlab.postings:construction','ITB']),
      ('telecommunication', array['hiringlab.postings:it_infrastructure_operations_and_support','XLC']),
      ('health care|hospital|medical', array['hiringlab.postings:nursing','XLV']),
      ('mining|metal', array['hiringlab.postings:installation_and_maintenance','XME']),
      ('logistics|shipping|freight|trucking|delivery', array['hiringlab.postings:logistic_support','IYT']),
      ('social media|internet|social network', array['hiringlab.postings:software_development','XLC'])
    ) kw(pattern, nodes) on lower(i.label_en) ~ kw.pattern
    cross join lateral unnest(kw.nodes) k(n)
    join _g_nodes x on x.node in (k.n, 'alphavantage:' || k.n, 'twelvedata:' || k.n)
   where c.status = 'ok';

  -- 5b. IO route ideas reachable from the family node (render-only, never tested)
  insert into _e
  select from_node, to_node, 'IO', null, template, 0, strength, meta from (
    select 'family:' || fi.family from_node, r.to_node, 'route:family:' || fi.bea || '>' || coalesce(r.meta->>'via', r.template) template,
           r.strength,
           jsonb_build_object('route_idea', true, 'family_industry', 'bea:' || fi.bea, 'via', r.meta->>'via', 'leontief', r.meta->'leontief',
             'text', coalesce(r.meta->>'label', fi.bea) || ' -> ' || coalesce(r.meta->>'via_label', r.meta->>'via', '?') || ' (input-output link)',
             'status', 'hypothesis, not measured', 'src', 'BEA 2017 IO table, (I - A)^-1',
             'render_only', true, 'never_test', true, 'builder', 'att_build_graph') meta,
           row_number() over (partition by fi.family order by r.strength desc, r.to_node) rn,
           row_number() over (partition by fi.family, r.to_node order by r.strength desc) rn_to
      from ripples.att_family_industries fi
      join ripples.att_mech_edges r on r.from_node = 'bea:' || fi.bea and r.etype = 'IO' and r.valid_to is null
       and coalesce((r.meta->>'route_idea')::boolean, false) and r.meta->>'builder' = 'att_load_io') z
   where rn_to = 1;
  delete from _e e where e.etype = 'IO' and (e.from_node, e.to_node) not in (
    select from_node, to_node from (select from_node, to_node, row_number() over (partition by from_node order by strength desc, to_node) rn
                                      from _e where etype = 'IO') q where rn <= 5);

  -- 6. upsert live edges; close edges the builder no longer produces (MAP / MECH / WD / its own IO route ideas)
  insert into ripples.att_mech_edges(from_node, to_node, etype, prop, template, sign, strength, meta, version)
  select distinct on (from_node, to_node, etype, coalesce(prop, ''), coalesce(template, ''))
         from_node, to_node, etype, prop, template, sign, strength, meta, p_version
    from _e where from_node is not null and to_node is not null and from_node <> to_node
   order by from_node, to_node, etype, coalesce(prop, ''), coalesce(template, ''), strength desc
  on conflict (from_node, to_node, etype, coalesce(prop, ''), coalesce(template, ''), version) do update
    set sign = excluded.sign, strength = excluded.strength,
        meta = excluded.meta || jsonb_strip_nulls(jsonb_build_object('first_built', ripples.att_mech_edges.meta->'first_built',
                                                                     'valid_from_basis', ripples.att_mech_edges.meta->'valid_from_basis',
                                                                     'data_from', ripples.att_mech_edges.meta->'data_from',
                                                                     'evidence', ripples.att_mech_edges.meta->'evidence')),
        valid_from = case when ripples.att_mech_edges.valid_to is not null then current_date else ripples.att_mech_edges.valid_from end,
        valid_to = null
   where ripples.att_mech_edges.valid_to is not null
      or (ripples.att_mech_edges.meta - 'first_built' - 'valid_from_basis' - 'data_from' - 'evidence') is distinct from excluded.meta
      or ripples.att_mech_edges.sign is distinct from excluded.sign or ripples.att_mech_edges.strength is distinct from excluded.strength;
  get diagnostics v_up = row_count;
  update ripples.att_mech_edges m set valid_to = current_date
   where m.version = p_version and m.valid_to is null and m.etype in ('MAP','MECH','WD','IO') and m.meta->>'builder' = 'att_build_graph'
     and not exists (select 1 from _e e where e.from_node = m.from_node and e.to_node = m.to_node and e.etype = m.etype
                        and coalesce(e.prop, '') = coalesce(m.prop, '') and coalesce(e.template, '') = coalesce(m.template, ''));
  get diagnostics v_closed = row_count;

  -- 7. valid_from = REGISTRATION date (round 3): the day the edge entered the live graph (column default current_date on
  --    insert; the reopen day when a closed edge comes back). It is never back-dated. meta.first_built keeps the first
  --    registration day, meta.data_from the first observation day of the target series (informational only: it says when
  --    the target data existed, not when the mechanism was registered). An event with onset before valid_from can only be
  --    a retrospective (hindsight) test; ENGINE §3.9 "registered before onset" holds only for onset > valid_from.
  drop table if exists pg_temp._fo;
  create temp table _fo on commit drop as
    select s.source || ':' || s.key node, min(f.d) d
      from ripples.att_series s
      cross join lateral (select o.day d from ripples.attention_obs o where o.series_id = s.series_id order by o.day limit 1) f
     where (s.source || ':' || s.key) in (select to_node from ripples.att_mech_edges
                                            where version = p_version and valid_to is null and etype in ('MAP','MECH') and meta->>'builder' = 'att_build_graph')
     group by 1;
  update ripples.att_mech_edges m
     set meta = m.meta || jsonb_build_object('data_from', f.d)
    from _fo f
   where m.version = p_version and m.valid_to is null and m.etype in ('MAP','MECH') and m.meta->>'builder' = 'att_build_graph'
     and f.node = m.to_node and m.meta->>'data_from' is distinct from f.d::text;
  update ripples.att_mech_edges m
     set meta = m.meta || jsonb_build_object('valid_from_basis', 'registered',
                  'first_built', coalesce(m.meta->>'first_built', m.valid_from::text),
                  'evidence', 'registered ' || m.valid_from || ' (v6.0 templates / maps authored 2026-09-25 with the library and control '
                              || 'events visible): a test of an event with onset <= valid_from is retrospective, never "registered before onset"')
   where m.version = p_version and m.valid_to is null and m.etype in ('MAP','MECH','WD') and m.meta->>'builder' = 'att_build_graph'
     and (m.meta->>'valid_from_basis' is distinct from 'registered' or m.meta->>'evidence' not like 'registered ' || m.valid_from || ' %');
  get diagnostics v_vf = row_count;

  -- 8. counts, hashes, ledger
  select jsonb_object_agg(k, n) into v_counts from (
    select etype || coalesce('.' || (meta->>'kind'), '') k, count(*) n from ripples.att_mech_edges
     where version = p_version and valid_to is null group by 1) z;
  select count(*) filter (where m.etype = 'MAP' and not coalesce((m.meta->>'structural')::boolean, false)
                            and coalesce(m.meta->>'channel', '') <> 'MONEY' and exists (select 1 from _g_nodes x where x.node = m.to_node)),
         count(*) filter (where m.etype = 'MAP' and coalesce((m.meta->>'structural')::boolean, false))
    into v_into, v_struct
    from ripples.att_mech_edges m where m.version = p_version and m.valid_to is null;
  v_counts := v_counts || jsonb_build_object('map_into_series', v_into, 'map_structural', v_struct);
  select encode(extensions.digest(coalesce(string_agg(from_node || '|' || to_node || '|' || etype || '|' || coalesce(prop, '') || '|'
           || coalesce(template, '') || '|' || sign || '|' || strength || '|' || valid_from, E'\n'
           order by from_node, to_node, etype, coalesce(prop, ''), coalesce(template, '')), ''), 'sha256'), 'hex')
    into v_hash from ripples.att_mech_edges where version = p_version and valid_to is null;
  select encode(extensions.digest(coalesce(string_agg(template || '|' || family || '|' || target_pattern::text || '|' || sign || '|' || channel
           || '|' || coalesce(l_days::text, ''), E'\n' order by template), ''), 'sha256'), 'hex')
    into v_tpl from ripples.att_mech_templates where version = p_version;
  select encode(extensions.digest(coalesce(string_agg(etype || '|' || channel || '|' || family || '|' || prior, E'\n'
           order by etype, channel, family), ''), 'sha256'), 'hex')
    into v_pri from ripples.att_edge_priors where version = 'v6.0-seed';
  select v into v_prev from ripples.att_state where k = 'graph.hash:' || p_version;
  if v_prev is null or v_prev->>'graph_hash' is distinct from v_hash or v_prev->>'templates_hash' is distinct from v_tpl
     or v_prev->>'priors_hash' is distinct from v_pri then
    v_seq := ripples._att_ledger_append_wsa((now() at time zone 'utc')::date, 'model_version',
      jsonb_build_object('object', 'mech_graph', 'version', p_version, 'graph_hash', v_hash, 'templates_hash', v_tpl,
                         'priors_hash', v_pri, 'prior_cutoff', '2026-01-01', 'counts', v_counts,
                         'hash_formula', 'sha256 over live edges: from|to|etype|prop|template|sign|strength|valid_from, ordered',
                         'valid_from_basis', 'registered'),
      encode(extensions.digest(v_hash || '|' || v_tpl || '|' || v_pri, 'sha256'), 'hex'));
    insert into ripples.att_state(k, v) values ('graph.hash:' || p_version,
      jsonb_build_object('graph_hash', v_hash, 'templates_hash', v_tpl, 'priors_hash', v_pri, 'ledger_seq', v_seq, 'at', now(), 'counts', v_counts))
    on conflict (k) do update set v = excluded.v, updated_at = now();
  end if;
  v_pre := ripples.att_prereg_check(p_version);
  return jsonb_build_object('version', p_version, 'prereg', v_pre, 'upserted', v_up, 'closed', v_closed, 'registration_meta_set', v_vf, 'counts', v_counts,
    'graph_hash', v_hash, 'templates_hash', v_tpl, 'priors_hash', v_pri, 'ledger_seq', v_seq,
    'ledger', case when v_seq is null then 'unchanged' else 'appended' end);
end $$;
revoke all on function ripples.att_build_graph(text) from public, anon, authenticated;

-- One-off statements run on 2026-09-25 ~20:50 UTC after the r3 migrations (execute_sql):
--   update ripples.att_mech_edges m set valid_from = (m.meta->>'first_built')::date
--    where m.version = 'v6.0' and m.meta->>'builder' = 'att_build_graph' and m.etype in ('MAP','MECH','WD')
--      and m.meta->>'first_built' ~ '^\d{4}-\d{2}-\d{2}$' and m.valid_from is distinct from (m.meta->>'first_built')::date;
--      -> 1,516 edges moved from back-dated valid_from (2015-07-01 .. 2026-09-24) to their registration day 2026-09-25
--   select ripples.att_prereg_check('v6.0');   -> cutoff 2026-09-25, 1,241 family events re-flagged
--   select ripples.att_family_sync('v6.0'), ripples.att_build_graph('v6.0');   -> ledger seq 463, graph hash bf0c3937...
