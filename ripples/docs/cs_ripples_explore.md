# Explore-then-confirm workflow, and the Clickstream ripple-map prototype (registered 2026-09-29, ledger 1466)

**Owner decision (2026-09-29):** exploration no longer needs a registration before every step. Registration is kept
for confirmation.

## The workflow

1. **Explore** freely on the exploration set: change settings, look at results, iterate. Nothing found here is shown
   as a confirmed ripple; the page labels it "exploratory".
2. **Freeze** the engine's settings and pick the candidates to confirm, in a ledger entry.
3. **Confirm** on held-out data the exploration never touched, with a registered test (the daily timing test and,
   where it exists, a second lens). Only confirmed ripples lose the "exploratory" label.

**Split for Clickstream work:** exploration months are 2017-11 to 2022-12; held-out months are 2023-01 to 2026-08.
The prototype computes maps for every month so the viewer works end to end, but settings are tuned only by looking at
exploration months, and held-out months are read only in a registered confirmation.

## Prototype v0: ripple maps from reader behaviour (`ripples/lab/cs_ripples.py`)

- **Data:** every monthly English Clickstream file (2017-11 onward), pairs with ≥ 200 clicks.
- **Event:** an article whose arrivals in a month are ≥ 4× its 6-month median and ≥ 60,000.
- **Ripple (ring 1):** a link from the event with ≥ 1,000 clicks and ≥ 3× its own usual level, into an article whose
  arrivals rose ≥ 1.5×.
- **Carried:** the share of the target's extra arrivals that came straight from the event.
- **Surprise:** 1 − overlap between the event's neighbours this month and the target's usual neighbours, halved when
  readers already went that way before the event.
- **Ring 2:** links out of a ring-1 article that surged the same month into articles the event does not link to.
- **What it is not:** a claim of cause. It shows where readers went next; timing tests and other lenses come after.
