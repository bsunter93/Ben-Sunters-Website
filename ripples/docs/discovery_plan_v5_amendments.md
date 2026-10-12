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
