# Ripple, the second roundtable: the twelve return, and three who have never seen it (Oct 4, 2026, late)

A simulation. The twelve simulated testers of rounds one to five reconvene, and three net-new simulated testers join
who have never seen the product: **Rosa**, 34, an impact producer at a documentary studio (MacBook, 1512×982); **Dev**,
45, a statistician who moderates a data-visualization forum (Linux desktop, 1920×1080); **Jaz**, 19, a college
freshman (iPhone 15 Pro, 393×852, touch). Nine of the returning testers are fictional; three are simulated personas
modeled on three executive roles (a cloud platform, an engineering-led founder, a consumer-growth lead), labeled as such wherever they appear, not
those people's words. The Founder persona moderates again. The owner asked for both: a re-review by the room, and three
strangers.

Build: `ripple-standalone.html` from main at 0f5cefc2 plus the duplicate-link fix (md5 9ea400fd… before the fix).
Verification ran in headless Chromium through Playwright, one context per persona at that persona's viewport, scale and
input mode; the deuteranopia emulation via CDP for Earl. Scripts `rt2_probe.js` and `rt2_new.js` in the session
scratchpad; the link check ran under the honest user agent at one request a second.

## Part 1: measurements, before anyone speaks

| Persona (viewport, input) | What was checked | Measurement or observed state | Pass? |
|---|---|---|---|
| Dani (390×844, touch) | The first screen and tap exclusivity on the densest engine-found pond (September 11, 8 marks) | No opening screen; pond top 173 px (the header is 126 px on a two-line title); first narration at 2.5 s; 8 of 8 tap centers answer to their own ripple; targets 13.7 to 31.5 px on a pond this dense; 3 labels at rest | Pass |
| Marcus (360×800, touch) | Same, on Android | 8 of 8 right, targets 13.7 to 28.8 px, 2 labels at rest | Pass |
| Lena (375×667, touch) | A shared engine step: `?w=sandy-hook&s=w1` | Opens stopped, focused on "Connecticut's gun law", caption on, no opening screen. The caption covers **76%** of the SE's pond, unchanged since the final roundtable | Pass (the SE caption is still the SE caption) |
| Aisha (1440×900, mouse) | Every engine-found card: a sentence, a source, a date and its precision | 58 stones, 102 marks: 102 with a sentence, 102 with a Wikipedia source URL; 55 dated to the day, 13 to the month, 34 to the year, and the card says which; 1 Disputed, 4 with a note; 58 of 58 stones carry a context line. Link check: 101 distinct article URLs, 99 answer 200; one Wikipedia title was wrong (Canada's Anti-Terrorism Act, fixed) and one mark has no article (OnePulse Foundation, link removed) | Pass after two fixes |
| Earl (1093×614 at 1.25, deuteranopia) | The desktop fold after the header change; the Disputed pill under his eyes | Header 243 px; the pond's foot at **602 px inside a 614-px viewport**; the Disputed pill is coral `rgb(208,74,58)` at luminance .19 against the paper, and its title is struck through, so the grade does not rest on hue; legend top at 652, still below his fold | Pass (fold); legend open |
| Yuki (1280×720, projector) | Beat gaps and the narration size on an 8-mark engine pond | September 11: 8 ripples in 40.3 s, shortest gap 4.5 s; narration 15.7 px, the date line 11.8 px | Pass |
| Tom (1180×820, touch) | Sputnik's statute links survive; the engine card's honesty wording | 3 govinfo links on Sputnik's cards; Enron's "How sure?": "We did not measure this ourselves. The source named on the card records that it happened on this date and ties it to the step before: a sentence in the article names the link with a causal word…" | Pass |
| Priya (1440×900, mouse) | Her one-place rule for grades; the editorial lines | "Not yet" is still a regular expression in the page (5 occurrences); "Disputed" is mapped in 3 places; 148 context lines, one author | Open, as before |
| Walter (820×1180, touch) | Sputnik's first mark and whole run on the beat schedule | First lasting mark at **12.2 s** (5.1 s under the retired trailer); the story runs 38.9 s; the narration sits in flow under the pond on a tablet | Pass (he liked it; see the session) |
| Cloud-exec persona (1440×900) | Reproducibility of the discovery result | `lab/discovery/` holds nine scripts and a README with the exact commands; `docs/results/` holds the stones, pairs, decoys, held-out runs and both blind screens; the record states recall 62%, strict precision 61%, decoys 0 of 50 and "Not met". The checker still runs on branches | Pass (reproducible); governance open |
| Founder persona (1440×900) | The idle bill and the page's weight | One running animation at rest (the wake ring; the two body sheens are gone); the standalone is 1.15 MB with 102 engine marks inlined. The frame-rate probe measured the display's rate, not the page's loop, and is not reported | Pass |
| Growth-exec persona (390×844, touch) | The loop on a phone | First named mark at 2.8 s on Sandy Hook (the stone's first beat is a mark); a share link on an engine step is `?w=sandy-hook&s=w0`; the Engine leads tab now lists **72 chips** | Pass (loop); the wall of chips is his point |
| **Rosa, new** (1512×982) | What a stranger lands on; clicks to the engine-found ponds; what a MeToo card gives her to cite | Lands on Tiger King playing; the chooser is closed behind "Change story · Lasting marks"; Engine leads is two clicks away and its note names the source; the Indonesia card: "Reported", Apr 12, 2022, +4.5 years, a How sure that says what a sentence can and cannot show, and the context line. It showed the same Wikipedia link twice on reverse-hop pairs (fixed in this pass) | Pass after one fix |
| **Dev, new** (1920×1080) | What the page claims and disclaims; whether the discovery numbers are published | Subtitle says "Order, not proof of cause"; the title's arrow is drawn from the weakest link; a measured card carries p = 0.013, placebo wording and the run stamp; the footer links the maps and the discoveries; the record publishes 62%, 0 of 50, 61% and "Not met"; the Top Gun claim shows as Disputed | Pass |
| **Jaz, new** (393×852, touch) | Three seconds, no instructions | At 3 s: the title, the pond at 145 px, one label and the narration "+3 days · The zoo at the center of the show · Measured · Attention 1280× normal"; the play and share buttons at 396 px, in thumb reach. At 9 s: still **0 lasting marks** on Tiger King; the first arrives at about 17 s. The share button's effect could not be measured in headless Chromium | Pass (first screen); the payoff is late for her |

## Part 2: the session

**MODERATOR (simulated persona: an engineering-led founder):** Since the last room: a bug we
all missed, a slower clock, a flatter face, and an engine that now shows its work in the product. Three people here
have never seen it. They go first, one sentence of first impression, then the twelve re-rate. Jaz.

**Jaz:** It started playing and I knew what it was in three seconds, the water thing, the show, a ring with a name on
it. I didn't touch anything. Nothing I'd screenshot had happened by the time I'd normally leave.

**Dev:** I came to catch it overclaiming and it kept saying "order, not proof of cause" before I could. The arrow in
the title is drawn from the weakest link, the p has a placebo behind it, and the engine's own precision is published
as 61% with "not met" next to it. My complaint is that the engine tab is almost all "reported." That's honest. It's
also a lot of gray.

**Rosa:** Two clicks to the thing I'd actually use, and then a card I could put in a funder report: a law, a date, the
sentence, the link, and a line saying what else was going on. I'd want to export that card. It showed me the same
link twice, which is the kind of thing a funder notices.

**MODERATOR:** Returning testers. Walter, the trailer you asked for is gone and the first mark now comes at twelve
seconds instead of five.

**Walter:** And I prefer it. Five seconds was a slot machine. Now a name arrives, I read it, the next one arrives. Twelve
seconds to the first law is fine when I can read the three steps before it.

**Dani:** On my phone the first law is at seventeen seconds. That's a long time to look at rings. I like that it tells
me what each one is now. I'd still want the law sooner, or something that tells me it's coming.

**Yuki:** For a room it is right. Four and a half seconds between ripples on a nine-mark pond, a sentence under the
pond the back row can read, and a Disputed card I can put on the board and ask "why did the record change its mind."

**Marcus:** Eight out of eight taps on the densest pond went where I put my finger. Last time three of eleven didn't.
And the words are on the water now, not in boxes.

**Lena:** The link I'd send opens on the law. The caption still eats three quarters of my pond, same as last time; I
have learned to tap it away.

**Aisha:** A hundred and two engine-found marks and every one has a sentence I can read and a page I can open; two
links were wrong and were fixed in this session. What I would cite is different now: not "the show changed the law,"
but "the record that made the law names the show," and the card says exactly that.

**Tom:** The statutes are still one click away on Sputnik. The engine cards say "we did not measure this ourselves"
in the first sentence. That is the sentence I wanted on every card that is not green.

**Earl:** My fold is fixed; the pond's foot is inside my screen for the first time. The Disputed pill is struck
through, so I do not need to tell its red from anything. The legend is still under the fold.

**Priya:** The grade lives in two places still, and now Disputed is mapped in three. It works; it is debt. The product
is the credibility model I asked for, extended to the engine's own finds.

**CLOUD-EXEC PERSONA (simulated persona: a cloud-platform executive):** I asked for the
discovery to be reproducible and it is: scripts, a README with the commands, the stones, the decoys, the held-out set
and both blind screens in the repository, and a result document that states the bar and says it was not met. That is
the right way to miss a bar. The checker is still on branches.

**GROWTH-EXEC PERSONA (simulated persona: a consumer-growth executive):** The loop is
unchanged and tight. Seventy-two chips in one tab is a wall; the engine shelf needs a shape, by kind or by decade,
before the hundredth stone.

**MODERATOR:** My own. One animation at rest where there were three, no gradient to composite, and 1.15 megabytes
with a hundred engine marks inlined. The engine is a candidate generator with its precision printed on it, which is
more than most engines admit. Numbers. One sentence each.

**Aisha:** 9; a hundred and two cited marks and the sentence that fits each one.
**Tom:** 9; the honest sentence is now the first sentence.
**Lena:** 8; the link opens on the law and my pond is still three quarters caption.
**Marcus:** 9; eight for eight.
**Yuki:** 9; a Disputed card is a lesson plan.
**Earl:** 8; my fold is fixed and the legend is still under it.
**Dani:** 8; seventeen seconds to the law on my phone.
**Priya:** 8; the model holds; the debt is in three places now.
**Walter:** 8; I prefer the clock, and twelve seconds is the price.
**CLOUD-EXEC PERSONA:** 8; reproducible, published, not yet on main.
**MODERATOR:** 7; lighter and more honest, still a hand-screened engine.
**GROWTH-EXEC PERSONA:** 8; the loop is tight and the shelf needs a shape.
**Rosa:** 8; I'd put a card in a report tonight if I could export it.
**Dev:** 7; it says what it cannot prove, and most of what the engine found is gray.
**Jaz:** 7; I got it in three seconds and nothing happened for seventeen.

## Ratings

| Persona | First-ever | Final roundtable (Oct 4, 05:00) | **This room (Oct 4, late)** |
|---|---|---|---|
| Aisha | 5 | 9 | **9** |
| Tom | 7 | 9 | **9** |
| Lena | 6 | 9 | **8** |
| Marcus | 5 | 8 | **9** |
| Yuki | 6 | 9 | **9** |
| Earl | 6 | 8 | **8** |
| Dani | 4 | 8 | **8** |
| Priya | 5 | 8 | **8** |
| Walter | 5 | 9 | **8** |
| Cloud-exec persona (simulated) | 6 | 7 | **8** |
| Founder persona (simulated) | 5 | 7 | **7** |
| Growth-exec persona (simulated) | 6 | 7 | **8** |
| **The twelve, average** | 5.5 | 8.2 | **8.3** |
| Rosa (new) | | | **8** |
| Dev (new) | | | **7** |
| Jaz (new) | | | **7** |
| **All fifteen, average** | | | **8.1** |

The three strangers averaged 7.3 against the room's 8.3: the gap between people who watched it get better and people
who see it once. Their three complaints are the same three the measurements show: the first lasting mark arrives
late on a phone (17 s on Tiger King, 12 s on Sputnik), the engine shelf is a wall of 72 chips, and the engine's grades
are almost all reported.

**Verdict:** release Monday morning as planned. First-week items, in order: the time to the first lasting mark on a
phone (an earlier first beat for a mark, or a visible promise of one); a shape for the Engine leads shelf (by kind or
decade); the legend under a 614-px fold and the caption on a 375-px pond, both carried over; an export of an
engine-found card for people like Rosa. Builder's own rating after this room: **8.0**.

## Actions (Oct 5, 2026, 01:30 UTC): every item in the room, built the same night

| Finding | Who | What was built | Measured after |
|---|---|---|---|
| The first lasting mark arrives late on a phone (17 s on Tiger King) | Dani, Jaz, Walter | The ordinary beats before the first mark hold 1.8 s instead of 2.6 and travel at most 1.0 s; measured steps before it hold 3.2 s instead of 4; and from the first beat the narration says what is coming: "Next lasting mark: License suspended · 3 ripples away" | First mark at **15.3 s** (16 s allowed; the two measured steps before it keep a hold a reader can use); the promise line at **2.2 s**. Tiger King runs 28.1 s, Sputnik 35.4, Prohibition 75.8; no two beats under 2.2 s apart. `fold_test.js` |
| The Engine leads shelf is a wall of 72 chips | Growth-exec persona | The shelf is grouped under small headings: "From Wikipedia's record · 2010s" by the stone's decade, "From Parliament and Congress", "From attention" | Headings render as full-width rows in the picker |
| The legend sits under a 614-px fold | Earl | On a laptop screen 700 px or shorter, the legend becomes a corner panel over the pond's top right, like a map's | Legend bottom **482 px** inside a 614-px viewport; pond's foot 602 |
| The caption covers 76% of a 375-px pond | Lena | A pond shorter than 220 px keeps its water: the caption flows under it instead of over it | Caption covers **0%** of the SE pond |
| An export of an engine-found card | Rosa | "Copy citation" on every engine card: the stone, the mark, the date, the grade, the sentence and its source, the context line and a link to the step, as one line | Present on 102 cards; copies to the clipboard, falls back to a prompt |
| The engine's grade lives in two places | Priya | The engine kind reads its grades from one map (`WGRADE`) | "Disputed" and "Reported" defined once for the kind; the chain checker's grades are still its own |
| The checker runs on branches only | Cloud-exec persona | The chain-check workflow now also runs on pushes to main that touch the chains, weekly on Monday mornings, and by hand | `.github/workflows/ripples-chain-check.yml`; the results commit back to the branch it ran on |
| Decoys should match the stones' fame | Dev | Fifty of the highest-grossing films of 2005 to 2024 run through the culture reading and the strict reverse rule (`docs/results/famous_decoys_v1.json`) | 46 of 50 produced nothing a screener would keep; 3 produced a "banned in one country" sentence (Deadpool, Wonder Woman, Lightyear) and 1 an industry claim (The Dark Knight and the comic-book boom): **8% under the loosest reading, 0% under the strict reverse rule**, both under the registered 1 in 10. Country bans are a thin mark class and will carry less weight in the next lexicon |
| Most engine grades are reported | Dev | Stated as such on the tab and on every card; the way up is the series, not the prose (see `discovery_culture_v1.md`) | Open by design |
| Two wrong links, one duplicate | Aisha, Rosa | Fixed in this pass | 99 of 101 article links answer; the other two corrected or removed |
