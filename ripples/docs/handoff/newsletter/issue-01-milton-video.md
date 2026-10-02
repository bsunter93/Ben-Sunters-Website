# Ripple Map #1: Hurricane Milton · 60-second video script

**Format:** vertical 9:16, burned-in captions (most people watch muted), about 150 spoken words.
**Tone:** quiet mode. Milton cost lives: no dramatic music, no whooshes, no storm-damage footage. A calm voiceover, the pond visuals and one chart.
**Sound:** optional soft ticks as stops appear (per the sound spec). No music bed, or a very low neutral one.

---

| Time | Voiceover | On screen |
|---|---|---|
| **0:00–0:04** | "The day after Hurricane Milton hit Florida, something moved in the power grid." | A dark pond. The stone drops, and **HURRICANE MILTON · 9 OCT 2024** fades in. |
| **0:04–0:13** | "On Florida's Gulf coast, electricity demand fell to less than half of normal. For the whole week it ran about eleven percent below." | The first ripple reaches a stop labeled **Duke Energy Florida**. The number counts **1.00× → 0.45×**, then settles to **0.89× · the week after landfall**. |
| **0:13–0:18** | "But demand bounces around. Could that just be luck? We checked three ways." | The text **COULD IT BE LUCK?** appears, then three empty circles. |
| **0:18–0:25** | "One. We ran the same test on 1,646 random days. Only three looked this strong." | Circle 1 fills in. A dot field of 1,646 gray dots, 3 highlighted, and a large **3 / 1,646**. |
| **0:25–0:34** | "Two. We compared Florida with fifty-one grid regions the storm missed. Florida ran twenty percent below them, and no fake storm date came close." | Circle 2 fills in. The daily chart (`milton-grid-daily.csv`): Florida and the other regions track together, then Florida drops at landfall. **−20% vs 51 regions** · **0 of 41 fake dates**. |
| **0:34–0:41** | "Three. A forecast model that knew nothing about the storm predicted normal demand. Reality came in about twenty percent under." | Circle 3 fills in. A dashed forecast line with the actual line below it, **−20.4% · −19.1%**, and the small label *Google BigQuery forecast*. |
| **0:41–0:44** | *(pause)* | The stop label changes to **● MEASURED**. |
| **0:44–0:51** | "And what didn't move? Jobless claims. Air travel. Gas prices. Twelve things we tested stayed flat." | Grass beds at the pond's edge, with calm labels appearing one by one: *Florida jobless claims · TSA travelers · Gas prices · +9 more* · **STAYED FLAT**. |
| **0:51–0:57** | "Milton is one of our test storms. It's how we check the engine finds real effects before we trust it on the surprising ones." | The pond pulls back to show the other ponds, faint and waiting. |
| **0:57–1:00** | "Consistent with, never proof of cause. Full evidence at the link." | **What did that event change?** · Ripple Map · bensunter.com/ripples · *consistent with, never proof of cause* |

**Word count:** about 150, which is 60 seconds at a steady pace. If a read runs long, the first thing to cut is the "Could that just be luck?" line (0:13–0:18).

---

## Caption and post copy

**Caption:**
The day after Hurricane Milton, Florida's Gulf-coast grid drew 45% of its normal electricity. Luck? We checked against 1,646 random days, 51 grid regions the storm missed, and an independent forecast. Twelve other things stayed flat. Consistent with, never proof of cause.
Full evidence (with downloadable data): link in bio.

**Pinned comment:** "Why didn't gas prices or air travel move? Any effect was too small or too local to separate from normal noise in national data. Stayed flat is a finding too."

---

## Every number, with its source

All figures come from `rm_pond('hurricane-milton-positive-control-213')`, published Sep 26, 2026.

| Claim | Value in the data |
|---|---|
| Less than half of normal, the day after landfall | Oct 10, 2024: 45% of normal (Duke Energy Florida, EIA-930) |
| About 11% below for the week | 0.89× normal, week from 10 Oct |
| 3 of 1,646 random days | single-event test: `exceed_date` 3, `n_date` 1,646 |
| 20% below 51 regions | regional contrast (Duke Energy Florida + FPL vs 51 donors): −19.9% |
| No fake storm date came close | 0 of 41 in-time placebos as big |
| Forecast about 20% under | BigQuery AI.CAUSAL_EFFECT: −20.4% and −19.1%, 8-day horizon |
| Twelve things stayed flat | 12 pre-registered hops at tier `flat` |

**Wording guard:** the script never says Milton "caused" anything, and the closing line carries the rule. "Florida ran 20% below them" refers to both utilities together. Don't edit it into "Duke ran 20% below".
