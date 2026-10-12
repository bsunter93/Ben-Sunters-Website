# Discovery v5: amendments

The registered plan is `docs/discovery_plan_v5.md` (sha256 `a3d343eeb54162c8ac0a22abe71b92bfc0a3091f14ec6fa0e2a307b485694c83`).
Amendments are logged here before the stage they change runs; the plan file itself is not edited.

## A1 (Oct 12, 2026, 00:11 UTC, before any v5 candidate reached verification): verification sources

Owner, Oct 11: "make the verification fix now, don't wait for v6."

In v4, 29 of 138 verification targets got no text at all, so 17 of the 100 sampled gate passers counted as not
defensible without being read. Crossref had been stopped for the day by an earlier error (24 targets), and publisher
pages refused with 403 or were stopped (the rest). Open copies that were PDFs were read as web pages, which turns a PDF
into noise.

`verify/fetch_text.py` now tries, stopping at the first text that contains the quote: the PubMed abstract, the
Crossref abstract, the Europe PMC abstract, the PubMed Central full text, open copies (the target's own, then
OpenAlex's open locations, repositories first, never SSRN; a PDF read with pdftotext), the DOI landing page last, and
finally OpenAlex's copy of the abstract. A quote found only in OpenAlex's copy is the same text extraction read, so v5
reports how many defensible candidates rest on it, and the primary bar is given with and without them.

Effect on the comparison: v4's defensible rate (75 per 100) was measured with the old order. v5's will be read against
it with that difference stated.

### A1, measured before use (Oct 12, 00:00 to 00:11 UTC)

The new order was run on v4's 29 targets that had no text. With the order alone, 10 found the quote in an independent
source (Crossref 9, Europe PMC 1) and 12 only in OpenAlex's copy; the run's own Crossref was stopped at 00:00:05 by a
404 for a DOI Crossref does not hold. That is the cause of v4's loss: the stop rule treated "not here" as "go away".

`fetch.py` now treats a 404 as a miss, not a stop; a 403, a 429 after its retry, a 5xx after its retry, or any other
4xx still stops the host for the day. Rerun: 18 of 29 found in Crossref, 6 only in OpenAlex's copy, 5 not found.
Repository PDFs found none: most answered with a bot check (403).

`fetch.py` also refuses SSRN outright, including by redirect from a DOI; v4's logs show it reached www.ssrn.com.

## A2 (Oct 12, 2026, 00:21 UTC, after the review of raw pairs, before the gate): findings v4 already had

The plan marks v4's 442 papers as sent so v5 reads only new papers. That held by paper id, but the same findings came
back through other copies of the same work: a working paper and its journal version, a replication package on ICPSR or
Dataverse, a thesis, a data deposit. No v5 DOI matched a v4 candidate; by reading, 33 of the 151 usable raw pairs
state a claim a v4 candidate already states (the same kind of stone, the same outcome, the same direction), and 4
repeat a live story.

Rule, applied in `data/review.json` as `exclude_v4_repeat` with the v4 candidate named in the note: a v5 pair that
makes the same claim as a v4 candidate is dropped before the gate. A different outcome for the same stone stays, and
so does the opposite direction on the same outcome (Uber and more transit trips stays; v4 had less transit). The
owner rated some of these claims on Oct 11, and a repeat is not a new discovery.

Counts after the review: 92 candidates on 67 stones (16 stones reuse v4's predictions); 4 dropped as live, 33 as v4
repeats, 2 as parts of another row's finding, 22 merged into another row's candidate.

Effect on the bars: none on their definitions. The share of raw pairs lost to repeats is reported with the results.
