# Editor trail v1: discovery of non-obvious ripples (explore stage)

*Written 2 Oct 2026, before the run. Explore stage under explore-then-confirm (ledger 1466): no claim on the public
pages rests on this run alone.*

**Why.** Every open-ended method so far proposed neighbours of an event, not its consequences: Clickstream is a
curiosity graph. When an event really moves something, Wikipedia editors tend to record it in the article that moved
(a song that re-charted, a food that sold out, a town that drew tourists). The articles linking to an event's article
therefore contain its documented ripples, mixed with cast, episodes and navbox noise.

**Method.** See `ripples/lab/editor_trail.py`: backlinks to the event article(s); Wikidata typing drops people,
TV and film works, episodes, seasons, characters, awards, lists and same-franchise titles; daily views from July 2015;
a sustained rise must begin on or after the event's own attention onset and within 120 days (the ordering rule,
ledger 1497); specificity is checked against the candidate's own history (every 14th day as a pseudo-event,
p = (1 + hits) / (1 + N), at least 20 pseudo-events); a rise in the same window one year earlier flags "seasonal".

**Recall check (set before the run).** Six documented, non-obvious ripples, chosen from public reporting:
Stranger Things 4 → "Running Up That Hill" and "Master of Puppets"; Wednesday → Lady Gaga's "Bloody Mary" and
"Goo Goo Muck"; Saltburn → "Murder on the Dancefloor"; Squid Game → dalgona. The method works if at least 4 of the 6
appear among their event's 15 top unusual candidates (p ≤ 0.05). Controls with obvious ripples: Queen's Gambit → chess,
Chernobyl → Pripyat, Tiger King → big cats, The Last of Us → cordyceps.

**What happens next.** If recall passes, the other unusual, non-seasonal candidates from all 14 events (at most 15,
chosen by rank, names only, no hint of which are known) go to a blind owner round under the owner's rule (≥ 5
interesting, non-obvious, not-searched; ≥ 1 worth chasing). Survivors get a confirm stage: a registered test on data
not used here (Google Trends archive, library borrowing or a dated public record) before they appear on a map.
If recall fails (fewer than 4 of 6), the method is dropped.

**Known limit.** It finds ripples someone documented: new to most people, not unknown to the world.
