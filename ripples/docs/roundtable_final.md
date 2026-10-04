# Ripple, round five: the final review (Oct 4, 2026)

A simulation. The same twelve simulated testers as the first roundtable reconvene for one question. Nine are fictional testers (Dani, Priya, Walter, Marcus, Yuki, Earl, Aisha, Tom, Lena). Three are simulated personas modeled on the public roles of Thomas Kurian, Elon Musk and Mark Zuckerberg; they are labeled as such wherever they appear, they are not those people's words, and nothing below is anyone's real statement. The Musk persona moderates again.

Build: `ripple-preview11.html` (md5 2603837e…). Verification ran in headless Chromium through Playwright, one context per persona at that persona's viewport, scale and input mode. Verification scripts and screenshots stayed in the session scratchpad.

## Part 1: verification, before anyone speaks

| Persona (viewport, input) | What was checked | Measurement or observed state | Pass? |
|---|---|---|---|
| Walter (820×1180, touch) | Shipped #1, the ten-second trailer, on Sputnik; his next point was Prohibition's back-loaded autoplay | Sputnik (`?c=sputnik-nasa-arpa`): first lasting mark (ARPA created, Institution) blooms at **5.1 s**; the five marks bloom (ARPA 5.1 s, Space Act 6.5 s, Education Act 7.0 s, NASA opens 7.5 s, ARPANET 9.3 s); the four plain reported steps (Sputnik 2, Vanguard fails, Explorer 1, Space agency proposed) land quiet; all nine down by 9.3 s; `cur.trailer` = true; 0 steps still quiet 1.5 s after rest (they wake). Prohibition: 25 steps land between 4.0 s and 9.9 s, 5 loud (Repeal, AA, NIAAA, NA beer, the measured cancer-warning attention), 20 quiet. Round four was about 25 s with eighteen in the last six. | Pass |
| Aisha (1440×900, mouse) | Shipped #2, the arrow drawn from the weakest link; her kill vote was the surprise axis (not built) | Tiger King: `.arw.l-plausible`, stroke-dasharray `0.1px 4.5px` (dotted), color straw `rgb(217,201,152)`, tally ends "weakest link plausible", subtitle "…The arrow is drawn from the weakest link on the way there: dotted, a link is unproven. Order, not proof of cause." Sputnik: `.arw.l-reported`, dasharray `5px 4px` (dashed), white, "weakest link reported". The Jungle: dashed, "weakest link reported". A volcano → the bicycle: dotted, plausible. Squid Game: no arrow in the title at all, tally "No lasting mark yet … weakest link plausible". Hover title on the arrow: "The weakest link on the way to the mark is plausible." | Pass |
| Lena (375×667, touch) | Shipped #3, share a step; her kill vote was the printable sheet (not built) | Card link text "Share this step"; caption link text "Share"; `shareStep` produces `https://bensunter.com/ripples/demo/?c=columbine-active-shooter&s=c3` and the toast "Link to this step copied". `?c=columbine-active-shooter&s=c3` opens with the intro skipped, stopped (`playing` false, t = 0.468), focused on **"Sheriff's report · Reported · May 2000 · +13 months"**, caption open with "Read the card ↓" and "Share". On the SE the caption (134 px) covers 77% of the 175-px pond. | Pass (pond mostly hidden behind the caption on the SE) |
| Yuki (1920×1080, mouse) | Shipped #5 as built: the claims line, and whether the smartphone claim still steps before the trend it is about | The 1980 card ("Per-capita drinking climbs back for half a century and peaks around 1980", pond label "Drinking peaks (1980)") carries exactly: **"People say this started with: Smartphone claim (Jul 2012; tested: came after, busted as the origin); Dry January claim (Jan 2013; tested: came after, busted as the origin); Cannabis claim (Jan 2014; tested: came after, busted as the origin)."** Step order now: Teen drinking halves is stop 9, the Smartphone claim stop 13 (round four: claim at stop 10, trend at stop 19). Pond label type 13.5 px (was 12). | Pass (the line sits on the peak card, not on the two decline cards) |
| Kurian persona (1440×900, mouse) | Shipped #4 as gated: the run stamp on a Measured card after the truncation test (13 grades, 0 flips) | Tiger King Measured card, How sure: **"Checked Oct 4, 2026 with checker b0aa6fd; the placebo windows come from the page's history before the step, so a later run changes this only if the post-step window was still open."** `DATA.run` = 2026-10-04, `DATA.sha` = b0aa6fd, both present in the card text. | Pass |
| Priya (1440×900, mouse) | Step as a button; "Not yet" styling; her kill vote was ask-for-a-stone (not built) | Six presses from a paused Tiger King advanced six ripples in order (Wynnewood, Big Cat Rescue, Exotic pets, Wildlife trade, License suspended, House passes), `aria-pressed` true throughout; `dblclick` set `stepMode` false and restored the trailer title. Frozen's 2032 card: class `card notyet`, pill "Not yet" in `b na` (gray `rgb(126,139,142)`, dashed hairline border), no line-through rule on `.notyet` (the busted card beside it keeps the red pill and the struck h2). The grade is still mapped on the page (`/not yet/` on the verdict), not in the checker. | Pass (styling); her one-place rule, not done |
| Marcus (360×800, touch) | The 44-px tap target and the caption on Squid Game | Hit circles 40.4–49.2 px across the 11 ripples (10 of 11 at or above 43 px). Tapping 18 px off Ddakji focused Ddakji, caption on, 1 label shown, 0 leaders. But on this 324-px pond the targets overlap each other: `elementFromPoint` at the center of "111m accounts" returns "$891m valuation", the center of "Network-fee bills" returns "Settlement", and the center of "$891m valuation" lands on a text element; 3 of 11 centers do not answer to their own ripple. Caption 336–469 px inside the pond's 312–480 px, controls stay at 480 (no jump); "Read the card ↓" 246×33 full-width button; "Share" link. Smallest pond text still 8.5 px. | Partial: size passes, exclusivity fails on dense ponds |
| Dani (390×844, touch) | Same, on Tiger King | Hit circles 39–47.8 px; caption 386–482 inside pond 309–492, controls at 492 unchanged; "Read the card ↓" 276×33; "Share" present; 0 label leaders until a tap; 5 labels at rest. "Big Cat Act becomes law" center resolves to a neighbor at every offset tried (it sits on "House passes Big Cat Act"). Header 264 px above the pond. | Partial: same overlap on the two Act ripples |
| Earl (1093×614 at 1.25, mouse, deuteranopia emulated via CDP) | Lit connectors colored by what they lead to; quiet trailer dots under his view | Focus on the measured "Cancer-warning attention": 2 lit edges, measured one green `rgb(127,191,123)` solid, plausible one straw dashed `6px 5px`, opacity .9; unlit edges opacity 0. Focus on the mark "Repeal": 12 lit, the four that lead to a mark marigold `rgb(242,169,59)`, reported ones white, plausible dashed. Prohibition at rest: 13 labels drawn, **0 overlapping pairs** (round four: about fourteen colliding). Quiet dots at 4 s: node opacity .45, ring .22; under deuteranopia the one quiet step on screen is a faint stroke on the ring, close to invisible until it wakes. Legend top at 656 px on a 614-px viewport, still below his fold. | Pass (connectors); quiet dots are, by design, hard to see |
| Tom (1180×820, touch) | Sputnik's marks and their citations; his next point was linking the Pub. L. themselves | Five marks: ARPA created (Institution, Feb 1958, +4 months), Space Act (Law, Jul 1958, +10 months), Education Act (Law, Sep 1958, +11 months), NASA opens (Institution, Oct 1958, +12 months), ARPANET (Infrastructure, Oct 1969, +12.1 years). Source lines: "Pub. L. 85-325, February 12, 1958", "Pub. L. 85-568, 72 Stat. 426, signed July 29, 1958", "Pub. L. 85-864, 72 Stat. 1580, signed September 2, 1958". 9 of 10 cards link out, all to Wikipedia; "Eisenhower asks Congress" has no link; no govinfo or congress.gov link on any Sputnik law. | Pass (marks); his next point not done |
| Zuckerberg persona (390×844, touch) | Deep link skips the intro; the phone first screen; time to the payoff | `?c=squid-game-ripples`: intro not shown, title "Squid Game, beyond TV", header 245 px, pond at **290 px** down, 354×183, 23-word subtitle, hint box sitting on the pond. Tiger King on the phone: first ripple 2.2 s, first mark (License suspended) 6.9 s, "Big Cat Act becomes law" at **9.2 s** (round four: 14 s); the three plain steps land quiet and all wake at rest. | Pass (loop and payoff); first screen unchanged |
| Musk persona (1440×900, mouse) | Idle cost and the filter count | rAF 30.2 fps during the trailer, 33.4 fps at rest; the page still registers about 32 rAF callbacks a second at rest (160 in 5 s). CDP task time **107 ms/s during the trailer, 32 ms/s at rest** (script 1 ms/s), with 14 layouts/s and 25 style recalcs/s at rest from the two CSS animations (`sheen`, the 7-s `pulse`); 0 long tasks in either 5-s window. Filters: 3 `feTurbulence`, 7 `<filter>` defs, 1 `filter=` attribute, 8 elements with a CSS filter; stripping them at rest changed task time within noise (44 ms/s), so the water filters are no longer the idle cost. Page 1,072,493 bytes. | Pass (idle); the trailer still burns 107 ms/s |

