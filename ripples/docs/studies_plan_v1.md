# Studies pilot: pre-registered plan

**Written:** 10/08/2026, about 8:40 PM PT, before any harvest request was sent.
**Generator:** published studies that measured the effect of a cultural stone (film, TV show, song, book, game, celebrity moment, public event) on something many people do.
**Grades used downstream:** Measured (the study beat a baseline with a quasi-experimental or experimental design), On the record (a public record names the link but the study is descriptive), Unproven.
**Attribution rule:** a link exists only when the paper itself names the stone. No outcome-first search.

## 1. Sources and request rules

- OpenAlex `https://api.openalex.org/works?search=<q>&per-page=50&select=id,doi,title,publication_year,cited_by_count,abstract_inverted_index,primary_location` (main generator).
- PubMed E-utilities `esearch.fcgi` (retmax 40, sort relevance) then `efetch.fcgi` (rettype abstract, retmode xml) for health families.
- Crossref `https://api.crossref.org/works` only as backup when an OpenAlex record lacks an abstract or a date.
- Verification: the paper's DOI landing page (via doi.org), or its PubMed abstract, or an open copy that OpenAlex lists for the same work (PMC, NBER, a university repository). The verified text is saved to `verify/`.
- Library of Congress Chronicling America for stones before 1963, to confirm a stone's date from a period newspaper.
- No Wikipedia, Wikidata, Wikimedia, Reddit, Merriam-Webster or Etymonline requests.
- User agent `ripple-research (bensunter.com)` on every request. No email address and no API key in any request.
- At most 1 request per second per host (3 per second for NCBI). Any 4xx or 5xx from a host stops all requests to that host for the day and is logged in `logs/blocked_hosts.log`.

## 2. Query families (frozen)

Every family runs on OpenAlex. Families with a `pm` key also run on PubMed. The harvester reads this block verbatim.

