# Sensors v1: results

**Run:** Oct 5, 2026. **Plan:** `ripples/docs/sensors_plan_v1.md`, registered in commit `80836a5` (06:34 UTC), 43 seconds
before the first request to any source; one amendment, `11eb8ad` (06:37 UTC), before any data. **Data:**
`ripples/docs/results/sensors_v1.json` (per step: each sensor's series summary, onset, ratio, p, decoys, class),
`ripples/docs/results/sensors_mediacloud_v1.json` (Media Cloud daily counts, written by the workflow). **Code:**
`ripples/lab/sensors_v1.py` (the test, convergence, calibration, catalyst scan), `ripples/lab/sensors_mediacloud.py` (the
workflow's counter), `ripples/lab/sensors_gdelt.py` (the GDELT fetcher).

**Status: interim.** GDELT refused the first request and is closed until Oct 6, 00:00 UTC; Media Cloud stopped on a 504
partway through. Everything below is Media Cloud's online news against the stored Wikipedia results. Television, GDELT's
news and the catalyst scan are not in this version.

## In one paragraph

Of the 13 measured Wikipedia attention steps, **7 are confirmed** by online news (Media Cloud's national
collections, beyond chance against their own history and in order), and **6 are not**: news either rose within
chance or did not rise, and television, the third family, could not be run. That is 54% against a bar of 70%: **bar
part 1 failed** on the sensors that could run. Media Cloud's false-pass rate on decoy dates is 3.8% (**part 2
passed** for that sensor). Media Cloud's US collection reaches back to July 2009, so 7 steps from 2011 to 2015 are
measured for the first time (**part 3 passed**). The catalyst scan was not run: neither source reached the panel (**part 4
not run**).

## What each source allowed

| Source | Requests | What happened |
|---|---|---|
| GDELT DOC 2.0 and TV 2.0 (`api.gdeltproject.org`) | 1 | HTTP 429 on the first request (Oct 5, 06:35:42 UTC) with the notice "Please limit requests to one every 5 seconds". The host serves both APIs, so both stopped for the UTC day. No retry, no other agent, no other network. One registered attempt is allowed after Oct 6, 00:00 UTC. |
| Media Cloud (`search.mediacloud.org`, from the workflow only) | 71 of the 2,000 allowed | The server declared 2 requests a minute; requests went every 31 s. US National (34412234) and United Kingdom - National (34412476) found. 69 count requests answered; the 70th answered HTTP 504 and the run stopped there, as the rules require. 68 of 166 registered queries recorded: sets A, A2 and D complete, 9 of 18 leads, 13 of 103 panel entities (only those sharing a query with an earlier step). The workflow was triggered once and not re-run. |
| Wikipedia pageviews | 0 new for steps | The stored results in `chain_check_v1.json` and `demo/discovered.json` are the comparison. |

## 1. Convergence: the 13 measured Wikipedia steps

| Step | Claim | Ref | Wikipedia (stored) | News | Television | Class |
|---|---|---|---|---|---|---|
| tiger-king 2 | People look up big cats and exotic pets | Mar 20, 2020 | measured, onset Mar 26, 2020, 5.1x, p = .010 | Media Cloud: beyond chance in order, onset Mar 27, 2020, 18.2x, p = .010 | not run | confirmed |
| wordle 2 | People look up Wordle | Oct 1, 2021 | measured, onset Jan 21, 2022, 49881.1x, p = .007 | Media Cloud: timed (sparse), onset Jan 11, 2022, 39x | not run | partial |
| chernobyl-zone 2 | Interest in the real disaster surges | May 6, 2019 | measured, onset May 8, 2019, 48x, p = .013 | Media Cloud: within chance, onset May 21, 2019, 9.3x, p = .103 | not run | partial |
| mr-bates-horizon 2 | Attention to the Horizon scandal surges | Jan 1, 2024 | measured, onset Jan 2, 2024, 370.1x, p = .023 | Media Cloud: beyond chance in order, onset Jan 7, 2024, 123.4x, p = .005 | not run | confirmed |
| mr-bates-horizon 9 | Attention to Paula Vennells surges | Jan 1, 2024 | measured, onset Jan 3, 2024, 1879x, p = .006 | Media Cloud: beyond chance in order, onset Jan 6, 2024, 65.5x, p = .005 | not run | confirmed |
| daily-show-zadroga 5 | Attention to the Act surges | Jun 11, 2019 | measured, onset Jun 11, 2019, 48.7x, p = .012 | Media Cloud: within chance, onset Jun 12, 2019, 3.7x, p = .173 | not run | partial |
| ocean-attenborough 2 | Attention to bottom trawling rises | May 8, 2025 | measured, onset May 10, 2025, 4.6x, p = .004 | Media Cloud: beyond chance in order, onset May 7, 2025, 5.7x, p = .004 | not run | confirmed |
| america-and-alcohol 25 | Attention to alcohol and cancer surges after the Surgeon General's advisory | Jan 3, 2025 | measured, onset Jan 3, 2025, 4.2x, p = .035 | Media Cloud: beyond chance in order, onset Jan 3, 2025, 12.3x, p = .004 | not run | confirmed |
| jwst 2 | Public interest in astronomy spikes | Jul 11, 2022 | measured, onset Jul 12, 2022, 2.4x, p = .006 | Media Cloud: within chance, onset Jul 12, 2022, 3.8x, p = .124 | not run | partial |
| gamestop 1 | Reddit traders squeeze GameStop | Jan 13, 2021 | measured, onset Jan 28, 2021, 215x, p = .008 | Media Cloud: beyond chance in order, onset Jan 27, 2021, 102.1x, p = .008 | not run | confirmed |
| queens-gambit-2 2 | People look up chess and chess sets | Oct 23, 2020 | measured, onset Oct 27, 2020, 3.9x, p = .009 | Media Cloud: no sustained rise | not run | partial |
| toilet-paper 2 | People look up bidets | Mar 11, 2020 | measured, onset Mar 13, 2020, 13x, p = .010 | Media Cloud: beyond chance in order, onset Mar 17, 2020, 11.1x, p = .010 | not run | confirmed |
| squid-game-ripples 12 | Interest in ddakji, the paper-tile game, surges | Sep 17, 2021 | measured, onset Sep 26, 2021, 6499.7x, p = .008 | Media Cloud: no sustained rise | not run | partial |
| pokemon-go 1 | Pokémon GO launches | Jul 6, 2016 | timed (short history), onset Jul 8, 2016, 347716x | Media Cloud: rose, no placebo history, onset Jul 11, 2016, 726.1x | not run | not measured |
| barbie 4 | Fashion pivots to pink ('Barbiecore') | Jul 21, 2023 | timed (new article), onset Aug 9, 2023 | Media Cloud: moved, wrong order, onset Jun 29, 2023, 19x, p = .005 | not run | not measured |
| covid-remote 2 | Knowledge workers move to 'Zoom towns' | Mar 13, 2020 | timed (new article), onset Apr 11, 2021 | Media Cloud: no sustained rise | not run | not measured |
| airpods 2 | Wireless earbuds take off; AirPods dominate | Sep 7, 2016 | timed (new article), onset Sep 10, 2016 | Media Cloud: rose, no placebo history, onset Sep 7, 2016, 99.3x | not run | not measured |
| tiktok 1 | TikTok's For You feed takes off | Aug 2, 2018 | timed (new article), onset Aug 25, 2018 | Media Cloud: beyond chance in order, onset Jan 7, 2019, 39.3x, p = .017 | not run | measured on N |

**Reading.** The seven that converge are the loud ones: Tiger King's big cats, the Post Office scandal and Paula Vennells,
bottom trawling after Ocean, alcohol and cancer after the Surgeon General's advisory, GameStop, and bidets in the toilet
paper run. Onsets agree with Wikipedia's to within five days in every case, and the order holds. The six that do not
converge fall into three kinds:

- **A term news did not use before.** Wordle (sparse: news never named the game before October 2021, so the placebo test
  is degenerate and the rise counts as timed, exactly as a new Wikipedia article does).
- **A rise news shares but not beyond its own history.** The Chernobyl disaster after the miniseries (9.3x, p = .103;
  the disaster's 30th anniversary in April 2016 drew more news), the Zadroga Act at Jon Stewart's 2019 testimony (3.7x,
  p = .173; the 2015 reauthorization fight drew more), astronomy at Webb's first images (3.8x, p = .124; the 2017 solar
  eclipse and Webb's own launch in December 2021 drew more). The onsets that matched or beat each step are listed under
  `placebo_hits` in the results file.
- **Reading that never reached the news.** Chess after The Queen's Gambit and ddakji after Squid Game: Wikipedia readers
  looked these up; US national news did not write about them more.

These six are the steps where the attention is curiosity (people looking something up) rather than news, and where the
claim on the card ("people look up chess") is still true. Wikipedia remains the right sensor for curiosity; it is the only
one of the three that measures it. Where a step's claim is about public attention in general, the card can now say
whether the news agreed.

## 2. Calibration on decoy dates

| Sensor | Decoy dates tested | Beyond chance in order | False-pass rate |
|---|---|---|---|
| gdelt_doc | 0 | 0 |  |
| mediacloud | 370 | 14 | 3.8% |
| gdelt_tv | 0 | 0 |  |

## 3. The other attention steps

**Timed Wikipedia steps (new articles or short histories).** No timed step becomes a candidate for a measured grade on
this evidence. TikTok passes on news (onset Jan 7, 2019, five months after the step, p = .017), but three of its five
decoy dates also pass: a new name's coverage grows in jumps, and the test cannot tell one jump from another. Pokemon Go
and AirPods rose at once on news but have no placebo history: the registered span began Jul 1, 2015, to match
Wikipedia's, although the collection reaches 2009. Barbiecore rose in news on Jun 29, 2023, three weeks before the
film's release (the marketing, not the film); Zoom towns never rose in national news.

**Record steps whose attention check rose.** 7 of 20 converge.

| Step | Claim | Ref | Wikipedia (stored) | News | Television | Class |
|---|---|---|---|---|---|---|
| wordle 3 | The New York Times buys Wordle | Jan 31, 2022 | attention rose, onset Jan 21, 2022, 49881.1x, p = .007 | Media Cloud: moved, wrong order, onset Jan 11, 2022, 38x, p = .007 | not run | partial |
| haber-nitrogen 7 | World population grows from 1.6 billion to 8 billion | Nov 15, 2022 | attention rose, onset Nov 15, 2022, 9.7x, p = .006 | Media Cloud: no sustained rise | not run | partial |
| chernobyl-zone 3 | Tour operators report bookings up 30–40% | Jun 4, 2019 | attention rose, onset May 10, 2019, 28x, p = .013 | Media Cloud: within chance, onset Jun 4, 2019, 6x, p = .087 | not run | partial |
| mr-bates-horizon 3 | A petition to strip Paula Vennells of her CBE passes a million signatures | Jan 8, 2024 | attention rose, onset Jan 3, 2024, 1708.1x, p = .006 | Media Cloud: beyond chance in order, onset Jan 6, 2024, 65.5x, p = .005 | not run | confirmed |
| mr-bates-horizon 4 | Vennells hands back her CBE | Jan 9, 2024 | attention rose, onset Jan 3, 2024, 1708.1x, p = .006 | Media Cloud: beyond chance in order, onset Jan 6, 2024, 65.2x, p = .005 | not run | confirmed |
| mr-bates-horizon 5 | The Prime Minister announces a law to quash the convictions | Jan 10, 2024 | attention rose, onset Jan 2, 2024, 353.8x, p = .023 | Media Cloud: beyond chance in order, onset Jan 7, 2024, 122.8x, p = .005 | not run | confirmed |
| octopus-sentience 3 | The film wins the Academy Award for Documentary Feature | Apr 25, 2021 | rose, no placebo history, onset Apr 26, 2021, 12.4x | Media Cloud: beyond chance in order, onset Apr 23, 2021, 27.4x, p = .008 | not run | measured on N |
| ocean-attenborough 3 | The UK government opens a consultation on banning bottom trawling in 41 marine protected areas | Jun 9, 2025 | attention rose, onset May 10, 2025, 4.5x, p = .004 | Media Cloud: beyond chance in order, onset Jun 9, 2025, 5.7x, p = .004 | not run | confirmed |
| adolescence-schools 1 | Netflix releases Adolescence | Mar 13, 2025 | rose, no placebo history, onset Mar 15, 2025, 2470.4x | Media Cloud: beyond chance in order, onset Mar 15, 2025, 93.6x, p = .004 | not run | measured on N |
| adolescence-schools 3 | MPs cite the series in the Children's Wellbeing and Schools Bill debate | Mar 18, 2025 | rose, no placebo history, onset Mar 15, 2025, 2007.2x | Media Cloud: beyond chance in order, onset Mar 15, 2025, 93.3x, p = .004 | not run | measured on N |
| adolescence-schools 4 | The Prime Minister backs showing the series in schools | Mar 31, 2025 | rose, no placebo history, onset Mar 15, 2025, 1356.2x | Media Cloud: moved, wrong order, onset Mar 15, 2025, 92.3x, p = .004 | not run | not measured |
| america-and-alcohol 21 | The Surgeon General calls for cancer warnings on alcohol | Jan 3, 2025 | attention rose, onset Jan 3, 2025, 4.2x, p = .035 | Media Cloud: beyond chance in order, onset Jan 3, 2025, 12.3x, p = .004 | not run | confirmed |
| three-mile-island-nrc 10 | Constellation agrees to restart Unit 1 to power Microsoft's data centers | Sep 20, 2024 | attention rose, onset Sep 20, 2024, 14.1x, p = .032 | Media Cloud: beyond chance in order, onset Sep 20, 2024, 18.1x, p = .023 | not run | confirmed |
| serial 4 | Renewed legal momentum; conviction vacated | Sep 19, 2022 | attention rose, onset Sep 19, 2022, 25.4x, p = .006 | Media Cloud: within chance, onset Sep 17, 2022, 28.1x, p = .078 | not run | partial |
| dobbs 2 | Trigger bans take effect | Jul 28, 2022 | attention rose, onset Jun 28, 2022, 165.9x, p = .006 | Media Cloud: moved, wrong order, onset Jun 28, 2022, 67.4x, p = .006 | not run | partial |
| gdpr 1 | GDPR takes effect | May 25, 2018 | attention rose, onset May 23, 2018, 8.9x, p = .019 | Media Cloud: beyond chance in order, onset May 22, 2018, 34.1x, p = .019 | not run | confirmed |
| ice-bucket 4 | Project MinE helps identify NEK1 | Jul 25, 2016 | rose, no placebo history, onset Jul 27, 2016, 870.9x | Media Cloud: timed (sparse), onset Jul 27, 2016, 11.1x | not run | not measured |
| queens-gambit-2 1 | The Queen's Gambit is released in lockdown | Oct 23, 2020 | rose, no placebo history, onset Oct 25, 2020, 2948.8x | Media Cloud: moved, wrong order, onset Sep 23, 2020, 9.7x, p = .009 | not run | not measured |
| squid-game-ripples 5 | SK Broadband sues Netflix over network costs, citing the traffic surge | Sep 30, 2021 | attention rose, onset Oct 2, 2021, 26.2x, p = .007 | Media Cloud: no sustained rise | not run | partial |
| squid-game-ripples 11 | Netflix launches Squid Game: The Challenge | Nov 22, 2023 | rose, no placebo history, onset Nov 22, 2023, 67829.3x | Media Cloud: beyond chance in order, onset Nov 21, 2023, 12.5x, p = .005 | not run | measured on N |

The checker's attention checks do not apply the ordering rule; the news test does. Where the two onsets agree but come
before the step's own date (trigger laws on Jun 28, 2022, a month before the bans took effect; Wordle before the Times
bought it), the attention belongs to the step before.

**Attention leads.** 2 of 18 leads converge (Running Up That Hill and Master of Puppets after
Stranger Things 4). The rest are tourism and back-catalog leads that national news did not cover, and nine were not
fetched before the stop.

| Step | Claim | Ref | Wikipedia (stored) | News | Television | Class |
|---|---|---|---|---|---|---|
| stranger-things-4: Running Up That Hill | A 1985 Kate Bush song returns | May 27, 2022 | unusual, onset May 30, 2022, 110.4x, p = .006 | Media Cloud: beyond chance in order, onset May 30, 2022, 19.9x, p = .006 | not run | confirmed |
| stranger-things-4: Lukiškės Prison | The Vilnius prison used for filming, now an arts venue | May 27, 2022 | unusual, onset May 29, 2022, 40.5x, p = .006 | Media Cloud: no sustained rise | not run | partial |
| stranger-things-4: Master of Puppets (song) | Metallica's 1986 track finds a new audience | May 27, 2022 | unusual, onset Jul 2, 2022, 30.7x, p = .006 | Media Cloud: beyond chance in order, onset Jul 4, 2022, 12.6x, p = .006 | not run | confirmed |
| wednesday: Bloody Mary (song) | A dance trend revives a 2011 Lady Gaga track | Nov 23, 2022 | unusual, onset Jan 8, 2023, 3997.4x, p = .006 | Media Cloud: no sustained rise | not run | partial |
| wednesday: Cantacuzino Castle | The Romanian castle that played Nevermore Academy | Nov 23, 2022 | unusual, onset Nov 27, 2022, 92.2x, p = .006 | Media Cloud: no sustained rise | not run | partial |
| saltburn: Murder on the Dancefloor | Sophie Ellis-Bextor's 2001 hit returns | Nov 17, 2023 | unusual, onset Nov 25, 2023, 82.9x, p = .005 | Media Cloud: moved, wrong order, onset Oct 29, 2023, 25.2x, p = .005 | not run | partial |
| squid-game: Ddakji | The show's playground games become a craze | Sep 17, 2021 | unusual, onset Sep 26, 2021, 6499.7x, p = .008 | Media Cloud: no sustained rise | not run | partial |
| squid-game: SK Broadband | Korea's internet provider and Netflix's traffic | Sep 17, 2021 | unusual, onset Oct 2, 2021, 24.9x, p = .007 | Media Cloud: no sustained rise | not run | partial |
| the-bear: Italian beef | Chicago's Italian beef sandwich in the spotlight | Jun 23, 2022 | unusual, onset Jun 26, 2022, 4.9x, p = .006 | Media Cloud: no sustained rise | not run | partial |
| bridgerton: Ranger's House | A Greenwich house that played the Featheringtons' home | Dec 25, 2020 | unusual, onset Jan 2, 2021, 38.2x, p = .008 | Media Cloud: not run | not run | untested |
| queens-gambit: The Steps of the Sun | Readers turn to Walter Tevis's other novels | Oct 23, 2020 | unusual, onset Oct 25, 2020, 52.4x, p = .008 | Media Cloud: not run | not run | untested |
| chernobyl: Voices from Chernobyl | The oral history behind the series | May 6, 2019 | unusual, onset May 29, 2019, 123.3x, p = .012 | Media Cloud: not run | not run | untested |
| chernobyl: Ignalina Nuclear Power Plant | The Lithuanian plant that stood in for Chernobyl | May 6, 2019 | unusual, onset May 9, 2019, 58.4x, p = .012 | Media Cloud: not run | not run | untested |
| chernobyl: Chernobyl Children International | A Chernobyl children's charity draws attention | May 6, 2019 | unusual, onset May 9, 2019, 14.2x, p = .012 | Media Cloud: not run | not run | untested |
| tiger-king: Greater Wynnewood Exotic Animal Park | The zoo at the center of the show | Mar 20, 2020 | unusual, onset Mar 23, 2020, 1280x, p = .013 | Media Cloud: not run | not run | untested |
| tiger-king: Big Cat Rescue | Carole Baskin's sanctuary in the spotlight | Mar 20, 2020 | unusual, onset Mar 24, 2020, 739x, p = .010 | Media Cloud: not run | not run | untested |
| the-last-of-us: Long Long Time | Episode 3 revives a 1970 Linda Ronstadt song | Jan 15, 2023 | unusual, onset Feb 1, 2023, 36.9x, p = .006 | Media Cloud: not run | not run | untested |
| shogun: Gai-Jin | Readers turn to James Clavell's other novels | Feb 27, 2024 | unusual, onset Feb 28, 2024, 20.7x, p = .005 | Media Cloud: not run | not run | untested |

## 4. Before August 2015: steps measured for the first time

Media Cloud's US National collection carries daily totals from Jul 2, 2009 (about 3,500 stories a day in 2009, 6,000 in
2011, 16,000 in 2014), so a step needs about 610 days of history (Mar 2011) for a full placebo test.
**7 of 42 registered steps are measured beyond chance in order**, the first measured attention before
Wikipedia's window: the 60 Minutes insider-trading segment (news of insider trading and Congress the next day, 14x,
p = .025), the Senate's STOCK Act vote, the NRC's Vogtle license, Fukushima, the Thailand floods, the Ice Bucket
Challenge and the dress. Two steps moved before their date (the Sony hack's coverage began Dec 14, 2014, before the FBI's
attribution on the step's Dec 19; the ALS Association's rise on Aug 15, 2014, before the $115 million total on Aug 29).
Steps from 2009 and 2010 (the Zadroga bill, Eyjafjallajokull, Cash for Clunkers) rose but have too little history for a
p. Television, which reaches the same years, is not yet run.

