# Mark-text search v1.3: the US side, properly (explore stage)

*Written Oct 3, 2026, after the first GovInfo run and before the v1.3 run.*

**What the first GovInfo run found (41 pairs).** The second positive control: *Tiger King* → the Big Cat Public Safety
Act in the Congressional Record (July 28, 2022); *Blackfish* → the "Orca Captivity" floor debate (2014) and National
Orca Protection Month (2018); *Unsafe at Any Speed* cited across twenty years of hearings; *Silent Spring* in Earth
Day tributes. Two defects: one query across all four collections sorted oldest-first returned thirty years of floor
speeches and never a public law or a bill; and every hit was tiered "record".

**Repairs (nothing else changes).** One query per collection (PLAW, BILLS, CREC, CHRG), newest first, 40 results each;
the tier comes from the package (public law → `law`, bill → `bill`) or from the Record's section title (an Act, Bill,
H.R., S. or resolution → `bill debate`; a hearing → `hearing`). v1.3 starts from v1.2's Hansard, legislation.gov.uk
and Federal Register results and redoes only GovInfo.

**Unchanged.** Marker phrases, the ambiguity guard, politeness, and the success rule; the US control is Tiger King →
Big Cat Public Safety Act as a `law` or `bill debate`.

**Output.** `ripples/docs/results/mark_text_v1_3.json`.
