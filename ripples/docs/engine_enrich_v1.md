# Engine: enrich and a person's scoreboard (Oct 11, 2026)

Two stages added to `ripples/engine/`, from the day's work on the study stories. Commands are in the engine README.

## Enrich: build-ready study stories

A good find becomes a story with two fields it lacked: the authors' reason (`test.why`) and the paper's own number as
a chart (`test.fx`). `enrich/fulltext.py` finds an open copy (PubMed Central, then OpenAlex's open locations,
repositories first; never SSRN) through the engine's fetcher, so the host rule holds: one retry on a server error, then
the host stops for the day. Two fixed prompts read the abstract (why) and the full text (fx). `enrich/judged.py
assemble` keeps a row only when its quote is in the text it read and every number on a bar is in that quote; it caught
a planted wrong number and a planted wrong quote in testing, and passed all 28 why lines and 10 chart specs made on
Oct 11. A person then reads `enrich/enrich.json`; `enrich/apply.py` writes what remains into the chains file.

## A person decides surprising

The simulated panel matched the owner's blind ratings at .35 on surprise and .02 on belief, and its surprise ran
against its own belief (-0.75) where his did not (-0.03). `rate/human/pick.py` draws a blind batch (thirds by panel
surprise, half with a why line, planted controls), `build_page.py` fills the rating page, and `score.py` reads the
ratings back: good per 100, the controls, the why line's effect and agreement with the panel. Run on the owner's 50
ratings it gives 36.4 good per 100 real findings and 43.5 per 100 gate passers, the same numbers as the day's analysis.
