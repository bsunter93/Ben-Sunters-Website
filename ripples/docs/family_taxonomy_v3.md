# Ripple Map event-family taxonomy v3 (2026-09-28)

Why a new taxonomy: family pooling finds ripples that recur across events. Broad families (screen v2's
"streaming hits": nine different shows) average a strong single-event ripple away; that is how The Queen's Gambit ->
Chess vanished there. The one replicated ripple so far (space events -> Speed of light) came from tight families of
8-12 events of the same kind. v3 therefore defines families mechanism-first.

## Rules for a family

1. **One kind of event, one mechanism.** For example "US hurricane landfalls", not "natural disasters"; "FDA/WHO
   approvals of a named drug or vaccine", not "medicine".
2. **An anchor day.** Day 0 is the day public attention starts: landfall, mainshock, keynote, launch, ceremony,
   approval, announcement. Placeholder dates (1 January, the 1st of a month with no event on that day) are not
   anchors. When only a short window is known, the family file gives `start..end` and day 0 is the peak of the event
   article's own views in that window.
3. **10-20 events.** Fewer than 10 has too little power; more than 20 usually means the family is too broad.
4. **Spread out.** Events ideally at least 30 days apart. Closer pairs are allowed, but they are flagged, and a
   candidate carried by them is reported as common-shock risk (as for the COVID lockdown in v2).
5. **Window.** 2016-09-01 to 2026-04-30, so each event has a year of history before it and 90 days after it.
6. **One English Wikipedia article per event**, carrying the event's own attention. It may be shared by several
   events on different dates (e.g. "Bitcoin" for price milestones).
7. **Sources.** Owner corpus first. Dates from the public record are added only where the date is not in doubt
   (annual ceremonies, landfalls, mainshocks); these are marked `PR-` in the family file.

## Families

Status: **runnable**, with at least 10 events that meet the rules (registered as screen v3), or **needs events**
(defined, but the owner is asked for more).

| Domain | Family | Events now | Status | Mechanism being tested |
|---|---|---|---|---|
| Tech / AI | ai_model_releases | 16 | runnable (second look: 8 v2 ai_models events overlap) | new AI capability -> attention to the jobs, skills and topics it touches |
| Tech / consumer hardware | apple_product_launches | 10 | runnable | product keynotes -> attention to the categories and habits they change |
| Tech / consumer hardware | game_console_launches | 8 | needs events | console launches -> gaming culture topics |
| Tech / platforms | social_platform_moments | 11 | runnable | platform launches, ownership and brand shocks -> media and speech topics |
| Space | spacex_milestones | 11 | runnable | launch spectacles -> physics, engineering and space topics |
| Money | crypto_shocks | 11 | runnable | price milestones, collapses, ETFs -> finance and technology topics |
| Transport | ev_milestones | 11 | runnable | EV unveilings and deliveries -> energy, cars and industry topics |
| Health | drug_vaccine_approvals | 12 | runnable | approvals -> the disease, body and diet topics they concern |
| Culture / ceremonies | academy_awards | 10 | runnable (annual) | the ceremony -> film, fashion and culture topics |
| Culture / ceremonies | super_bowls | 10 | runnable (annual) | the game and halftime show -> food, music and advertising topics |
| Disasters | hurricanes | 15 | runnable (seasonal) | landfalls -> geography, climate, insurance and relief topics |
| Disasters | earthquakes | 11 | runnable | mainshocks -> geology, geography and aid topics |
| Culture / games | game_releases | 7 | needs events | blockbuster game launches -> history, myth and craft topics |
| Culture / streaming | streaming_service_launches | 5 | needs events | service launches -> the franchises they carry |
| Culture / streaming | drama_series_premieres | 0 with exact dates | needs events | a series premiere -> the real-world subject of the series (the Chess mechanism) |
| Culture / film | film_openings | 7 | needs events | opening weekend -> the film's real-world subject |
| People | celebrity_deaths | 3 | needs events | a death -> the person's work, era and cause of death |
| Society | us_mass_shootings | 0 | needs events | attacks -> policy, place and mental-health topics |
| Society | landmark_court_rulings | about 6 | needs events | rulings -> the rights and topics decided |
| Society | referendums | about 6 | needs events | votes -> the issue voted on |
| Tech / security | cyberattacks_and_outages | 4 | needs events | attacks and outages -> security and infrastructure topics |
| Sport | sports_finals | 0 with exact dates | needs events | finals (World Cup, NBA, Champions League) -> places, players and the sport |

Annual and seasonal families (Oscars, Super Bowls, hurricanes) cannot separate a ripple from the time of year: every
member falls in the same season. Their candidates always get a hand check for a plain seasonal explanation (for
example, Valentine's Day around the Super Bowl), recorded before any confirmation.

## What would help most (for the owner)

For each family below, **12-15 events** with an **exact date** (the day attention began) and, if you know it, the
**English Wikipedia article**. Events from 2016-09 to 2026-04.

- **drama_series_premieres** (highest value; it is the Queen's Gambit -> Chess mechanism): prestige drama premieres
  whose subject is a real-world thing people could look up (chess, a historical period, a profession, a place).
- **celebrity_deaths**: deaths of widely known musicians, actors and athletes (e.g. the day of death or of the
  announcement).
- **film_openings**: wide-release films about a real subject (a person, an event, a place, a science), with opening
  dates.
- **game_releases**: blockbuster game launches, with release dates.
- **sports_finals**: finals of major tournaments, with match dates.
- **us_mass_shootings, landmark_court_rulings, referendums, cyberattacks_and_outages**: 12-15 each, with dates.
- **game_console_launches, streaming_service_launches**: 5-8 more each.

Families that reach 10 good events are registered and screened like the runnable ones.

## Update 2026-09-28: owner batch added

The owner supplied 500 dated events with Wikipedia articles and a named subject for each
(`ripples/corpus/events_taxonomy_batch1.csv`). With it:

- **12 families are now runnable**, all in screen v3 (amendment A in `q3_protocol_v3.md`): drama_premieres,
  true_story_films, game_releases, music_icon_deaths, screen_icon_deaths, football_finals, us_league_finals,
  us_mass_shootings, scotus_rulings, referendums, cyberattacks_outages, console_launches.
- **Still short:** streaming_service_launches (8 events).
- **The subject column opens a stronger test.** Each event is tested against its own named subject: 197 event →
  subject pairs (`ripples/docs/q4_protocol_v1.md`).
- **Next most useful from the owner:** held-out events for any family that produces candidates, used to confirm them,
  and named subjects for events in the older corpus.

## Update 2026-09-28: owner validation pack

The owner's validation pack (`ripples/corpus/validation_pack_1.csv`, 91 rows) is registered before any of it is run:

- **streaming_service_launches** is now runnable (10 events; screen v3 amendment B).
- **43 more event → subject pairs** from the older corpus form Q4 v1b, in three families: culture, science and tech,
  and news (`q4_protocol_v1.md`, addendum 1).
- **8 held-out drama premieres** will confirm or fail to confirm the Q4 drama family.
- **Most useful next from the owner:**
  - more held-out premieres (15-20 would give the confirmation real power);
  - exact dates for the 7 flagged rows (WeWork, Peloton, Stanley, Robinhood, D&D, mukbang, Dalgona coffee);
  - held-out events for Q4 v1b's science and news families.
