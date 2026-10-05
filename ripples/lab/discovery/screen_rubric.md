# Screen rubric v1 (Oct 5, 2026)

The rubric a language model applies, in place of the person, to every candidate the discovery engine finds. It is the
first pass only: what passes still goes to a person for the context line and the final keep, and nothing it passes is
graded above **reported**. Fixed before any comparison with the hand decisions (`docs/screen_plan_v1.md`).

The definitions are the project's own. A ripple's payoff is a **lasting mark**: "a law, an institution, infrastructure,
jobs, public health, a durable change in behavior. Attention, growth and crazes are intermediate steps, never the
endpoint" (`HANDOFF.md`, section 1). A citation is labeled **reason / context / aside** as `lab/cite_score.py` does:
"cited as a reason", "mentioned in context", "an aside". The ordering rule: "every step later than the one before"; a
mark dated before its stone is busted. The record "disputes itself, usefully": a sentence that questions its own claim
is a Disputed link, not a mark (`docs/discovery_culture_v1.md`).

## Input

One candidate:

| Field | What it is |
|---|---|
| `stone` | the memorable thing: a work, a broadcast, an event |
| `stone_year` | the stone's year (from the catalog) |
| `reading` | `forward` (a sentence in the stone's own article) or `reverse` (a sentence in the mark's article that names the stone) |
| `mark`, `mark_year`, `mark_dated_by` | reverse only: the mark article's title, its year, and how the year was found (title, infobox, lead) |
| `sentence` | the candidate sentence, as the run extracted it |
| `section`, `years_in_sentence`, `source` | where the sentence sits, the years it carries, the article it came from |

Judge from these fields only. Do not supply facts from outside the record: if the sentence does not date the mark, the
mark is undated, whatever you know. General knowledge may be used to read the sentence (that "the Act" is the mark
title, that a pronoun refers to the stone) and to score the four dimensions, never to pass the gate.

## Output

```json
{"id": "...", "mark_stated": "the lasting change the sentence states, in a few words, or null",
 "is_mark": true, "link_label": "reason", "date_ok": true, "disputed": false,
 "gate": "pass", "decision": "accepted", "reason_code": null, "flags": [],
 "scores": {"interest": 0, "surprise": 0, "evidence": 0, "novelty": 0},
 "justification": "one line"}
```

## 1. is_mark: does the sentence state a lasting change?

`true` when the sentence states, as having happened, at least one of:

1. **A law or a standing rule.** A statute, regulation, ordinance, treaty, executive order, a court ruling that set a
   rule, or a standing official policy, enacted, adopted, signed, ruled or in force. Not proposed, introduced, debated,
   passed by one chamber, vetoed, or "called for".
2. **An institution.** An agency, commission, office, program, fund, foundation, charity, standing body, memorial, annual
   observance or facility that was created and is presented as lasting. An investigating commission counts (it is a
   body with a mandate and a record); a temporary task force, an emergency shelter, a relief appeal or a one-off event
   does not.
3. **A durable change in behavior.** A shift in what a population does, in a domain other than consuming the stone:
   enrollment, applications, enlistment, baby names and other namings (a species, a team, a place named after the
   stone), purchases of a different category, safety or professional practice, giving, voting. It must be stated as a
   change (a rise, a fall, a shift, a measured effect), not described as brief.
4. **Infrastructure, jobs or public health.** A thing built, a lasting change in employment, a health outcome.

`false` (and the reason code) when the sentence states only:

- **`attention_only`**: the stone's own audience, ratings, views, searches, sales, box office, merchandise, sequels,
  adaptations, awards, critical reception or "renewed interest"; a spike, a craze or a fad; tourism to a filming
  location or a site of the event (curiosity, not consequence) unless a standing rule followed (a visitor cap).
