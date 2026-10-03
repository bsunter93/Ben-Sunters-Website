# Ripple v1: three persona tests (Oct 3, 2026)

Three simulated users, each driven as a real browser session against the v1 build (main at a0cb79a: the lake scene,
before the one-bar header and the wavefront change). Each persona had a viewport, a task list and no coaching. Their
reports are below in their own words, followed by what we are doing about each finding. Screenshots named in the
reports are in the session scratchpad.

## 1. Dani, 16, high-school junior, Houston (phone, 390×844)

> ok so first thing I see is a dark blue screen with a lil orange drop and "Throw a stone. See what it changed." which honestly looks kinda nice, like a movie title. The paragraph under it I skipped, it was like 4 lines, my brain said no. The big orange button says Throw a stone so obviously I hit that.
>
> And... nothing got thrown?? The popup just closed and there's a rock already sitting in the water. No splash, no toss, no sound. It said "2 days before" at the top which, before what? Then the rings started growing and little tags popped up like "Scandal attention" and "Vennells attention." I have zero idea who Vennells is. The whole first story is "Mr Bates → convictions quashed by law" and I've literally never heard of it, so for the first 15 seconds I'm watching rings about a British thing I don't know. Also there was a bar covering the play button and slider saying "Press play or drag the slider" while hiding them lol.
>
> What I THINK the picture is: a rock in a pond at night, the rings are like years going outward (there's a tiny "1 year" line), the words on the edge like "STICE & LAW" (cut off on my screen) are categories, and the little bubbles are things that happened. The grey thing is the rock = the show. Honestly it looks like a solar system more than a pond.
>
> Tapping stuff: I tapped one of the little dots on the water and the page YANKED me all the way down to some card about a petition, so the pond disappeared. Felt like I fat-fingered a link. The dots are also tiny, smaller than my fingertip. Tapping empty water did nothing I could see. Slider worked fine. Tapping a card lit up its border orange, cool, but I expected the pond to move too.
>
> Finding Tiger King took me 13 swipes through that chip row and like 9 seconds, it was buried deep. Squid Game I found in 2 taps once I guessed the "Fact-checks" tab. Tiger King's pond actually hits: "Big Cat Act becomes law" with a shiny diamond, and that got my attention cause I remember the show. But the labels piled on top of each other. Squid Game says "No lasting mark found yet" which felt like the site shrugging at me, but the ddakji thing being 6499× normal is a crazy stat I'd screenshot.
>
> "How it works": I couldn't even read the headings, they're dark on dark. Words that lost me: Hansard, CBE, quashed, "tested against chance", FRED, BLS, Census retail sales, p = 0.023, "second reading". "Measured / timed / reported / plausible / busted": busted I get (MythBusters vibes), measured kinda, plausible sure, but timed vs reported? no clue, they sound the same.
>
> Would I share it? Maybe the Tiger King one to my friend who's obsessed with it, with "bro the show literally made a law". Not the site itself. What would make me stay: a story I know on the first screen, an actual throw (I drag and flick the stone), and sound on by default.

**Dani's top five, in order:** (1) the cold open lands on an unknown UK story and nothing is thrown; (2) tapping a ripple scrolls the page away from the pond, and the tap targets are 12 px; (3) known stories are buried 13 swipes deep in the chip row; (4) "How it works" is unreadable on a phone (dark headings, 215 words of jargon); (5) the first-run hint covers the controls it describes, rim words clip ("STICE & LAW"), labels overlap on busy ponds.

**Delights:** the pond itself; the diamond "lasting mark" pins; big stats on cards ("6499.7× normal").

**Suggestions:** a real drag-and-release throw; a phone-first picker with search and "ones you'll know" pinned first; plain-English rating labels with tappable one-line definitions.

## 2. Priya, 36, product manager, Chicago (laptop, 1440×900)

> Cold open: a dark pond, a drop icon, "Throw a stone. See what it changed." I got the metaphor in about three seconds and had no idea what the product was until I clicked "Throw a stone". Then the page revealed itself: a Mr Bates headline, a tally line, a "Same stone, another pond" chip, three tabs, a chip rail, then the map. That is eight distinct things stacked before the visualization; the header is 326–350 px tall, so the map starts at pixel 386 on a 900 px laptop. Too much. I would cut the tagline next to the wordmark (it repeats the intro), the "Same stone, another pond" row (a third navigation layer I did not understand until step 4), and fold the tally into the map's clock.
>
> The default story plays in 15 seconds. The map is pretty and only half legible. After one viewing I could explain the stone and the rings. I could not explain the arcs: of 8 ripples only 3 were labelled on the water; the five "reported" steps that actually carry the story are anonymous grey slivers until you hover. The cards on the right do the real work; the map is an index to them.
>
> Credibility: better than I expected, and the writing is the strongest part. "Measured" means Wikipedia pageviews ran 370× normal and the same test at 43 placebo dates matched 2.3% of the time (p = 0.023), and the card says plainly "this shows attention, not what people did next." That is honest, if thin (43 placebos). The "busted" calls on Prohibition are fair and genuinely interesting (smartphones, Dry January and cannabis cannot have started a decline that began in 1980), but they are dated "Jul 1, 1981", which is the decline's onset, not the claim's date, and that confused me for a minute. Less fair: Frozen's "Elsa cohorts reach college around 2032" is marked busted with the boilerplate "the claim has to match the record; this one does not", when the honest label is "not yet". And one card leaks a researcher's note: "ClinicalTrials.gov is free and can confirm."
>
> Engine leads: the header says "The mark it left: Housing Subsidies Act 1967 (law)… and 5 more" and "8 lasting marks" for a 1966 TV play, including the Broadcasting Act 1990 and the Renters' Rights Act 2025. The card copy says a citation "shows the work was in the room, not that it caused the Act". The header overclaims what the cards carefully disclaim.
>
> Prohibition: a century on a non-linear slider (half the track is 1920–1931) and 15 of 21 ripples land in the first four seconds. The best fact, that teen drinking has fallen since 1980 and every popular explanation arrived decades too late, I found by reading cards 9–11, about 70 seconds in. The map never showed it to me.
>
> Would I show my team? Yes, as a visualization and writing example of honest uncertainty labelling. Not as a product yet: too many layers of navigation, a map that does not carry the story on its own, and a header that promises more than the cards deliver.

**Priya's top five, in order:** (1) the Engine-leads header overclaims ("8 lasting marks" for a play cited in debates); (2) the map leaves most ripples unlabeled, so it is an index to the cards rather than the story; (3) the header stack pushes the map below the fold; (4) "busted" is misapplied (Frozen's 2032 cohort is "not yet"; the Prohibition catalyst claims carry the decline's date instead of their own; an editor's note leaks; the feed order breaks once); (5) the first-visit hint covers the controls, and an empty card flashes on a tab switch.