```json
[
{"id":"F01","name":"Angelina Jolie effect","oa":["Angelina Jolie BRCA testing","Angelina Jolie effect"],"pm":["Angelina Jolie[tiab]"]},
{"id":"F02","name":"celebrity cancer disclosure and screening","oa":["celebrity cancer diagnosis screening uptake","celebrity announcement cancer screening rates"],"pm":["celebrit*[tiab] AND cancer[tiab] AND screening[tiab]"]},
{"id":"F03","name":"Katie Couric colonoscopy","oa":["Katie Couric colonoscopy"],"pm":["Couric[tiab]"]},
{"id":"F04","name":"Jade Goody cervical screening","oa":["Jade Goody cervical screening"],"pm":["Goody[tiab] AND cervical[tiab]"]},
{"id":"F05","name":"Kylie Minogue mammography","oa":["Kylie Minogue breast cancer mammography"],"pm":["Kylie Minogue[tiab]"]},
{"id":"F06","name":"celebrity HIV disclosure and testing","oa":["Magic Johnson HIV announcement testing","Charlie Sheen HIV disclosure"],"pm":["(Magic Johnson[tiab] OR Charlie Sheen[tiab] OR Rock Hudson[tiab]) AND HIV"]},
{"id":"F07","name":"public figure illness and screening","oa":["Betty Ford breast cancer effect","Chadwick Boseman colorectal cancer screening","Ben Stiller prostate cancer screening","Nancy Reagan breast cancer mastectomy"],"pm":["(Chadwick Boseman[tiab] OR Ben Stiller[tiab] OR Nancy Reagan[tiab] OR Betty Ford[tiab] OR Ronald Reagan[tiab]) AND cancer"]},
{"id":"F08","name":"celebrity suicide Werther effect","oa":["Robin Williams suicide Werther effect","celebrity suicide imitation suicides"],"pm":["(celebrity[tiab] AND suicide[tiab]) AND (Werther[tiab] OR imitat*[tiab] OR copycat[tiab])"]},
{"id":"F09","name":"13 Reasons Why","oa":["13 Reasons Why suicide rates"],"pm":["13 Reasons Why[tiab]"]},
{"id":"F10","name":"16 and Pregnant","oa":["16 and Pregnant teen childbearing MTV"]},
{"id":"F11","name":"telenovelas and family","oa":["telenovelas fertility Brazil","soap operas divorce fertility"]},
{"id":"F12","name":"cable TV and women in India","oa":["cable television women's status India"]},
{"id":"F13","name":"An Inconvenient Truth","oa":["An Inconvenient Truth carbon offsets","documentary film environmental behavior"]},
{"id":"F14","name":"CSI effect","oa":["CSI effect forensic science enrollment","CSI effect jurors"]},
{"id":"F15","name":"Scully effect","oa":["Scully effect X-Files women STEM"]},
{"id":"F16","name":"Blue Planet II","oa":["Blue Planet II plastic"]},
{"id":"F17","name":"Pokemon Go","oa":["Pokemon Go physical activity steps"],"pm":["Pokemon Go[tiab]"]},
{"id":"F18","name":"Sideways and wine","oa":["Sideways movie Pinot Noir Merlot demand"]},
{"id":"F19","name":"film-induced tourism","oa":["film-induced tourism visitor arrivals","Lord of the Rings New Zealand tourism","Game of Thrones tourism","Harry Potter tourism"]},
{"id":"F20","name":"TV drama and anime tourism","oa":["Korean drama tourism arrivals","anime pilgrimage tourism"]},
{"id":"F21","name":"food documentaries","oa":["Super Size Me fast food consumption","documentary meat consumption"]},
{"id":"F22","name":"Blackfish","oa":["Blackfish documentary SeaWorld attendance"]},
{"id":"F23","name":"Jamie Oliver school dinners","oa":["Jamie Oliver school dinners outcomes"]},
{"id":"F24","name":"Oprah effect","oa":["Oprah book club sales","Oprah effect"]},
{"id":"F25","name":"Dr. Oz effect","oa":["Dr. Oz effect supplements sales"]},
{"id":"F26","name":"Queen's Gambit and chess","oa":["Queen's Gambit chess interest"]},
{"id":"F27","name":"Top Gun and recruitment","oa":["Top Gun Navy recruitment film"]},
{"id":"F28","name":"baby names and media","oa":["baby names popular culture television characters","Game of Thrones baby names"]},
{"id":"F29","name":"Sesame Street","oa":["Sesame Street school readiness"]},
{"id":"F30","name":"television introduction","oa":["introduction of television children test scores","arrival of television social capital"]},
{"id":"F31","name":"violent movies and crime","oa":["violent movies violent crime"]},
{"id":"F32","name":"video game releases and crime","oa":["video game release violent crime"]},
{"id":"F33","name":"football games and family violence","oa":["football upset domestic violence"]},
{"id":"F34","name":"sports events and participation","oa":["Olympic Games sport participation legacy","Wimbledon tennis participation","Tiger Woods effect golf"]},
{"id":"F35","name":"World Cup and health","oa":["World Cup cardiovascular events"],"pm":["World Cup[tiab] AND (myocardial[tiab] OR cardiac[tiab] OR cardiovascular[tiab])"]},
{"id":"F36","name":"Super Bowl","oa":["Super Bowl influenza mortality","Super Bowl advertising sales"]},
{"id":"F37","name":"Ice Bucket Challenge","oa":["Ice Bucket Challenge donations"]},
{"id":"F38","name":"Marie Kondo","oa":["Marie Kondo donations thrift"]},
{"id":"F39","name":"smoking in movies","oa":["smoking in movies adolescent smoking"]},
{"id":"F40","name":"medical TV drama","oa":["television drama organ donation","Grey's Anatomy viewers"]},
{"id":"F41","name":"entertainment-education","oa":["radio soap opera family planning Tanzania","MTV Shuga HIV"]},
{"id":"F42","name":"Fox News effect","oa":["Fox News effect voting"]},
{"id":"F43","name":"radio and behavior","oa":["radio propaganda effect"]},
{"id":"F44","name":"songs and sales","oa":["song lyrics brand mentions sales","music video product sales"]},
{"id":"F45","name":"novels and behavior","oa":["novel publication effect behavior","Twilight Forks tourism"]},
{"id":"F46","name":"Harry Potter","oa":["Harry Potter owls trade","Harry Potter reading children"]},
{"id":"F47","name":"Finding Nemo","oa":["Finding Nemo clownfish demand","Finding Dory blue tang"]},
{"id":"F48","name":"Jaws and sharks","oa":["Jaws film shark"]},
{"id":"F49","name":"Babe and meat","oa":["Babe film pork vegetarianism"]},
{"id":"F50","name":"climate films","oa":["The Day After Tomorrow film climate"]},
{"id":"F51","name":"celebrity and vaccination","oa":["Elvis Presley polio vaccine","celebrity endorsement vaccination uptake","Jenny McCarthy vaccination"]},
{"id":"F52","name":"Taylor Swift effect","oa":["Taylor Swift effect"]},
{"id":"F53","name":"streaming series effect","oa":["Netflix series effect demand","Squid Game effect"]},
{"id":"F54","name":"cooking shows","oa":["cooking television shows home cooking","Great British Bake Off baking"]},
{"id":"F55","name":"Mozart effect","oa":["Mozart effect meta-analysis"]},
{"id":"F56","name":"blackout babies","oa":["blackout births nine months later"]},
{"id":"F57","name":"designated driver and TV","oa":["designated driver campaign television"]},
{"id":"F58","name":"Princess Diana","oa":["Princess Diana death suicide","Diana bulimia"]},
{"id":"F59","name":"TV and attitudes plus behavior","oa":["sitcom effect behavior","television show effect behavior natural experiment"]},
{"id":"F60","name":"named media effects","oa":["media effect natural experiment","television program effect difference-in-differences"]},
{"id":"F61","name":"celebrity and diet or health behavior","oa":["celebrity effect health behavior","celebrity endorsement sales effect"],"pm":["celebrit*[tiab] AND (sales[tiab] OR uptake[tiab] OR searches[tiab]) AND effect[tiab]"]},
{"id":"F62","name":"films and career choice","oa":["film effect career choice","television effect college major choice"]},
{"id":"F63","name":"Steve Irwin and wildlife","oa":["Steve Irwin death"]},
{"id":"F64","name":"royal events and behavior","oa":["royal wedding effect","royal baby effect"]}
]
```

