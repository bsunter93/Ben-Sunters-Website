# Chain tests v2: less obvious chains, in time order (registered 2026-09-30, before any v2 data is fetched)

**Why:** chain tests v1 (ledger 1501) showed the behaviour step can be measured: 3 of 13 obvious chains passed and the
ordering rule caught Oppenheimer. v2 asks for less obvious behaviour, and for two-step chains where the second
behaviour must start after the first (owner ordering rule, ledger 1497).

## Chains, fixed now

| Event | Month (m0) | Step 1 | Step 2 (must start after step 1) | Mechanism |
|---|---|---|---|---|
| Squid Game | 2021-09 | Korean language | | viewers start learning Korean |
| Stranger Things season 4 | 2022-05 | Dungeons and Dragons Game | | the Hellfire Club storyline revives D&D |
| Shōgun (FX) | 2024-02 | Tokugawa period | | viewers read the real history behind it |
| Tiger King | 2020-03 | Wild animal trade | | the show exposes the exotic-pet trade |
| Tidying Up with Marie Kondo | 2019-01 | Simplicity | | tidying turns into a simpler-living interest |
| Barbie | 2023-07 | Feminism | | the film's themes send readers to feminism |
| GameStop short squeeze | 2021-01 | Speculation | | new retail traders read about speculating |
| The Queen's Gambit | 2020-10 | Chess | Board games | chess interest spreads to board games in general |
| The Last of Us (HBO) | 2023-01 | Fungi | Mushroom culture | the cordyceps story leads to fungi, then to growing mushrooms |
| Chernobyl (HBO) | 2019-05 | Chernobyl | Nuclear power plants | the disaster leads to nuclear power in general |

## Test (`ripples/lab/chain_tests_v2.py`)

- **Data and series:** as v1 (Seattle Public Library checkouts by subject heading; log(1 + checkouts) minus the
  1,376-heading panel median, minus the same-month median of the previous three years).
- **Effect:** mean over m0 .. m0+5 minus mean over m0-6 .. m0-1 (6 months, since downstream behaviour can be slower).
- **Null:** the same effect at every admissible month of the same heading (2008 on, at least 10 months from m0).
- **Onset:** first month from m0-3 to m0+9 above the pre-period mean + 2 MAD (pre-period m0-12 .. m0-1).
- **Step passes:** p ≤ 0.05 and onset in m0 or later.
- **Chain passes:** every step passes; for two steps, step 2's onset is a later month than step 1's.
- **Reported:** chains passing, steps passing against 5% expected by chance.
- **Offline check:** a planted two-step chain (step 2 one month after step 1) passed; nine null chains did not (2 of 13
  steps passing, both planted).

## Limits

- One city, monthly counts. Headings are matched as text inside the Subjects field (parentheses dropped, as v1 found).
- "Chess" includes every chess heading; "Board games" is a separate heading.
- The mechanisms are hypotheses written before the data; a pass shows timing and size, not proof of cause.