**What worked:** the "How sure?" copy for measured steps; the fairness architecture (busted claims stay struck through on the map, the dose-response card); speed and feel.

**Credibility verdict, in her words:** "The cards are honest to a fault; the headers are not: fix 'lasting marks' on Engine leads and the 'Not yet'-as-busted cases and I would cite this as a model of uncertainty labelling."

## 3. Walter, 75, retired internist, Savannah (tablet, 820×1180, text zoomed, an unsteady finger)

> I opened it on the iPad with my text turned up, and the first screen was a pleasant surprise: large type, a sentence I could read in one breath, one orange button. But the rings behind the words never stop spreading, and I had not finished the first line before they had gone round twice. I am seventy-five; I would like the page to wait for me.
>
> I pressed "Throw a stone" and was dropped into "Mr Bates → convictions quashed by law." I have no idea who Mr Bates is. I read the headline, the line beneath it, the counts, the tabs. Nothing told me it was a television drama, or that a post office computer had put honest people in prison. I found "ITV airs Mr Bates vs The Post Office" only after scrolling down to the cards, and the word "drama" only inside a folded "How sure?" box on the seventh card. By then the water had finished moving.
>
> That is my main complaint. The pond plays for fifteen seconds whether a story spans five months or a century, and while it plays the written cards are below the bottom edge of my screen. On Prohibition, which I know well, twenty-odd ripples arrived in about seven seconds and most of them have no label; the lower right of the pond is a tangle of arcs under a word, "CATALYSTS?", in ten-point capitals I needed the magnifier for.
>
> Finding Tylenol took ten swipes along a strip of pills. Quincy, happily, was third in the row, one tap. The chips themselves are a fair size for my hand.
>
> The Tylenol story is right as far as it goes: the seven deaths, the recall, the FDA rule in November 1982, and the honest note that the move to caplets followed the second poisoning in 1986, not the first. I would have added the Anti-Tampering Act of 1983. What troubled me was the sourcing. "Nationwide recall, early October 1982" is not a citation; it is the claim again in grey type. The FDA rule and the Public Law are properly named, but there is not one link on the whole page I could follow.
>
> The pause button worked, and when I dragged the slider with my unsteady finger it did not fight me. Good. The "Details" and "How sure?" lines, though, are small grey text with no button around them; I missed twice.
>
> The grading scale I like. Measured, Timed, Reported, Plausible, Busted is roughly my own ladder from a controlled trial, through a well-timed observational series, to a case report, to a plausible mechanism, to disproven; the honest "we did not measure this ourselves" is more than most journalism gives. I would only ask that Timed and Plausible not share the same orange.
>
> Would I send it on? To my grandson, yes, with Quincy and the Orphan Drug Act, because it is a true story told carefully. To a friend my age, not yet: too fast, too small, and it assumes you already know the stone.