## Part 2: the session

**MODERATOR (simulated persona modeled on the public role of Elon Musk; not his words):** Five ideas shipped, one gate test ran. I am not asking whether you like it. I am asking the proposer and the person who voted to kill it whether the build passes their own falsification test, as far as one reviewer can judge, and what is still wrong. Idea one, the trailer. Walter, you proposed it. Yuki, you said kill it unless the reported steps were one tap away.

**Walter:** My test was six in ten first-timers naming the lasting mark at ten seconds. I cannot run thirty strangers, but I can say what the clock did: on Sputnik the first mark bloomed at five seconds and the fifth at nine, and the four steps in between landed without a word. Prohibition, which took twenty-five seconds and dumped eighteen in the last six, now takes ten and speaks five times. When it stopped, every quiet one woke up and I could read it. That is the thing I asked for.

**Yuki:** The condition was that the reported spine is one tap away, and it is: Step walks every step, and at rest the quiet ones come back. I withdraw the kill. What is still wrong is that on a projector the quiet dots are ghosts; a student at the back sees five rings appear and will ask where the other twenty came from.

**MODERATOR:** Idea two, the arrow. Aisha proposed. Dani defended the old arrow, which is the nearest thing to a kill vote.

**Aisha:** The test was thirty readers and a third fewer saying "the show caused the law." I have one reader, me, and I can report the state: Tiger King's arrow is dotted and straw, the tally says "weakest link plausible," and the subtitle says it in words. Sputnik and The Jungle are dashed. Squid Game has no arrow at all because there is no mark. My desk's question, "does the title promise more than the worst card," is now answered on the page itself. I would cite it.

