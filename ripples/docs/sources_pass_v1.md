# Sources pass v1

**What it covers.** `ripples/tools/build_sources.py` writes `ripples/demo/sources.json`: one real source link per step, keyed chain slug → step number → `{url, label}`. Testers rejected "Search Wikipedia" links; the demo shows "not linked yet" where no real link exists, and this pass supplies the links.

**Inputs.** (a) The `wiki` hint on steps in `ripples/chains/*.json` becomes a direct Wikipedia article link. (b) A hand-written `CURATED` table in the script overrides the hints for the most-viewed stories. `tiger-king` renders as a ripple map, so it is keyed by step index in `ripples/maps/out/tiger-king.json` (0 = the release), not by chain step number; the hint pass skips that slug.

**The rule.** One link per step. Prefer the Wikipedia article for the exact thing the step names (an Act, a case, a person, an organization, an event). Use an official page only where the URL pattern is certain (congress.gov bills, NIAAA surveillance reports, SSA baby names, Gallup, CDC BRFSS, Monitoring the Future, anchorit.gov). If the title or URL is not certain, leave the step out. No invented DOIs or deep links.

**Counts (steps linked).** america-and-alcohol 23, mr-bates-horizon 9, squid-game-ripples 8, daily-show-zadroga 6, octopus-sentience 6, cathy-come-home 5, quincy-orphan-drug 5, silent-spring-ddt 5, sixty-minutes-stock-act 5, tambora-bicycle 5, tiger-king 5 (map), planet-earth 4, frozen 2. Hints alone cover 16 more chains. Total: 116 links, 29 chains.

**Caveat.** No network access during this pass: every URL was written from knowledge, not fetched. A reviewer should click through the top stories once before launch, especially the five congress.gov links and the Act-titled Wikipedia articles.

**Held back.** legislation.gov.uk chapter numbers (Horizon Offences Act 2024, Sentience Act 2022, Housing Act 1977): not certain, Wikipedia used instead. Hansard, Pew, Bloomberg, Netflix, NCHS, FDA and the Surgeon General's advisory: no certain deep link, so those steps got the nearest Wikipedia subject or nothing.