| Step | Claim | Date | Media Cloud (US National) | Television | Result |
|---|---|---|---|---|---|
| frozen 1 | Frozen is released; Elsa becomes a phenomenon | Nov 27, 2013 | within chance, onset Nov 24, 2013, 23.6x, p = .075 | not run | not measured |
| sixty-minutes-stock-act 1 | 60 Minutes airs 'Insiders' on members of Congress trading stock | Nov 13, 2011 | beyond chance in order, onset Nov 14, 2011, 14.2x, p = .025 | not run | measured on N |
| sixty-minutes-stock-act 2 | Cosponsors of the STOCK Act jump from 9 to more than 100 within weeks | Dec 15, 2011 | no sustained rise | not run | not measured |
| sixty-minutes-stock-act 3 | The Senate passes the bill 96–3 | Feb 2, 2012 | beyond chance in order, onset Jan 31, 2012, 10.3x, p = .022 | not run | measured on N |
| sixty-minutes-stock-act 4 | The STOCK Act is signed | Apr 4, 2012 | no sustained rise | not run | not measured |
| sixty-minutes-stock-act 5 | Members' trades must be disclosed within 45 days | Jul 3, 2012 | no sustained rise | not run | not measured |
| daily-show-zadroga 1 | Jon Stewart devotes a full Daily Show to the stalled 9/11 responders' health bill | Dec 16, 2010 | rose, no placebo history, onset Dec 19, 2010, 7.2x | not run | not measured |
| daily-show-zadroga 2 | The Senate passes the bill by unanimous consent six days later | Dec 22, 2010 | rose, no placebo history, onset Dec 19, 2010, 7.2x | not run | not measured |
| daily-show-zadroga 3 | The James Zadroga 9/11 Health and Compensation Act is signed | Jan 2, 2011 | wrong order (no placebo history), onset Dec 19, 2010, 7.4x | not run | not measured |
| america-and-alcohol 13 | Most US teens have a smartphone | Apr 9, 2015 | no sustained rise | not run | not measured |
| america-and-alcohol 15 | Dry January begins as a public campaign | Jan 1, 2013 | no sustained rise | not run | not measured |
| america-and-alcohol 17 | Legal recreational cannabis begins (Colorado) | Jan 1, 2014 | within chance, onset Dec 31, 2013, 12.2x, p = .074 | not run | not measured |
| three-mile-island-nrc 8 | No new reactor is licensed for 33 years, until the NRC approves Vogtle 3 and 4 | Feb 9, 2012 | beyond chance in order, onset Feb 9, 2012, 6.1x, p = .022 | not run | measured on N |
| exxon-valdez-opa90 9 | Single-hull tankers are barred from US waters | Jan 1, 2015 | no sustained rise | not run | not measured |
| liebeck-hot-coffee 10 | HBO's Hot Coffee retells the case and the campaign built on it | Jun 27, 2011 | no sustained rise | not run | not measured |
| columbine-active-shooter 9 | Colorado's Claire Davis School Safety Act lets families sue schools that fail to take reasonable care against violence | Jun 3, 2015 | no sustained rise | not run | not measured |
| flint-lead-pipes 1 | Flint switches its drinking water to the Flint River | Apr 25, 2014 | no sustained rise | not run | not measured |
| flint-lead-pipes 2 | General Motors stops using Flint water at its engine plant because it corrodes parts | Oct 13, 2014 | no sustained rise | not run | not measured |
| serial 1 | Serial season 1 launches | Oct 3, 2014 | within chance, onset Nov 10, 2014, 8.9x, p = .070 | not run | not measured |
| fukushima 1 | Fukushima Daiichi meltdown | Mar 11, 2011 | beyond chance in order, onset Mar 12, 2011, 319.1x, p = .045 | not run | measured on N |
| fukushima 2 | Germany decides to phase out nuclear | May 30, 2011 | no sustained rise | not run | not measured |
| eyjafjallajokull 1 | Icelandic eruption sends ash over Europe | Apr 14, 2010 | rose, no placebo history, onset Apr 16, 2010, 70.6x | not run | not measured |
| eyjafjallajokull 2 | European airspace closes | Apr 15, 2010 | timed (sparse), onset Apr 16, 2010, 46.2x | not run | not measured |
| eyjafjallajokull 4 | Kenyan flower exporters destroy stock | Apr 19, 2010 | rose, no placebo history, onset Apr 20, 2010, 3.4x | not run | not measured |
| thailand-floods 1 | Floods hit Thailand's industrial estates | Oct 8, 2011 | beyond chance in order, onset Oct 12, 2011, 33.2x, p = .027 | not run | measured on N |
| thailand-floods 2 | Hard-drive factories halt | Oct 17, 2011 | no sustained rise | not run | not measured |
| ice-bucket 1 | The Ice Bucket Challenge goes viral | Jul 29, 2014 | beyond chance in order, onset Aug 16, 2014, 389.1x, p = .009 | not run | measured on N |
| ice-bucket 2 | ALS Association raises about $115 million | Aug 29, 2014 | moved, wrong order, onset Aug 15, 2014, 86.9x, p = .009 | not run | not measured |
| ice-bucket 3 | ALSA funds genetics projects, including Project MinE | Dec 1, 2014 | no sustained rise | not run | not measured |
| cash-for-clunkers 1 | CARS rebates begin | Jul 24, 2009 | not testable: no coverage for the baseline | not run | not measured |
| cash-for-clunkers 2 | About 677,000 trade-ins are destroyed | Dec 1, 2009 | no sustained rise | not run | not measured |
| the-dress 1 | The dress photo goes viral | Feb 26, 2015 | beyond chance in order, onset Feb 27, 2015, 19.7x, p = .008 | not run | measured on N |
| the-dress 2 | Scientists take notice | May 14, 2015 | no sustained rise | not run | not measured |
| jurassic-park 3 | Poachers smuggle Mongolian dinosaurs | Oct 1, 2012 | no sustained rise | not run | not measured |
| sony-hack 1 | North Korea hacks Sony Pictures | Dec 19, 2014 | moved, wrong order, onset Dec 14, 2014, 308.8x, p = .008 | not run | not measured |
| sony-hack 2 | Leaked emails show Jennifer Lawrence paid less | Dec 12, 2014 | no sustained rise | not run | not measured |
| planet-earth 3 | Old TVs on dressers crush children | Nov 1, 2011 | no sustained rise | not run | not measured |
| planet-earth 4 | CPSC launches 'Anchor It!' | Jun 1, 2015 | no sustained rise | not run | not measured |
| gangnam-style 1 | Gangnam Style goes viral | Dec 21, 2012 | no sustained rise | not run | not measured |
| gangnam-style 2 | Views approach 2,147,483,647 | Dec 1, 2014 | within chance, onset Dec 6, 2014, 12.9x, p = .076 | not run | not measured |
| manhunt-byron 5 | The Digital Economy Act 2010 makes video game ratings legally enforceable | Apr 8, 2010 | no sustained rise | not run | not measured |
| manhunt-byron 6 | PEGI becomes the statutory UK rating system | Jul 30, 2012 | no sustained rise | not run | not measured |

## 5. Catalyst detection

Not run as registered. The scan needs every panel entity's news series; GDELT was closed and Media Cloud stopped before
the panel. The scan code ran on the 13 panel entities that shared a query with an earlier step, as a smoke test only: its
strongest changes were catalog stones it was not told about (Running Up That Hill on May 30, 2022; Master of Puppets on
Jul 4, 2022; Adnan Syed on Sep 17, 2022; Three Mile Island on Sep 20, 2024; alcohol and cancer on Jan 3, 2025), and each
converged with Wikipedia within a day. That shows the rule recovers known stones; it says nothing yet about new ones.

## 6. Limits

- Television and GDELT's news are missing from this version. For the six non-converging steps, television is the family
  that could still confirm them.
- Media Cloud and GDELT DOC are both online news; when GDELT runs, it is a second view of the same family, not a third.
- US National is the collection for US steps; Squid Game, ddakji and the Wednesday castle are global stories read through
  US outlets.
- The floor of 3 stories a day decides small cases: a step whose news baseline is zero needs a run of at least 3 a day for
  five days.
- No grade in the product changes in this pass.
