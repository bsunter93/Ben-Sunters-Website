# Study-backed ripples, second batch (Oct 9, 2026)

## What this is

The discovery v4 pilot (`docs/discovery_plan_v4.md`, plan sha256 `b90dbbd6...0cced69`) rated 26 finds good: surprising
and defensible on a simulated panel. This batch turns the ones that hold up into stories. Seven ship, in
`chains/batch19.json`, under Engine leads in the group "From published studies", built the same way as the first batch
(`docs/studies_v1.md`): a stone, then the study's own result as a `study` step graded by the paper's design.

## How a find was chosen

- **In:** a peer-reviewed journal paper whose design compares against a baseline (a control group, the days around an
  event, a cutoff). Graded Measured.
- **In, with a label:** a working paper from an established series (NBER, SSRN with a named university author, IZA,
  CEPR, IDE-JETRO), with a clear quasi-experimental design and a stated effect size. None passed this time, so no card
  carries the working-paper label yet.
- **Out:** the BMJ Christmas-issue Doctor Who paper; bioRxiv and medRxiv preprints with health claims; theses; a stone
  that doesn't come before the outcome; suicide, self-harm, overdose and party-vote outcomes; anything already live.
- **Re-verified:** every included find was checked again against its own source on Oct 9: the PubMed abstract, the
  publisher's abstract page, or an open copy of the paper. Each story quotes one sentence that carries the effect, and
  its stone date and effect size match the source. Requests used the user agent `ripple-research (bensunter.com)`, one a
  second per host at most, and a host was stopped for the day on any 4xx or 5xx (www.pnas.org returned 403 and was
  stopped; the pilot's own stops for Oct 9 were honored).
- **A line, later:** a find whose paper gives yearly or monthly values that could draw a real line waits for a build
  that draws it, so no data is invented for a chart.

## What ships

| # | Story | Paper | Effect | Slug |
|---|---|---|---|---|
| 1 | Album release days → more traffic deaths | JAMA Network Open, 2026 (10.1001/jamanetworkopen.2026.29282) | 18.2 more US traffic deaths on an average release day, +15.1% | `study-album-traffic` |
| 2 | European football losses → protests in Africa | International Organization, 2023 (10.1017/S0020818322000261) | more peaceful protests after a close loss than a draw; no change in riots | `study-football-protests` |
| 3 | Stockholm truck attack → fewer ER visits | Scandinavian Journal of Trauma, Resuscitation and Emergency Medicine, 2019 (10.1186/s13049-019-0634-2) | 7% to 9% fewer emergency visits for about three weeks | `study-stockholm-er` |
| 4 | Catalonia attacks → more low-birth-weight babies | Journal of Health Economics, 2021 (10.1016/j.jhealeco.2021.102510) | +23.77% low birth weight among mothers from Muslim countries in the towns attacked | `study-catalonia-birthweight` |
| 5 | Broadband in Senegal → more kids under bednets | Economie et Statistique / Economics and Statistics, 2024 (10.24187/ecostat.2024.542.2113) | 7.8 to 14.3 points more homes where young children slept under a bednet | `study-senegal-bednets` |
| 6 | Greece's spring clock change → fewer serious crashes | Health Economics, 2023 (10.1002/hec.4715) | 15% to 20% fewer serious crashes | `study-greece-dst-crashes` |
| 7 | Britain's clock changes → slightly fewer road casualties | BMJ Open, 2022 (10.1136/bmjopen-2021-054678) | about 4.7 fewer casualties a year across both changes | `study-britain-dst-casualties` |

All seven are peer reviewed and graded Measured. None leaves a lasting mark (each effect is short or one-off), so all
sit under "Big splashes, nothing lasting yet". Each story has a "Not the only reason" line in `demo/context.json` naming
the other explanations the paper itself tested.

Two finds came from working papers that have since been published, and the stories cite the published version:
the football paper (IDE Discussion Paper 866, 2022, now International Organization, 2023; the published abstract gives
no size, and the note keeps the working paper's "nearly doubles") and the Catalonia paper (IEB Working Paper 2021/05,
now the Journal of Health Economics; its open copy dates the attacks).

## What was left out, and why

| Find | Reason |
|---|---|
| Doctor Who at Christmas → lower mortality (BMJ, 2023) | Christmas-issue paper, excluded by rule |
| 2004 tsunami → thyroid hormones (bioRxiv, 2026) | preprint with a health claim |
| 2004 tsunami → private consumption in Aceh (LSE thesis, 2016) | thesis |
| Queensland's daylight saving trial → substance-abuse admissions (Research Square, 2026) | preprint outside the allowed series, with health claims; the same result reports a suicide outcome |
| UK digital TV switchover → mothers' jobs and housework (SSRN, 2020; two finds) | working paper with no effect size stated; no stone date |
| Broadband in Norway → fertility and women's work (SSRN, 2026; two finds) | working paper with no effect size stated |
| Daylight saving time in Brazil → 14% fewer highway accidents (SSRN) | a version by the same group posted July 20, 2023 (SciELO Preprints 6458) reports 10% on 2007 to 2013 data; the effect size doesn't hold across versions, and the newer one is outside the allowed series |
| Mexico's 2017 earthquakes → cartel violence and cartel aid (SSRN, 2023; two finds) | a later journal version appears under another title ("Organized crime after earthquakes," 2025, 10.1177/17488958241302274), found by search; its publisher's host was stopped for the day, so it could not be read and the card can't honestly say "not yet peer reviewed" |
| iPhone launch → fewer births (NBER w35310, 2026) | verified, but the paper gives yearly birth rates (ages 15 to 19: 41.5 per 1,000 in 2007, 31.2 in 2011) and plots actual against no-iPhone births by year: held for a story with a real line |
| Korea's 2002 World Cup → happier "World Cup babies" (SSM Population Health, 2023) | the wellbeing measure includes a suicidal-thoughts item; the paper also gives yearly birth ratios, 2000 to 2005 |
| Hurricane Katrina → fewer parolees back in prison (PNAS, 2015) | the abstract gives no date or size, and the full text host returned 403 |
| A Chilean earthquake → fewer boys born (Human Reproduction, 2012) | the abstract doesn't date the earthquake and the publisher's host was stopped for the day; the effect comes from a simulation |
| 2008 Beijing Olympics → fewer underweight children (BJSM, 2022) | the authors warn the effect (odds ratio 0.12, lower bound 0.02) may be inflated by sparse data |
| London 2012 Olympics → less drinking and smoking (Social Science & Medicine, 2025) | the paper calls this evidence suggestive and gives no size |
| Daylight saving time → fewer infections diagnosed (PLoS Computational Biology, 2020) | the paper says these risks "appear to decrease" with no size, and its main finding is more disease after the change |
| Hurricane Floyd → fewer behavioral-health admissions (Psychiatric Services, 2005) | the abstract gives no size and doesn't call the drop significant; its main finding is more outpatient care |

## Follow-ups

- **Lines from the papers' own numbers:** iPhone → fewer births (yearly birth rates, actual against no-iPhone) and the
  Korean World Cup birth bump (spring births against January births by year, 2000 to 2005) for the births part only.
- **Recheck on another day:** the Mexico earthquake paper against its published version, and Katrina and the Chilean
  earthquake against their full texts.
- **The working-paper label:** the first working paper to ship needs a plain "working paper, not yet peer reviewed" line
  on its card.

## The opener

The demo now opens on Album release days → more traffic deaths, a peer-reviewed study with a strong design (each
release day against the same weekdays nearby, random Fridays and the same dates in other years). Tiger King stays under All
stories and at `?m=tiger-king`. The change is its own commit so it can be reverted alone.
