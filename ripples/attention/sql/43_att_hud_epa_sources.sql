-- 43: register the two county sources fetched from GitHub Actions (.github/workflows/ripples-hud-epa.yml,
-- ripples/tools/gov/hud_epa.py). huduser.gov answers 400 and aqs.epa.gov times out for every request from the Supabase
-- network, so these cannot be collected with pg_net. Keys live in GitHub secrets (HUD_USER_TOKEN, EPA_AQS_KEY,
-- EPA_AQS_EMAIL); copies are in Vault (hud_user_token, epa_aqs_key, epa_aqs_email).
-- Geography: geo 'US-CTY-<5-digit FIPS>', key = FIPS, so state panels (geo ~ '^US-[A-Z]{2}$') never mix counties in.
insert into ripples.att_sources(source, family, channel, tier, grade, grain, value_kind, enabled, quality, policy_d1, hosts, spacing_ms, per_run_cap, history_from, needs_secret, robots_required, engine_channel, attribution, license_note, reason)
values
 ('epa.aqi', 'epa', 'institutional', 'ship', 'green', 'week', 'level', true, 1, false, array['aqs.epa.gov'], 1000, 1, '2010-01-01', null, true, null,
  'U.S. Environmental Protection Agency, AirData: daily AQI by county', 'Public domain (U.S. government); cite EPA AirData',
  'County weekly max/mean AQI (GitHub Actions job ripples-hud-epa; aqs.epa.gov refuses the Supabase network). Wildfire smoke and other air-quality ripples.'),
 ('hud.fmr', 'hud', 'institutional', 'ship', 'green', 'month', 'level', true, 1, false, array['www.huduser.gov'], 300, 1, '2016-10-01', 'hud_user_token', true, null,
  'U.S. Department of Housing and Urban Development, HUD USER Fair Market Rents API', 'Public domain (U.S. government); cite HUD USER',
  'County 2-bedroom Fair Market Rent per fiscal year, one value dated at the FY start (grain month is the coarsest allowed). GitHub Actions job ripples-hud-epa; huduser.gov refuses the Supabase network. Model-based and annual: a slow housing-cost signal.')
on conflict (source) do nothing;