64 families, 101 OpenAlex queries, 12 PubMed queries.

## 3. Inclusion rule (screened by hand from title plus abstract)

A paper qualifies only if all hold:
1. It names a specific cultural stone: a film, TV show or episode, song, book, game, celebrity disclosure or death, broadcast, or a public event (sports final, royal event, viral challenge). Generic "media use" or "screen time" is out.
2. It measures an outcome in real behavior or records: sales, purchases, visits, arrivals, enrollments, screenings, tests, births, divorces, donations, registrations, deaths, admissions, crimes, searches tied to an action (search alone counts only as "On the record" grade, never Measured), names given to babies.
3. It compares against a baseline: natural experiment, interrupted time series, difference in differences, regression discontinuity, synthetic control, event study, or a randomized trial of the stone. A plain before and after with no trend or control counts as "On the record" grade, not Measured.
4. Attitude, knowledge, or intention surveys alone are out.
5. Reviews and meta-analyses are kept as context, not as links, unless they report a pooled effect of one named stone.

Nulls: a paper that meets 1 to 3 and finds no effect, or contradicts a famous claim, goes to `busted.csv`, not the main list.

## 4. Extraction (one row per stone and outcome)

stone, stone date, outcome in plain words, population and place, direction, effect size as the paper states it, design, lasting (yes if the paper reports the effect held a year or more, or the outcome is durable, such as a birth, an enrollment, a diagnosis, a death; "short" if it faded within months; "unknown"), quote (the paper's own words, under 25 words), domain, law/government flag, DOI, OpenAlex id, PMID, year, citations.

Domain list: health, money and shopping, food and drink, travel, careers and education, family, environment, language and names, sport and leisure, crime and safety, law and government.
Law/government flag: the outcome is a law, a policy, a vote, a court or jury decision, or a government program uptake.

## 5. Ranking

score = 2 x reach + fame + design + min(3, log10(citations + 1)) + surprise

- reach 1 to 5: 5 = most adults do or face it (food purchases, births, cancer screening, suicide and mental health, travel at large, physical activity); 4 = a large share (a specific screening test, college major, donations, vaccination, wine or alcohol buying); 3 = a sizable group (trips to one country, one product category); 2 = niche hobby (chess, aquarium fish); 1 = very niche. "Relevant to many" = reach 4 or 5.
- fame 1 to 5: would most US adults recognize the stone (5) or only specialists (1).
- design 1 to 4: 4 = randomized or regression discontinuity; 3 = difference in differences, synthetic control, or instrumental variable; 2 = interrupted time series or event study with a trend; 1 = before and after only.
- surprise: +1 if a reader would not guess the link, 0 if plausible, -1 flagged "widely known" (common knowledge, like Jaws and fear of sharks).

## 6. Bars

1. At least 40 distinct qualifying (stone, outcome) links.
2. At least 60% of links outside law and government.
3. At least 20 links rated "relevant to many" (reach 4 or 5).
4. Every shipped candidate verified on its paper's own page (DOI landing page, PubMed abstract, or an open copy of the same paper). Top 30 by score get this check: claim, dates, direction.
5. Stone dates confirmed from a non-Wikipedia source where possible (the paper text, a second paper, a period newspaper for pre-1963 stones). Never from memory.

## 7. Outputs

`raw/` (every response), `data/harvest.jsonl` (every paper with id, DOI, year, citations, abstract), `data/screen.csv`, `data/links.csv`, `data/busted.csv`, `verify/`, `logs/requests.log`, `logs/blocked_hosts.log`, `results.md`.