**Walter's top five, in order:** (1) the story plays out before it can be read: a fixed 15-second clock, cards below the fold on a tablet; (2) the default story is never explained in plain words; (3) pond and control text is too small and too faint (rim words 10 px at 55%, "1 year" 9 px, How-it-works headings near invisible); (4) finding a known story means swiping a 6,400-px strip; (5) sources are restatements and nothing is a link.

**What he appreciated:** the evidence ladder and its honesty; pause and slider that do not fight a tremor; the intro and card typography; accurate Tylenol and Quincy chronologies.

---

## What the three agree on, and what changed because of it

| Finding | Who | Status |
|---|---|---|
| Nothing is thrown; the stone is already in the water | Dani, Walter | **Done.** The stone is tossed from the near bank in an arc, spins, lands with a splash crown and a sound; drag the stone and let go to throw it from where you like |
| Too much header before the water (eight elements, 330 px) | Priya, Dani | **Done.** One bar: counts left, "Change story" right; tabs, chips, other ponds in a panel on demand |
| Known stories are buried 10–13 swipes deep | Dani, Walter | **Done.** "Start with one you know" row (Tiger King, Squid Game, Frozen, Prohibition, the volcano) pinned at the top of the chooser, and a search box that spans all three tabs (a title, a stone, or an event year) |
| The default story is not explained | Walter, Dani | **Done.** The first card now carries the step's plain-language note (for Mr Bates: what the drama was and what the scandal was) |
| Inner ripples overtake outer ones; it reads as orbits | Owner, Dani | **Done.** One wavefront moves outward; arcs bloom where it passes and stay |
| The fixed 15-second clock runs a century in 15 s | Walter, Priya | **Done.** The clock scales with the number of steps (about 0.65 s a ripple, 15–30 s) |
| Tapping a ripple on a phone yanks the page to the card | Dani | **Done.** No scroll on narrow screens; the card lights up in place |
| Tap targets 12 px | Dani | **Done.** 44 px hit areas on the pond |
| First-visit hint covers the controls and expires during the intro | All three | **Done.** Sits above the controls on a phone; its timer starts when the intro closes |
| "How it works" headings invisible on the dark background | All three | **Done.** Headings set in the ink color |
| Timed and Plausible share one orange | Walter | **Done.** Plausible is sand; Timed stays marigold |
| Engine-leads header claims "8 lasting marks" for a play cited in debates | Priya | **Done.** The header now says "Named in the passage of N laws, M of them as a reason given for the bill. A citation shows the work was in the room, not that it caused the law." and the count reads "cited as a reason" |
| Prohibition's catalyst claims dated 1981 instead of when the cause arrived | Priya | **Done.** Dated when the cause arrived (smartphones 2012, Dry January 2013, Colorado retail 2014, the advisory 2025) and tested with a new rule: a claimed cause must come before what it claims to have started. Re-run in CI |
| "Not yet" dressed as "Busted" | Priya | **Done.** Its own wording: nothing is wrong with the claim; it has not happened yet |
| A researcher's note leaked on a card | Priya | **Done.** Removed |
| Rim words clipped on a phone ("STICE & LAW") | Dani | **Done.** Rim words are kept inside the picture |
| Pond text too small for a 75-year-old | Walter | **Done.** Labels now have a floor in screen pixels that follows the pond's on-screen size: 15 px on a tablet, 12 px on a desktop, 11 px on a phone where the pond is small. Card source lines are larger too |
| Sources are restatements with no links | Walter | **Done.** Every card's source line now ends in a link: the Wikipedia article we counted, the FRED or SSA series we read, the methods page for our own tests, or a Wikipedia search for the source's own words when the chain names a record without a URL. Honest about what it is: a place to start checking, not a citation database |
| The map does not carry the story on its own; most ripples unlabeled | Priya, Walter | **Done.** A Step button: the front travels to the next ripple in about a second and a half, stops there with its card open and its label on, and waits; play or the right arrow goes on. The quiet pond stays the default |
| The log time axis is never explained | Priya, Walter | **Done.** One line in How it works |
| Sound off by default | Dani | **As is.** The throw's splash sounds on the first gesture; the ambient pings stay opt-in, since a page that makes noise unasked is the complaint we would get next |


Also fixed while closing these: when a ripple was focused, the labels of ripples that had not yet arrived showed through at 16%, which read as clutter near the stone. Only landed ripples sit back now.
