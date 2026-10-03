# Mark-text search v1.2: ambiguity and depth, after v1.1 (explore stage)

*Written Oct 3, 2026, after the v1.1 run (31 minutes) and before the v1.2 run.*

**What v1.1 found.** 347 pairs: 237 Federal Register, 109 Hansard, 1 legislation.gov.uk; 54 in the counted tiers.
Most counted pairs were false: *Blackfish* matched the fish in fisheries rules, *The Jungle* matched the Calais camp,
*Stranger Things* an idiom, *Adolescence* the word. The real trail was visible in Hansard (574 contributions name Mr
Bates; the January 8, 2024 statement "Horizon: Compensation and Convictions" announces legislation; the Compensation
Bill debates of December 2023 cite the drama a month before it aired, a true negative), but the Post Office (Horizon
System) Offences Bill debates of March–May 2024 sat outside the newest-100 and oldest-100 windows.

**Repairs (nothing else changes).**
1. **Depth for named works:** every Hansard page, up to 1,000 contributions per named work.
2. **Ambiguity guard:** a named marker that is also an ordinary word (Blackfish, The Jungle, Adolescence, Stranger
   Things, Mr Bates, Tiger King, Squid Game, Baby Reindeer, WarGames) counts only with a work-context word within 160
   characters (drama, series, film, documentary, programme, Netflix, ITV, BBC, book, novel, broadcast, episode,
   aired, viewers, or a name tied to the work).
3. **Bill stages:** a debate section naming a Second Reading, Committee, Report Stage or Third Reading is the tier
   `bill stage`; a section naming an existing Act is `act debate` and is not counted.

**Unchanged.** Marker phrases, sources, politeness, and the success rule (at least 5 time-ordered pairs in the counted
tiers, law / rule / bill / bill debate / bill stage, with a resolved work and a named law, bill or rule, at least 2
new to the project; Mr Bates → the Offences Bill as the positive control).

**Output.** `ripples/docs/results/mark_text_v1_2.json`. Budget 150 minutes.

## Addendum, after the first v1.2 run (Oct 3, 08:40 UTC)

The run (15 minutes) read 574 Mr Bates contributions and produced 10 pairs from them: the Hansard API highlights the
match as `Mr <em>Bates</em>`, and stripping the tags left a double space that failed the "marker in window" check.
Whitespace is now collapsed before matching (`clean`). Explanatory-note fetches are limited to primary legislation from
1999, where notes exist. Nothing else changes; the file is rebuilt from scratch.