**Dani:** It still says "Tiger King → the Big Cat Act," the arrow's just dotty. I'd still send it. If anything the dotted one looks like it's loading, but whatever, the sentence is the same sentence.

**MODERATOR:** So the brand kept its shape and the shape now carries a grade. Idea three, share a step. Zuckerberg persona proposed it. Kurian persona voted to kill it until a shared step carried a run id.

**ZUCKERBERG PERSONA (simulated persona modeled on the public role of Mark Zuckerberg; not his words):** My test needs two weeks of clicks, which nobody here has. The mechanics pass: every card has "Share this step," the caption has "Share," the URL is `?c=columbine-active-shooter&s=c3`, and it opens stopped on the Sheriff's report with the caption up and no interstitial. That is the loop I asked for. What is wrong is upstream of it: on a phone the pond still starts 290 pixels down, and on Lena's screen the caption covers three quarters of the pond it is captioning.

**KURIAN PERSONA (simulated persona modeled on the public role of Thomas Kurian; not his words):** I asked for the test before the id, and the test ran: thirteen measured grades, three cutoffs, zero flips, and a reason in the code. The placebo pool is fixed on the day of the step. So my kill condition dissolves on its own evidence; the grade a shared link spreads is a constant of the data. The card now says "Checked Oct 4, 2026 with checker b0aa6fd" and tells the reader the one case in which a later run could differ. I withdraw the kill. What is still wrong is governance, not the page: the checker still runs on branches, not on main or a schedule, and the "Not yet" grade is a regular expression in the HTML.

**MODERATOR:** Idea four was yours, gated. Does the gate's result embarrass the idea?

**KURIAN PERSONA:** No. It settles the narrow claim and leaves the wide one. The null was worth the afternoon.

**MODERATOR:** Idea five, Step follows the argument. Yuki proposed. Priya voted for the "Not yet" rule in the same breath; Walter wanted Step as the second act.

**Yuki:** They built something different from what I asked, and I think better. The claim does not move; the trend card names it. The 1980 card reads, exactly, "People say this started with: Smartphone claim (Jul 2012; tested: came after, busted as the origin); Dry January claim…; Cannabis claim…" and in Step the teen card now arrives at stop nine and the smartphone claim at thirteen. My two-class test would compare orders; the build made the order matter less by putting the rebuttal where the question is asked. One quibble: the line is on the peak card and not on the two decline cards, and the claims are about the decline.

**Priya:** Step passes. Six presses, six ripples, double-press back to the trailer, and the button says what it does. "Not yet" is a gray dashed pill with no strikethrough, which is what I asked for on screen. What is still wrong is my own one-place rule: the future is still the busted grade wearing a different coat, mapped on the page. That is a maintenance debt, not a reader's problem.

