# Surprise panel v1: results (simulated raters)

Plan: `docs/panel_plan_v1.md`, registered in commit 9e71247 before any rating. Five **simulated** raters (language-model sessions with personas; two model sizes), 169 items each in its own shuffled order, no lookups. These are not people; real raters replace them after the public launch.

## Validity (registered checks): both pass

- Planted obvious pairs: mean surprise index 1.04 (bar: at most 2.5 and below the engine median of 2.2).
- Planted fabricated pairs: mean believable 1.14 (bar: at most 2.5 and below the real median of 4.4).

Agreement, mean pairwise Spearman: surprise .82, predicted .75, interest .72, believable .67. High, and partly an artifact: one model family shares its knowledge.

## The good-discovery rate (surprise index at least 3.5 and believable at least 3.5)

| Source | n | Good | Rate | Mean surprise index | Mean believable |
|---|---|---|---|---|---|
| Engine-found marks | 102 | 12 | 12% | 2.41 | 4.4 |
| Hand-built catalog | 38 | 4 | 11% | 2.86 | 3.9 |
| New model-screen passes | 9 | 0 | 0% | 2.67 | 4.2 |

The engine's marks are believable (4.4) but mostly unsurprising (2.41): about one in eight is both. Most are a disaster followed by its own law.

## Most surprising and believable (top 15)

| Surprise index | Believable | Source | Claim |
|---|---|---|---|
| 4.9 | 3.6 | engine | The West Wing led to: The Racial and Religious Hatred Act 2006 receives royal assent, as amended after the government's defeat |
| 4.6 | 4.2 | engine | Furby led to: The NSA bans Furbies from its property |
| 4.4 | 4.2 | engine | Zumba led to: Iran bans Zumba |
| 4.4 | 3.8 | catalog | The container led to: Canary Wharf |
| 4.3 | 4 | engine | Pokémon Go led to: New York bars sex offenders on parole from the app |
| 4.1 | 3.6 | engine | Dear Zachary led to: Canada's Bill C-464 on bail and the protection of children receives royal assent |
| 4.0 | 4.6 | engine | Jurassic Park led to: An NBA franchise is named after the film's dinosaurs |
| 3.9 | 4.6 | engine | An Inconvenient Truth led to: The High Court rules on showing the film in English schools |
| 3.9 | 3.8 | catalog | Sputnik led to: GPS |
| 3.8 | 4.2 | catalog | A horse's gallop led to: the movies |
| 3.7 | 4.2 | engine | Flint led to: University of Michigan researchers found BlueConduit |
| 3.6 | 3.8 | catalog | Ammonia led to: 8 billion people |
| 3.5 | 3.8 | engine | An Inconvenient Truth led to: Carbon-offset purchases rise near theaters that showed the film |
| 3.5 | 4.2 | engine | The Oklahoma City bombing led to: The Victim Allocution Clarification Act is signed |
| 3.5 | 4.4 | engine | Parkland led to: Florida ends the unanimity requirement for a death sentence |

## The automated surprise score v1 (PR #121) against these labels

Spearman .40 and AUC .60 on the 102 engine marks (14 rated surprising). Weak, consistent with its failure against the owner's grades. These panel labels are now the evaluation set for a v2 score.

## Limits

- Simulated raters: correlated, and they know what the model knows (a person who never heard of the West Wing's role would rate it differently). Treat the rate as a proxy.
- One pass each; the surprise index weighs "would not have predicted" and "surprising" equally.
- "Believable" judges the evidence line, not the truth of the link; the catalog's items had no line and score lower on it.
