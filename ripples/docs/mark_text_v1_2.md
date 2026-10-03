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

## Result (Oct 3, 09:03 UTC; run 37110077187, 29 minutes)

547 pairs (526 Hansard, 21 Federal Register, 0 legislation.gov.uk; GovInfo skipped), 491 time-ordered, 138 in the
counted tiers. **The positive control is in:** Mr Bates vs The Post Office → Post Office (Horizon System) Offences
Bill, second reading, March 20, 2024, seven contributions ("that powerful ITV drama … prompted a public outcry"; "the
influence of the ITV drama … has been very significant in this campaign"). Hand-screened, the counted tiers hold at
least nine real work → bill citations beyond the control (Cathy Come Home → Housing Subsidies Bill, Dec 15, 1966, a
month after broadcast, and the 2016 Homelessness Reduction Bill debate tying it to the Housing (Homeless Persons) Act
1977; My Octopus Teacher → Animal Welfare (Sentience) Bill; Adolescence → Children's Wellbeing and Schools Bill, five
days after release; McMafia → Sanctions and Anti-Money Laundering Bill; Manhunt → the BBFC accountability bill; Ocean
with David Attenborough → the Biodiversity Beyond National Jurisdiction Bill; Baby Reindeer → Criminal Justice Bill;
Super Size Me → Food Products (Marketing to Children) Bill; Silent Spring → Agriculture Bill). **The rule passes** (≥5
counted pairs with a resolved work and a named bill; ≥2 new to the project). Noise remains (an idiom, a band, a
cartoon cited for a pun) and is screened by hand; a citation in a debate is a *reported* link at most, never measured.
Next: the blind owner round, then maps with the Act as the mark where the bill became law.
