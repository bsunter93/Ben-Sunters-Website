# Q3 protocol v2: screen v2 and the first held-out confirmation (registered 2026-09-28, before either is run)

Method: discovery v1 (ledger 1283), unchanged apart from one **data fix**, which is disclosed. Everything not stated
here follows `q3_protocol.md` (v1).

## What changed since v1, and why

- **Data fix.** Screen v1 (ledger 1284, result 1285) skipped 9 of 42 events: their articles had been renamed after
  the event, and Wikipedia stores views under the title at view time. From v2 on, each event article's views are
  the sum over its current title and every title that redirects to it (`cult_data.titles_with_redirects`). The
  outcome panel is unchanged.
- **Events.** The owner added 500 events (`ripples/corpus/events_501_1000.csv`, E501–E1000), almost all from 2015
  on.
- **What has already been seen.** Screen v1's results were seen before this registration:
  - space_science: Speed of light, Telescope, Solar System.
  - pandemic_crazes: Home, rejected by leave-one-out.
  - Nothing else passed.
  - v2 therefore does not screen space events. Pandemic_crazes is re-run and labeled a **second look**. Every other
    v2 family is new, and no outcome has been examined for it.

## Screen v2

- **Families:** 14 families, 115 events (`ripples/corpus/q3_families_v2.tsv`). They follow the owner's family labels,
  merged within a section into narrow themes.
- **Membership rules:**
  - Event day on or after 2016-09-01.
  - A clear event day, or a stated window in which day 0 is the peak of the event's own article.
  - No two members of a family on the same day.
- **Internal check:** the streaming family contains The Queen's Gambit, whose Chess ripple was confirmed in E9. If
  Chess appears it is an echo (linked from the article). It shows the engine sees what it should; it is not a
  discovery.
- **Analysis, null and candidate rule:** as in v1. 1,000 moved-date worlds and a family-wise maximum over 998
  outcomes; both z versions at p ≤ 0.05; leave-one-member-out stable.
- **Correction:** Benjamini–Hochberg at q = 0.10 across the **14** v2 families.
- **Common-shock flag:** members whose days fall within 30 days of each other are listed per family (for example,
  games and pandemic_crazes around March 2020). A candidate carried by clustered members is reported as
  common-shock risk, even if it passes leave-one-out.
- **Status:** candidates only. Each needs its own held-out confirmation, like the one below.

## Confirmation 1: space science → Speed of light

- **Members:** 8 space events from the owner corpus, none of them used in any screen, with no outcome examined
  (`ripples/corpus/q3_confirm_space_v1.tsv`): Falcon Heavy test flight, Chang'e 4, Crew Dragon Demo-2, Ingenuity,
  Sagittarius A* image, Starship flight test 1, OSIRIS-REx sample return, IM-1.
- **Pre-specified outcome:** Speed of light (the only non-echo candidate from screen v1). Telescope and Solar System
  are reported alongside as echo references and are not part of the test.
- **Test:** the family score for that one outcome against 1,000 moved-date worlds. Since the outcome is fixed in
  advance, the null is that outcome's own score, not a maximum over outcomes. Views are corrected for redirects.
- **Success:** p ≤ 0.05 for both the MAD and the rank version.
- **Reporting:**
  - Success: the ripple moves up the evidence ladder (timing + comparison + held-out replication). It is still not a
    causal claim.
  - Failure: the screen-v1 candidate is reported as not confirmed.
  - Either way, the result goes to the ledger.

## Surprise note (recorded before results)

A space-science → Speed of light ripple would be **same-domain and modest in surprise**: space news sending
readers to a basic physics concept. It is a test of whether the engine's candidates replicate, not a story.

## Addendum (registered before any v2 or confirmation run): confirmation 2

- **Members:** a second, independent held-out space family from the owner's batch E4001–E4500
  (`ripples/corpus/q3_confirm_space_v2.tsv`, 12 events): TRAPPIST-1, the 2017 eclipse, Cassini's finale,
  ʻOumuamua, Parker Solar Probe, InSight, Voyager 2 entering interstellar space, Artemis I, Chandrayaan-3,
  Euclid, SLIM, Europa Clipper.
- **Test:** same outcome, same test, same success rule as confirmation 1. The two confirmations are reported
  separately.
- **Reading the results:**
  - Speed of light counts as replicated only if both pass.
  - One pass and one failure is reported as mixed.