- **`not_a_mark`**: anything else that is not lasting: a proposal, a bill introduced or passed by one chamber, a
  petition, a campaign, a protest, a hearing or investigation that set no rule, a lawsuit filed, a settlement that set no
  standing rule, an arrest, a conviction, a firing, a resignation, an apology, a donation, an immediate operational
  response (shelters, curfews, evacuations, task forces, perimeters, emergency declarations), a company's own relief
  effort, a rename of a product, a ban, rating, recall or censorship **of the stone itself** in one jurisdiction (a
  reaction to the work's own distribution), or a sentence that states no change at all. A rule that governs people's
  conduct and names the stone (a parole condition, a rule about what may be brought onto secure property) is a standing
  rule and counts under 1.

## 2. link_label: is the stone given as the cause?

- **`reason`**: the sentence presents the mark as a consequence of the stone, at least in part: led to, prompted, in
  response to, as a result of, in the wake of, spurred, inspired, named after, credited with, because of, or "following
  X, Y was created to ..." where Y answers X. For a forward sentence the stone may be the article's implicit subject
  ("the film led to ...", "the disaster prompted ...").
- **`context`**: the stone and the mark share the sentence, but the stone is background: a date marker ("following the
  attacks" with no sign that the mark answers them), one item in a list of causes where the mark answers another, or the
  causal verb attaches to something else in the sentence (the mark's article explaining a different link, a person's
  later act). A reverse sentence that is about a third thing (an intermediate body, a predecessor) is context.
- **`aside`**: the stone is mentioned incidentally, as an illustration, a comparison, a title used as ordinary words,
  or the sentence is not about a consequence of the stone at all.
- **`wrong_entity`** (reason code; link_label `aside`): the sentence is about a different thing than the stone (a
  same-named work, a different event, the creator's other work, a real case the work portrays rather than the work).

## 3. date_ok: is the mark dated, and after the stone?

- `true` when the mark has a year, from the sentence (a year attached to the mark, or a stated interval from the stone:
  "two years after the film") or from `mark_year` on a reverse pair, and that year is at or after `stone_year`, and the
  sentence does not say the mark came first.
- `false`, **`bad_timing`**: the mark's year is before the stone's, or the sentence says it preceded the stone (the
  ordering rule: busted).
- `false`, **`undated`**: no year for the mark. "After the film's release" orders but does not date; it is undated.
  A year in the sentence that belongs to something else (the stone, a study's publication when the mark is the change
  the study measured) dates the mark only when the sentence ties them.

## 4. disputed: does the record question it?

`true` when the candidate text itself questions the mark or the link: questioned, disputed, contested, debunked, myth,
apocryphal, no evidence, found no effect, critics doubt, later analyses did not replicate. A disputed link is shown as
Disputed in the product, never as a mark; the gate fails with reason code **`disputed`**.

## 5. The gate, the decision and the reason code

**gate = pass** when `is_mark` and `link_label == "reason"` and `date_ok` and not `disputed` and the link is not merely
speculative. A link stated only as speculation by no one in particular ("it may have", "some believe", "it has been
suggested", "possibly") fails with **`weak_evidence`**; a named source, a study, an official record or a plain cited
statement is not weak.

**decision = accepted** when the gate passes and the candidate is not a **`duplicate`** (a sentence stating a mark that
an earlier accepted candidate for the same stone already states, including the same stone run twice under two names).
Otherwise **rejected**, with one `reason_code`, the first that applies in this order:

`wrong_entity`, `attention_only`, `not_a_mark`, `aside`, `context`, `bad_timing`, `undated`, `disputed`,
`weak_evidence`, `duplicate`.

**flags** (zero or more, never reject in v1, because the hand screens being compared did not reject on them):

- **`obvious`**: a knowledgeable person asked "what did this change?" would name this mark first (the inquiry after the
  disaster, the law named for it, the memorial).
- **`confounded`**: the sentence or the stone's history names a stronger concurrent cause, or the stone is one of many
  pressures the sentence lists.

The fixed code list is the owner's: `not_a_mark`, `attention_only`, `context`, `aside`, `bad_timing`, `undated`,
`weak_evidence`, `duplicate`, `confounded`, `obvious`, `wrong_entity`, `disputed`.

## 6. Four scores, 0 to 100

Scored for every candidate, accepted or not. They are editorial judgments, not measurements, and they never pass the
gate; they exist so the owner can see which dimension tracks his keep decisions.

| Score | Question | 0 | 50 | 100 |
|---|---|---|---|---|
| **interest** | Would a curious person care? | trivia about the work's release | a reader would finish the card | a reader would tell someone |
| **surprise** | Would a knowledgeable person have predicted it? | the expected response (the disaster's inquiry) | a plausible link few would name | nobody would have thought to test it |
| **evidence** | How strong is the record for the link as stated? | no link, or contradicted | a plain cited causal sentence | an official record or a study naming the stone |
| **novelty** | Were the two already obviously associated? | the mark is named for the stone or in its lead | known to people who follow the subject | never associated in common knowledge |

Surprise asks about the mechanism (could you have guessed the path?); novelty asks about the pairing's fame (has
everyone already heard it?). A law named for a disaster is low on both; a famous but odd link (a film and a team's name)
is high on surprise and middling on novelty.

## 7. Justification

One line: the mark, why it is or is not one, the link, the date. No more.

## Worked boundary cases (from the definitions, not from any hand label)

- "The documentary prompted calls for a ban on the practice." Calls are not a rule: `not_a_mark`.
- "In the wake of the disaster, the Red Cross opened 40 shelters." Operational response: `not_a_mark`.
- "The film was banned in three countries." A reaction to the work's distribution: `not_a_mark`.
- "Following the attacks, the agency was created in 2002 to coordinate security." Created, answers the stone, dated
  after: pass, likely `obvious`.
- "Sales of the novel rose 500%." The stone's own sales: `attention_only`.
- "Organ donor registrations doubled in the year after the episode aired." A population shift in another domain, dated
  by a stated interval: pass.
- "The Act, passed in 1975 after years of campaigning that cited the 1970 report ..." with a 1980 stone: `bad_timing`.
- "Its effect on recruitment has since been questioned." `disputed`.
