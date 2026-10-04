# Sources pass v1

**What it covers.** `ripples/tools/build_sources.py` writes `ripples/demo/sources.json`: one real source link per step, keyed chain slug → step number → `{url, label}`. Testers rejected "Search Wikipedia" links; the demo shows "not linked yet" where no real link exists, and this pass supplies the links.

**Inputs.** (a) The `wiki` hint on steps in `ripples/chains/*.json` becomes a direct Wikipedia article link. (b) A hand-written `CURATED` table in the script overrides the hints for the most-viewed stories. `tiger-king` renders as a ripple map, so it is keyed by step index in `ripples/maps/out/tiger-king.json` (0 = the release), not by chain step number; the hint pass skips that slug.

**The rule.** One link per step. Prefer the Wikipedia article for the exact thing the step names (an Act, a case, a person, an organization, an event). Use an official page only where the URL pattern is certain (congress.gov bills, NIAAA surveillance reports, SSA baby names, Gallup, CDC BRFSS, Monitoring the Future, anchorit.gov). If the title or URL is not certain, leave the step out. No invented DOIs or deep links.

**Counts (steps linked).** america-and-alcohol 23, mr-bates-horizon 9, squid-game-ripples 8, daily-show-zadroga 6, octopus-sentience 6, cathy-come-home 5, quincy-orphan-drug 5, silent-spring-ddt 5, sixty-minutes-stock-act 5, tambora-bicycle 5, tiger-king 5 (map), planet-earth 4, frozen 2. Hints alone cover 16 more chains. Total: 116 links, 29 chains.

**Caveat.** No network access during this pass: every URL was written from knowledge, not fetched. A reviewer should click through the top stories once before launch, especially the five congress.gov links and the Act-titled Wikipedia articles.

**Held back.** legislation.gov.uk chapter numbers (Horizon Offences Act 2024, Sentience Act 2022, Housing Act 1977): not certain, Wikipedia used instead. Hansard, Pew, Bloomberg, Netflix, NCHS, FDA and the Surgeon General's advisory: no certain deep link, so those steps got the nearest Wikipedia subject or nothing.

## Verification (Oct 4, 2026, 03:40 UTC, after the environment allowed the hosts)

Every link was fetched once with the project's user agent, one request per second.

| Result | Count |
|---|---|
| Resolved (HTTP 200) | 139 |
| Wrong Wikipedia title (404), corrected or dropped | 7 |
| Not checked by us: the site answers 403 to our agent (congress.gov ×6, ssa.gov, monitoringthefuture.org) | 8 |

The seven: "Housing (Homeless Persons) Act 1977" (no article; now the Act on legislation.gov.uk, ukpga/1977/48, title confirmed), "Motor Vehicle Manufacturers Ass'n v. State Farm" (the article is "Motor Vehicles Manufacturers Ass'n …", corrected), and five with no article at all, dropped from the links and from the chains' `wiki` hints so the attention check does not look for them either: ALERRT, the Factory Investigating Commission, the Neill–Reynolds Report, the STURDY Act, the Soil Conservation Act of 1935. While at it, the Sentience Act 2022 (ukpga/2022/22) and the Post Office (Horizon System) Offences Act 2024 (ukpga/2024/14) now link the Act itself on legislation.gov.uk, titles confirmed. Two Wikipedia links redirect harmlessly (iPhone 7 capitalization; the Gallup home page). Total after the pass: 185 links. The eight unchecked links use each site's canonical URL pattern; a person should click them once.

## The statutes themselves (Oct 4, 2026, 05:40 UTC)

Twenty-two law steps in the US catalog now link to the statute on govinfo rather than to an encyclopedia article about it. The link service `govinfo.gov/link/statute/{volume}/{page}` resolves a Statutes at Large cite to the page scan; `link/plaw/{congress}/public/{number}` resolves a public law from the 104th Congress on (the 103rd and earlier return 400).

How each link was confirmed, with the honest `ripples-research/0.2` user agent and one request a second:

- **Fourteen, by text.** For volumes from 1951 on the scan carries a text layer. The PDF the cite resolves to was fetched and its first page searched for "Public Law N-M"; all fourteen matched (85-325, 85-568, 85-864, 89-563, 91-605, 102-240, 91-190, 91-604, 92-500, 96-510, 99-499, 101-380, 103-354, 109-2). Pub. L. 117-58 is the one public-law link; it resolves to `PLAW-117publ58.pdf`, whose name is the law.
- **Seven, by page structure.** Volumes 34, 49 and 52 (1906, 1935, 1938) are scans whose text layer is not readable. For those the check is that govinfo's granule begins at the cited page (34 Stat. 768, 49 Stat. 163, 49 Stat. 620, 49 Stat. 1148, 52 Stat. 1040, 52 Stat. 1060), or, for the Meat Inspection Act, that 34 Stat. 674 falls inside the Agriculture appropriations act of June 30, 1906 that begins at page 669, which is where that act lives. A later CI pass can confirm their titles through the govinfo API with the `DATA_GOV_KEY` secret; this container's shared demo key is rate-limited.
- **Seven Stat. pages were supplied** where the chain file cited only the public law (74-461, 103-354, 85-325, 91-605, 102-240, 92-500, 99-499). Each was confirmed as above before it was linked.

Not linked: Pub. L. 99-509 on the Exxon Valdez "spill" step (the step is the spill, not the fund), and Pub. L. 89-564 (shares a step with 89-563). UK Acts already link to legislation.gov.uk.
