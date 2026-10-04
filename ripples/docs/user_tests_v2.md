# Ripple v1: three more persona tests (Oct 4, 2026)

Round two, after every row of round one (`user_tests_v1.md`) was closed. Three new profiles, chosen to differ from the first three in age, device, background and what they want from the page. As before, each persona was played by an agent driving the real page with Playwright in that person's viewport and input mode, with a task script and a brief; the reports below are theirs, verbatim. These are simulated users, not recruited ones. Measurements (font sizes, tap targets, color differences) are real and were taken from the running page.

| | Device | Build tested | Rating |
|---|---|---|---|
| Marcus Dela Cruz, 24, warehouse worker and night student, Fresno (born Manila) | Android phone, 360×800, touch | after PR #74 | **5 / 10** |
| Yuki Tanaka-Olson, 42, 11th-grade US History teacher, Minneapolis (born Sapporo) | Classroom projector 1920×1080 and a 1366×768 Chromebook | after PR #74 | **6 / 10** |
| Earl Whitcomb, 58, freight dispatcher, Zanesville OH, red-green colorblind | 1366×768 laptop at 125% scaling, mouse only | after PR #74 | **6 / 10** |

Round one averaged a little higher on paper, but round one's testers were asked different things. These three were asked to read the page as a skeptic, a teacher and a commuter, and the pattern in what they hit is the useful part.

## 1. Marcus, 24, Fresno (Android 360×800, touch)

Okay so I opened it on my break. First screen is this dark pond thing with "Throw a stone. See what it changed." and a big yellow button that says "Throw a stone". I didn't really read the paragraph under it, I just hit the button. Took me maybe five seconds. I thought it was gonna be a game, honestly.

Then it's a page about "Mr Bates → convictions quashed by law". I have no idea who Mr Bates is. A rock drops into the water from the top of the screen, not really a throw, more like it fell. Rings come out but only to the left side, like a half-ripple. Little black tags pop up, "Scandal attention", "Vennells attention", and then after that nothing else gets a tag even though it says 8 ripples. The words around the edge like "JUSTICE & LAW" and "1 year" are tiny, I'd need to zoom. Also a message "Press play or drag the slider · tap a ripple to follow it" sat right on top of the slider for like nine seconds, so I couldn't see the slider it was telling me to drag.

I hit "Change story" and Squid Game was right there in the "Start with one you know" row. Two taps, that part was easy. But the first line under Squid Game is "No lasting mark found yet: what changed is attention, money or hype, not a law..." which kind of felt like the site telling me my show doesn't matter. The pond said 11 ripples but only "Ddakji craze" got a label. I tapped one of the little dots (they're really small, like a grain of rice) and it said "SQUID token scam" and everything else went dim. That was cool. But nothing else happened on screen, I had to scroll way down to find the card about it, and it's like two screens down.

"Step" turned yellow when I tapped it and nothing moved. Then I hit play and it stopped at "SK Broadband suit". I get it now, it pauses at each one, but the card it's supposed to show is below the fold so you just see the clock stop.

The cards down below are actually good. "Interest in ddakji surges, 6499.7× normal" with a little spike chart, I'd send that. The source link under Details is just "Search Wikipedia ↗" and it searches for the sentence "the SQUID token's developers vanished on 1 Nov 2021". That's not a source, that's a Google search. The Ddakji one goes to the real Wikipedia article, that one I trust.

I tried grabbing the stone when it was sitting on the bank. It moved like a centimeter and then threw itself. Share button said "Link copied", fine.

I'd give it a 5. The pond looks nice and the Squid Game stuff is actually interesting, but on my phone half of it is unreadable, the labels disappear, and tapping a ripple doesn't show you anything unless you scroll. My friend would look at it for ten seconds and go "what am I looking at".

### Marcus: what the tester measured

