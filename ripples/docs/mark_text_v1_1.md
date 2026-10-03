# Mark-text search v1.1: three repairs after the first 26-minute run (explore stage)

*Written Oct 3, 2026, after v1 (`mark_text_v1.md`) and before the v1.1 run.*

**What v1 found.** 30 pairs in 26 minutes: 28 from Hansard (4 in bill debates), 2 from the Federal Register, 0 from
legislation.gov.uk; GovInfo skipped (no key). Real mentions (Adolescence in three 2025 debates, Cathy Come Home on its
35th anniversary, McMafia in the Skripal debate, Minder in a 1986 drugs debate) but the positive control, Mr Bates vs
The Post Office, did not appear, and no pair reached a law.

**Why, and the repairs (nothing else changes).**
1. **Named-work markers.** v1 only extracted a title when a quote mark or "the Netflix series" pattern followed the
   marker, so a speech saying "the ITV drama Mr Bates vs the Post Office" produced nothing. v1.1 resolves a named-work
   marker as the title itself (Mr Bates → *Mr Bates vs The Post Office*, Blackfish → *Blackfish (film)*, and so on).
2. **Hansard recency.** v1 read the newest 100 contributions per phrase; for "television series" that is 2025 only.
   v1.1 reads the newest 100 and the oldest 100, and records each phrase's total.
3. **legislation.gov.uk paths.** v1 fetched notes from `/id/...` identifiers (no document there) and dated items by the
   feed's update time. v1.1 fetches `/ukpga/YYYY/N/notes/data.xht` and friends for UK enactments only (EU retained law
   is skipped) and dates the mark by the year in the path.

**Unchanged.** Marker phrases, tiers, politeness, and the success rule: at least 5 time-ordered pairs in the counted
tiers (law, rule, bill, bill debate) with a resolved work and a named law, bill or rule, at least 2 new to the project;
Mr Bates → Post Office (Horizon System) Offences Act 2024 as the positive control.

**Output.** `ripples/docs/results/mark_text_v1_1.json` (fresh state). Budget 150 minutes.