**MODERATOR:** Now the thing none of you proposed and two of you measured. Marcus.

**Marcus:** The circles are 44 now, I measured 40 to 49. But Squid Game's pond is 324 pixels wide and the circles sit on each other. I put my finger dead center on "111m accounts" and got "$891m valuation." Three of eleven do that. Dani's got the same thing on the two Act ripples. So the target is big enough and it still answers for the neighbor.

**Dani:** Yeah. The caption's good, it sits on the pond and the buttons don't jump anymore. But tap the law and you get the House vote.

**Earl:** For the record, the Prohibition labels do not collide anymore at rest, zero pairs where there were fourteen, and the lit lines are colored by where they go: green to the measured one, orange to the laws, dashed straw to the guesses. I can read that under my eyes. The legend is still below my fold.

**Tom:** Sputnik's five marks are right, and the Pub. L. numbers are on the cards, 85-325, 85-568, 85-864. They still link to Wikipedia and not to the statute. Better, not finished, same as last time.

**MODERATOR:** My own. At rest the page costs 32 milliseconds a second and one of script; the filters are no longer the idle bill, the two CSS animations are, and that is cheap. The trailer still costs 107. The loop still asks for a frame thirty times a second while nothing moves. Acceptable. Final numbers. One sentence each.

**Aisha:** 9; the title finally promises what the worst card can keep, and I can see which run said so.

**Tom:** 9; everything I checked holds, and the statutes themselves are one link away from being citations.

**Lena:** 9; the link I'd send opens on the thing I'd send, even if the caption eats my pond.

**Marcus:** 8; it reads, it taps, and on my show it still sometimes answers for the dot next door.

**Yuki:** 9; it went from a tool I'd assign to one I'd grade with, and the quiet dots need a word for the back row.

**Earl:** 8; the lines mean something now and nothing on the water lies to my eyes, but the legend is still under the fold.

**Dani:** 8; the throw, the story, the ten seconds, and a law I can send to the group chat.

**Priya:** 8; Step is a button, "Not yet" looks like what it is, and the rule still lives in two places.

**Walter:** 9; it waits for me, it speaks five times in ten seconds, and the rest is there when I stop.

**KURIAN PERSONA:** 7; the gate test turned a liability into a stamped constant, and the pipeline still runs on the wrong branch.

**MODERATOR:** 7; it looks like the part that is true now, and it still spends a hundred milliseconds a second to do it.

**ZUCKERBERG PERSONA:** 7; the share loop is tight, the first screen on a phone is where it was in round four.

**MODERATOR:** Verdict. One question: release publicly now, or not. Ten of twelve scored it eight or above; nobody scored it below seven; every kill vote from the first session was withdrawn on evidence, and the one failure we found is a tap on a dense pond answering for its neighbor, which is a first-week fix and not a reason to hold a public page. The room says release now. The condition, had it been no, would have been that one: no two 44-pixel targets overlap on any phone pond.

## Final ratings

| Persona | First-ever rating | Round four | Final | Their one line |
|---|---|---|---|---|
| Aisha | 5 | 8 | **9** | The title promises what the worst card can keep |
| Tom | 7 | 9 | **9** | Statutes are one link away from being citations |
| Lena | 6 | 8 | **9** | The link opens on the thing I'd send |
| Marcus | 5 | 7 | **8** | Still sometimes answers for the dot next door |
| Yuki | 6 | 8 | **9** | A tool I'd grade with |
| Earl | 6 | 8 | **8** | Lines mean something; legend still under the fold |
| Dani | 4 | 7 | **8** | A law I can send to the group chat |
| Priya | 5 | 7 | **8** | The rule still lives in two places |
| Walter | 5 | 7 | **9** | It waits for me |
| Kurian persona (simulated; not his words) | 6 | 6 | **7** | Stamped constant; wrong branch |
| Musk persona (simulated; not his words) | 5 | 5 | **7** | Looks like the part that is true |
| Zuckerberg persona (simulated; not his words) | 6 | 6 | **7** | Loop tight; first screen unchanged |
| **Average** | **5.5** | **7.2** | **8.2** | |

**Verdict:** release publicly now. No condition attached; the first-week fix is the overlapping tap targets on dense phone ponds (Squid Game, the two Tiger King Act ripples). Other open items, none blocking: the phone header (245–290 px above the pond), the caption covering most of a 375-px pond, the legend below a 614-px fold, the statute links, the quiet dots' visibility on a projector, "Not yet" as a checker grade, CI on main.
