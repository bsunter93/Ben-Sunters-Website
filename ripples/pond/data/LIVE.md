# Live data for the pond (published daily, no hand edits)

Base: `https://kffkasnzqcddpystszch.supabase.co/storage/v1/object/public/ripples/`
Written by the `ripples-publish` edge function (v2 runs 08:25 and 08:40 UTC), cache 300 s.

| File | Source | Shape |
|---|---|---|
| `v2/pond/index.json` | `public.rm_pond()` | `{v, as_of, flagship, ponds[{event_id, slug, name, label, emoji, family, onset, sensitive, is_control, version, stops{measured,likely,watching,flat}, archetype, story_sentence, url}], note}`. The flagship is listed first. |
| `v2/pond/{slug}.json` | `public.rm_pond(slug)` → `ripples.rm_pond_payload(event_id)` | Same top-level shape as `data/milton.json` (`v, version, snapshot_at, engine, honesty, event, story, travel, domains, domain_keys, rings, effects[], flats[], flats_note, controls[], untested[], shore[], rivals[], filtered[], watching, pattern_next, calibration, ledger[], ledger_head, links, changelog[]`). The fixture is `ripples/contract/fixtures/v2/pond.json`. |
| `v2/stories.json` | `public.rm_stories(50, 36500)` | The story layer's `featured[]` (fixture `contract/fixtures/v2/stories.json`). |
| `v2/patterns.json` | `public.rm_patterns()` | An array of 6.2 world rules, including hints. Each carries `strength`. |

The flagship today is `hurricane-milton-positive-control-213.json`, i.e. `v2/pond/hurricane-milton-positive-control-213.json`.

## How the live payload differs from the hand-built snapshot

- **Tiers.** `effects[].tier` is the tier of the frozen public version after the forecast gate. `engine_tier` is the engine's own tier, and `published{tier, engine_tier, reason, ce}` is the gate record.
  - Milton hop 6101 is **Measured**: the engine says Measured, and the forecast check agreed (2 of 2 series) at 04:56 UTC on 2026-09-26.
  - The RPC returns null, and the file is removed, if a Measured word is ever unsupported by the gate.
- **Domains.** `domains` and `domain_keys` list only the domains that this pond draws. Every item carries `domain` (an index into that list) and `domain_key`.
- **Contrast.** `effects[].contrast` is the 6.2 regional contrast (Milton: −19.9 %, z −4.77, p_space 1 in 31, 0 of 41 in-time placebos as big). It is null where the event has none.
- **Replication.** `replication` comes from the contrast pool when there is one; otherwise it is the story layer's. `story_replication` is always the story layer's.
- **Chart.** `chart.series[]` is `{d, t, o: null, v}`: the hop's own daily series, indexed to its 28-day pre-onset mean (`t`), plus the raw value (`v`). There is no donor line (`o`) yet.
- **Copy.** `story` copy comes from the story layer (`derived_by` says so). Copy is never generated in the frontend.
  - `conversation_hook` is null for quiet (sensitive) events.
  - The editorial copy in the snapshot (`mechanism[].why`, `how`, `mind`, `place`, `strength`) has no live source. It is absent or null in the live payload.
- **Milton's label.** Milton's public label is `Hurricane Milton (positive control)`. `event.name` strips the suffix, and `event.is_control` plus `honesty.control_note` say what the suffix means. Show the note.
- **Provenance.** Each effect's `ledger` gives `register_seq`, `version_seq` and `frozen_hash`. The top-level `ledger[]` holds this event's ledger rows, and `ledger_head` is the chain head.
