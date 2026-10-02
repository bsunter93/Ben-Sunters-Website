# Ripple Map · Issue #1

**Subject line:** What did Hurricane Milton actually change?
**Preview text:** One thing moved a lot. Twelve things we tested didn't.

---

Welcome to the first issue. The idea is simple: pick one big event, then ask the data what it actually changed. We don't ask what pundits predicted or what the headlines said. We look at what moved and what didn't, and how sure we can be.

Every finding carries one of three labels:

- **Measured:** it passed pre-set tests, beat random lookalikes, and an independent model agrees.
- **Likely:** a strong result, published with its odds of being a fluke.
- **Watching:** the test is set, but the answer isn't in yet.

One rule never bends: *consistent with, never proof of cause.*

---

## The event

Hurricane Milton made landfall near Siesta Key, Florida, on the evening of October 9, 2024, as a Category 3 storm. It cost lives and caused serious damage across the state. This issue looks at one measurable effect. It doesn't turn the storm into entertainment.

A note on why we're starting here. Milton is one of our **test storms**. We expect big hurricanes to move certain things, so we use them to check that the engine finds real effects before we trust it on anything surprising. Think of this issue as the instrument being calibrated in public.

## The ripple: Florida's Gulf-coast grid went quiet

**Measured.** Duke Energy Florida serves the Gulf coast where Milton came ashore. In the week from October 10, the day after landfall, its electricity demand ran at **0.89× normal**, about **11% below** what's usual for that time of year. On October 10 itself it drew just **45% of normal**.

That on its own could be a coincidence: October weather varies, and demand bounces around. So we checked it three independent ways.

**1. Against random days.** We ran the same test on 1,646 random days with no storm. Only **3** looked as strong as Milton.

**2. Against grids the storm missed.** We compared Florida's two big utilities, Duke Energy Florida and Florida Power & Light, with **51 US grid regions** the storm never touched, over the same week. Florida's grids ran **20% below** them. The two sides tracked each other closely in the weeks before, so the gap opens at the storm and not earlier. Then we ran the same comparison 41 times on dates when no storm hit, and **none** produced a gap that big.

**3. Against a forecast.** Google's BigQuery forecasting model had no information about the hurricane, and it predicted what Duke Energy Florida's demand *should* have been over the 8 days from onset. Actual demand came in **20.4%** and **19.1%** below forecast on the two demand series it checked. For calibration, the same model raised a false alarm on only 1 of 42 fake links.

Three methods, three sets of assumptions, one answer.

**Why?** The plausible mechanism is the obvious one: outages and closures meant homes and businesses on the Gulf coast weren't drawing power. The data shows *that* demand fell, and by far more than chance or the rest of the country explains. The "why" is an explanation, not something the numbers prove.

**Could it be Helene?** Hurricane Helene hit Florida 11 days earlier, so it's the natural rival explanation. We ran the same grid comparison for Helene. Its effect was just −1.8% and didn't pass. The drop belongs to Milton's week.

## What *didn't* move

This is the part most coverage skips. We tested twelve other things, and each **stayed inside its normal range**:

- **Florida Power & Light demand, on its own.** Florida's other big utility, mostly serving the east and south, didn't show a clear drop when tested alone. The effect was concentrated where the storm came ashore.
- **Florida jobless claims**
- **US air travelers** at TSA checkpoints
- **US gasoline prices** (weekly)
- **Gulf Coast jet-fuel prices**
- **FEMA declarations:** Florida-specific, emergency, and major-disaster (three tests)
- **National Weather Service warnings:** tornado, severe thunderstorm, flash flood, and all types combined (four tests)

"Stayed flat" doesn't mean nothing happened to anyone. It means any effect was too small, too local, or too noisy to separate from normal variation in these series. Two honest caveats:

- **FEMA:** declarations were already elevated from Helene, so Milton's week didn't stand out against it.
- **Weather-warning archives:** ours only reach back to 2024, which leaves few comparison dates. Those four tests are weak.

## Still waiting

One test has no answer yet: **extreme-wind warnings**. The test window (October 8–14, 2024) is long closed, but we're still loading the history needed to check it fairly. We'll report back when there's an answer, whichever way it goes.

## Where hurricanes usually reach

Milton wasn't tested on this, so treat it as a teaser, not a finding. Across **23 past hurricanes**, applications to start a new business in the hit states ran **3.2% below** unaffected states over the following four weeks. Hurricane Laura (2020) saw about −15%. It's a strong pattern, and about 1 in 20 findings at this level could be a fluke. It's also exactly the kind of downstream ripple we'll be testing on future storms before they land.

---

## Behind the curtain

Why trust any of this? Three habits:

- **We freeze the test before running it.** Each test is locked and time-stamped in a tamper-evident log before any results are computed.
- **We try to fool ourselves.** The engine is fed deliberately fake event-and-outcome pairs. In the latest blind check, 0 of 48 fakes were falsely confirmed.
- **We publish the losers.** Ideas that failed go on a public kill list with their numbers.

And where one check was weak, we say so. Within the grid comparison, a stricter "synthetic twin" check pointed the same way but was too noisy to confirm it on its own.

The full evidence for this ripple, down to the daily numbers you can download, is here: **[bensunter.com/ripples/pond/r/?e=hurricane-milton-positive-control-213](https://bensunter.com/ripples/pond/r/?e=hurricane-milton-positive-control-213)**

---

**Know someone who'd find this interesting?** Forward it. Every issue is one event and one honest answer.

**Got an event you want traced?** Reply and tell me. I read every one.

*Ripple Map finds patterns consistent with cause, never proof of cause. Data: US Energy Information Administration (EIA-930 hourly grid demand); OpenFEMA disaster declarations; FRED (jobless claims, gasoline and jet-fuel prices); TSA checkpoint throughput; National Weather Service warnings via the Iowa Environmental Mesonet; US Census Business Formation Statistics; forecast check with Google BigQuery.*