- Pond renders 324×168 px at 360 wide (scale 0.345). Ripple labels 7.6 CSS px, rim words 5.9 px, "1 year" 5.2 px, stone name 7.6 px. (Builder's note: the new text floor should give 11 px here; the discrepancy is being checked. Either way the rim words and ring label have no floor and are too small.)
- Tappable ripple element is the 10–12 px node; the label is not a target.
- Label collisions: Squid Game shows 1 of 11 labels at rest, Mr Bates 3 of 8.
- Tapping a ripple lights the card 900–1,700 px below the pond; nothing readable changes in the viewport. Step mode has the same problem on a phone.
- Drag-to-throw under touch: the pond's `touch-action: manipulation` makes Chrome fire `pointercancel` after two moves, and the release handler throws the stone early. In autoplay the drag window is about 450 ms, so the drag is effectively unreachable.
- First-visit hint sits over the slider for 9 s while telling the user to drag the slider.
- Stone at rest is clipped by the pond's rounded corner; the feed is an empty cream strip before the first card.
- Reported cards also get a sparkline (SK Broadband), which makes Reported look Measured.
- Copy: "No lasting mark found yet: what changed is attention, money or hype…" as the first line under Squid Game and Frozen; "Named in the passage of 1 law, 1 of them as a reason given for the bill" for Tiger King.
- Step tapped at story end does nothing visible.
- Console: negative `ry` / `r` attribute errors during the drag flow.
- Worked: the intro, two taps to a known story, no horizontal overflow, the page not jumping on a tap, the cards (he would screenshot the ddakji card), the focus dimming, share's toast.

## 2. Yuki, 42, Minneapolis (projector 1920×1080, Chromebook 1366×768)

Hi,

I spent about forty minutes with Ripple on my classroom machine (1920×1080, Chrome, no extensions) and on a 1366×768 window to stand in for our Chromebooks. It loaded in under a second from a plain file, with zero console errors, which already puts it ahead of half the edtech I'm sent.

The intro is lovely but it never mentions the thing I'd be teaching. "A show, a film, a disaster, a discovery. Its ripples spread out in time, each one rated for how sure we are" — fine, but the five ratings (Measured / Timed / Reported / Plausible / Busted) only appear as a 12.5 px legend under the pond and in the "How it works" text at the very bottom of the page, where the four headings are dark gray on dark navy and nearly invisible. The text itself is good and short (about 300 words); I'd just move "How sure" up and give it light type. I didn't know "How it works" was a page section rather than a popup until the page scrolled.

Finding stories: "Change story" → "Prohibition" is two clicks, same for "A volcano → the bicycle." The search box found "1920," "prohibition," "tambora," and "silent spring" correctly, and told me honestly that nothing matches "dust bowl," "flu," "1918" or "new deal." So from my list I can use Prohibition, Tambora, and Silent Spring. The rest of the catalog is mostly British television and Parliament (Mr Bates, Cathy Come Home, Quincy, Victim 1961), and the default story on cold open is the Post Office scandal, which means nothing to a Minneapolis 16-year-old. I would not put the Engine leads tab on a projector: Saltburn, Adolescence, Squid Game are on it, and "An angina drug → Viagra" sits in Fact-checks.

Step mode is the best thing here. Each stop opens one card with a date, a badge, a one-line reason. The Busted cards are exactly right: "Claim: smartphones started the teen decline" with the line "Came after what it claims to have started," and under How sure?, "The decline began some thirty years before most teens had a smartphone. As the origin, busted; as an accelerant after 2012, open." A junior can restate that. The p-value is explained in plain words on the Measured card: "a jump this big showed up at only 3.5% of them (p = 0.035)." Thank you.

Two things would trip a class. First, in step order the smartphone claim (2012) appears before the teen-drinking card it refers to (Dec 1, 2019), and the last six cards are out of date order (Aug 2025 sits above Dec 2023). Second, the sources. Almost every card ends in "Search Wikipedia ↗," and the link is literally a Wikipedia search for the entire source string, e.g. "Miron & Zwiebel (1991): consumption fell to 30–40%…". That is not a citation; I can't let students call it one. Only the three real "Wikipedia article ↗" links and the (broken-under-file://) "How we tested it" are usable.

Conventions: card headers are American ("Jan 17, 1920") but every source line is British ("17 Jan 1920," "5 Dec 1933"). Placeholder dates like "Jul 1, 1922" and "Jan 1, 1864" print as if exact, while the one ranged step honestly says "≈ 1817." There is a double period ("Ordered against AA's founding..") and an empty "Wikipedia daily views: ·" label.

Projector: the pond is 663 px wide on a 1920 px screen and its labels render at 9.5 px (rim labels 7 px, "1 year" 6.4 px). Nobody past the second row will read it. The cards are 13–15 px. On the Chromebook everything fits with a little scrolling, which is fine.

Rating: 6/10. The reasoning is honest and teachable; the sourcing and the projector legibility aren't there yet.

Yuki

### Yuki: what the tester measured

- Zero page errors; 277 ms load from a file.
- Pond at 1920×1080: 663×343 px (the layout caps the column). Labels 9.5 px, rim words 7.1 px, "1 year" 6.4 px, "◆ Law" 7.8 px. Cards 13–15 px.
- Sources: 23 of 26 Prohibition cards and 5 of 5 Tambora cards end in "Search Wikipedia ↗" with the whole source string as the query; the Tambora oat-prices card searches its own claim text.
- Order: the smartphone claim (dated Jul 1, 2012 under the must-precede rule) steps seven stops before the "teen drinking falls for four decades" card it refers to (Dec 1, 2019); the feed's last six cards are out of date order (Aug 13, 2025 above Dec 1, 2023, then Undated, then Jan 3, 2025).
- "How it works" headings are near-invisible (dark gray on navy); the five-level ladder is explained only there and in the 12.5 px legend. (Builder's note: the heading color was set to ink in round one; the preview the testers used shows otherwise, so the fix did not take and must be re-checked.)
- Date style: card headers US ("Jan 17, 1920"), source lines day-month ("17 Jan 1920", "5 Dec 1933", "3 Jan 2025").
- Placeholder dates (1922-07-01, 1973-07-01, 1980-07-01, 2012-07-01, 2019-12-01, 1816-06-01, 1864-01-01) print as exact days.
- Catalog: for a US History unit only Prohibition, Tambora → bicycle and Silent Spring exist; nothing for the Dust Bowl, 1918 flu or New Deal; Engine leads lists Saltburn, Adolescence, Squid Game; Fact-checks lists "An angina drug → Viagra"; Lasting marks lists "Super Bowl 2004 → FCC crackdown".
- "How sure?" on Reported cards nests the whole source string in parentheses, producing 60-word sentences.
- Dose-response card jargon: "CDC BRFSS state prevalence (dttw-5yxu)", "permutation p = 0.1, pre-trend p = 0.3417", "first rung above timing". "p = 0.023" on Mr Bates cards is unexplained on the face.
- Keyboard: ripples are focusable with good labels; Enter, Space and → work; ← does nothing; 25 unrevealed nodes are in tab order so Play takes 27 Tabs; no visible focus ring on the node.
- Hint overlaps the sound button; "tap" to a mouse user.
- Chooser chips are one scrolling row; "60 Minutes → th…" cut off; 4–5 of 26 visible.
- Chromebook: fits; the sticky feed is 748 px tall from y=233 so its lower third is below the fold until a scroll.
- Nits: "Ordered against AA's founding.." (double period); "Wikipedia daily views: ·" (empty name); Tambora oat prices Details starts lowercase; British "cinemas" in Ocean, Victim, Top Gun, Muybridge.
- Worked: Step mode ("the best thing here"), the Busted wording, p explained in words on Measured cards, candid Plausible cards, honest empty search state, dates spot-checked against the results file all match.

## 3. Earl, 58, Zanesville OH (1366×768 at 125%, mouse, deuteranopia)

Subject: that ripple thing you sent me

OK, I looked at it on the work laptop. Here's what I got.

Opens with a big dark screen, "Throw a stone. See what it changed." and a sentence underneath: "A show, a film, a disaster, a discovery. Its ripples spread out in time, each one rated for how sure we are, until something sticks." That's fine. It's not selling me anything, and "how sure we are" is the right thing to say up front. I clicked the orange button.

First story is the Post Office one from England, Mr Bates. The headline is "Mr Bates → convictions quashed by law," which is a claim, but the cards under it are dated and named: ITV broadcast Jan 1–4 2024, petition Jan 8, Hansard Jan 10, Royal Assent May 24 2024. That I can check. The pond itself I mostly couldn't see. On my screen the bottom of it, the little color key and the "How it works" button were cut off until I scrolled, and for the first ten seconds a bubble saying "Press play or drag the slider · tap a ripple to follow it" sat right on top of the slider. I don't tap, I have a mouse.

The rings: I figured the rock is the show and the rings are time going outward, but the rings all look the same to me, pale lines on blue. The key says green is "Measured" and red dots are "Busted." I can't tell your green from your orange, and the red dotted one is so faint I never found it on the water at all. What saved me is the cards. Every card has a word on it, "Measured," "Reported," "Plausible," "Busted," and the busted ones have the title crossed out. Keep that.

I did Prohibition. Hit Step so it would stop at each one. It didn't. It stopped at the 1922 one and the 1929 one and then jumped clean to 1971, skipped Capone and Repeal, which is the whole point of the story. I ran it again later and it skipped a different bunch. Also the clock said "Jul 26, 2023" while the card on the right said "Aug 13, 2025," and at the end it says "Jan 1920 → Dec 2019" when there's cards up to 2025. If you want a skeptic to trust the dates, the dates have to agree with each other.

The "How sure?" on a Reported card says: "We did not measure this ourselves. A named source (US District Court, Chicago, 17 Oct 1931) records that it happened on this date and ties it to the step before: the bootlegging fortune was the income the charges rested on. Treat it as reliable reporting, not a measurement." Honest. On a Busted card: "This arrived after the trend it is said to have started. The thing this step is said to have started was already under way before it arrived, so it cannot be the origin. As a later accelerant it stays an open question." Also honest, and it's exactly what I'd have said about the smartphone thing.

Then I opened Details to check a source. Every one says "Search Wikipedia ↗." Not a link to the court record, not the Act, a Wikipedia search for your own sentence. That's a dodge. Give me the law's name and the date and I'll find it myself; you half do that already.

Sound and share buttons are a speaker and a box with an arrow. I knew what they were, and holding the mouse on them says "Sound" and "Share."

Rating: 6 out of 10. The writing on the cards is careful and the dates are there. The water is a decoration I can't read, the step button doesn't step, and the clock lies to me. Fix the stepping and the dates and I'd say 8.

Earl

### Earl: what the tester measured

- Two-column layout holds at 1093 CSS px (588 | 453). Pond 580×300 CSS px. Header 199 px tall, so the legend and "How it works" sit below the 614 px fold.
- Smallest text (CSS → physical at 125%): rim words 10 → 12.5 px in dim gold; "1 year" 9 → 11.25 px; tick years 10.6 → 13.2; card badge 10.9 → 13.6; legend 12.5 → 15.6; pond labels 13.5 → 16.9.
- **Deuteranopia simulation** (Machado 2009, severity 1.0; CIE76 ΔE normal | simulated). Strokes: Measured–Busted 85.6 | 15.0; Measured–Plausible 33.6 | 11.4; Plausible–Busted 56.6 | 20.6; Measured–Timed 63.0 | 39.6; Timed and the marigold used for the stone, lasting-mark pill and hot outline are identical by design (0 | 0). Card badges on paper: Plausible–Busted 52.3 | **7.1**; Measured–Plausible 40.2 | 15.5; Measured–Busted 91.3 | 21.9. Pond arcs at rest, blended over water at their opacity: Reported–Plausible 9.3 | 8.8 (hard for anyone); Plausible–Busted 15.9 | 7.4. Only Measured stands apart, and by opacity.
- Line styles without color: the legend promises Plausible dashed, but the pond draws `.rip.l-plausible` solid; Busted is dashed at 1.3 px and .28 opacity, effectively invisible. Verdict: line style does not carry the five-way distinction on the pond; the card badge text and the strikethrough do.
- **Step mode skips ripples.** Four runs on Prohibition stopped at 12, 10, 9 and 11 of 25 items, each a different subset; Capone skipped 4 of 4, Repeal 3 of 4. Frame trace: while the front travels to one goal, the day it has reached passes an intermediate ripple, so the next frame picks a new goal and the clock never halts. (Builder's note: confirmed, a defect in the Step code shipped in PR #74. Fixed below.)
- **The "future" clamp mislabels real events.** Today is Oct 2026, the clamp point is 97% of the span, Jul 2023, so every Prohibition item after that (NA beer Dec 2023, the advisory Jan 2025, Gallup Aug 2025) is pushed to the rim and flagged future: the clock reads "Jul 26, 2023" while the hot card says "Aug 13, 2025"; the rest label says "Jan 1920 → Dec 2019" while cards run to 2025; six nodes pile on one rim point. (Builder's note: confirmed; a span bug. Fixed below.)
- Sources: "Search Wikipedia ↗" on 19 of 25 Prohibition cards and 7 of 9 Mr Bates cards.
- Hint over the slider, sound and share for 9 s; says "tap".
- Reported "How sure?" embeds the entire source string in parentheses.
- Data holes: "Attention to 'sober curious'" shows "Undated · no date to check" and an empty series name; the double period on the Hughes Act card.
- Worked: the intro copy ("measured, not hype"), the cards (date, text badge, strikethrough, "How sure?" that concedes limits), mouse-only operation complete (hover tooltip with the grade word and date, click to focus with the card scrolling into view, wheel over the feed, the slider), sound and share icons understood with titles, "How it works" answers "says who?" at the level of method but not at the level of a card.

## What the three agree on

| Finding | Who | Status |
|---|---|---|
| "Search Wikipedia" source links read as a dodge, not a citation | All three | **Done as asked, data pass still open.** The search links are gone. A card now links only to something real: the Wikipedia article whose attention was counted (33 steps by their own test, more by the attention check), the series read, a URL in the chain, or a `url` field a chain author adds. Everything else shows the source's own words with "not linked yet". Adding record URLs across the chains is the data pass that remains |
| First-visit hint sits on the slider it tells you to drag; says "tap" to mouse users | All three | **Fixed**: above the controls; "click or tap" |
| Pond text too small: rim words and "1 year" have no floor; labels under 10 px on a phone and on a projector | Marcus, Yuki | **Fixed** for labels, rim words and the ring label (see below). Open: the pond column does not grow past 663 px on a 1920 screen; a projector needs a wider pond or a large-type toggle |
| Step mode skips ripples | Earl (Yuki saw it work on Prohibition at 1920 wide) | **Fixed** (see below) |
| Dates disagree: clock vs card, rest label vs cards, nodes piled on the rim | Earl | **Fixed** (see below) |
| The pond does not carry the five grades for a colorblind reader; the legend promises a dashed Plausible that the pond draws solid | Earl | **Fixed.** Plausible dashed, Busted heavier, and Timed is now lilac, distinct from the stone's marigold and from green and red under deuteranopia (blue-violet survives the simulation; Earl's table had every marigold pair at ΔE 0) |
| Tapping a ripple or stepping on a phone shows nothing readable in view; the card is screens below | Marcus | **Fixed.** On screens up to 860 px a caption under the pond names the ripple, its grade, date and one-line reason, with a "Read the card" link that scrolls to it |
| Drag-to-throw breaks under touch and is unreachable during autoplay | Marcus | **Fixed.** The pond sets `touch-action: none` while the stone is held, so Chrome no longer cancels the gesture; a cancelled touch puts the stone back instead of throwing it; the grab window covers almost the whole wait before the throw |
| Reported "How sure?" nests the entire source string; dose-response card jargon | Yuki, Earl | **Fixed.** The sentence names the source's short name only ("The source named on the card (Miron & Zwiebel (1991)) records…"); dataset ids are stripped; the Measured face reads "370.1× normal · a rise this big at 2% of random dates (p = 0.023)" |
| Date style mixed: US headers, day-month source lines; placeholder dates print as exact days | Yuki | **Fixed for display.** Source lines are rewritten to US style ("17 Jan 1920" → "Jan 17, 1920"). A step dated to mid-year with no July in its source now reads as its year, "1922 · placed at mid-year". Jan 1 dates are left alone, since some are real (Mr Bates aired Jan 1). A precision field in the data is still the right long-term answer |
| Catalog is UK-heavy; the default story means nothing to a US 16-year-old; some stories do not belong on a projector | Yuki | **Default changed:** the page opens on Tiger King → the Big Cat Act (US, a law, a show most Americans know); Mr Bates is second. The launch clip is re-cut on it. A classroom filter and US-history chains (Dust Bowl, 1918 flu, New Deal) remain the owner's call |
| Copy: "No lasting mark found yet… hype" as the first line under a fan's show; "1 law, 1 of them" | Marcus | **Fixed.** "A big splash, no lasting mark yet: what changed so far is attention and money, not a law…"; the one-law case reads "Named in the passage of 1 law, as a reason given for the bill" |
| "How it works" headings invisible | Yuki | **Fixed** (paper cards) |

What all three praised, in their own words: the cards. The grade word on every card, the strikethrough on busted titles, "How sure?" text that concedes its limits, and the p-value explained in words. Yuki called Step mode "the best thing here"; Earl called the water "a decoration I can't read". Both are right, and together they say where the next work goes: the pond must carry the reading, not just the mood.

## Fixed in this pass (builder)

- Step mode keeps its goal until it is reached; it no longer re-picks a goal mid-flight, so every ripple gets its stop.
- The future clamp applies only to days after today; the Prohibition items from 2023–2025 take their real places, the clock and the cards agree, and the rest label reads to the last event.
- Plausible arcs on the pond are dashed, as the legend says.
- The first-visit hint sits above the pond's bottom edge instead of on the slider, and says "click or tap".
- The rim words and the ring label follow the same text floor as the labels.
- The text floor itself did not reach the labels: on small screens their size was still fixed at 22 SVG units (7.6 px on Marcus's phone, as he measured). Labels now scale with the floor factor: 11 px on a 360-px phone, 15 px on a tablet, 12 px on a desktop, measured on screen.
- "How it works" sits on paper cards, so its headings and text read (the round-one fix had set the heading color inside a section whose palette is paper ink on the dark page; the section had no paper behind it).

## Fixed in the second pass (builder, same night)

- Source links: real or none (table above). Timed is lilac. The phone caption on tap and step. Touch drag. The default story is Tiger King.
- Reported "How sure?" names the short source; US dates on source lines; mid-year placeholders read as a year; dataset ids gone; p explained on the Measured face.
- A sparkline only on Measured steps (a Reported card with an attention-check spike looked measured).
- Keyboard: a ripple joins the tab order when it lands (Play is a few Tabs away, not 27); a visible focus ring.
- The chooser's chips wrap instead of one scrolling strip. On screens 1500 px and wider the layout grows, so the pond is larger on a projector.
- Step at the end of a story restarts it. No negative radii in the splash. The double period, the empty series name, the lowercase detail, and "cinemas" in the chain text.
