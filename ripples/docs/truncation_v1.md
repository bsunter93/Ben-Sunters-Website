# Truncation test v1 (Oct 4, 2026)

The roundtable's fourth idea came with a gate: before building a "grade with a history" on every measured card, check whether the measured grades drift at all. The worry (the enterprise-role persona, Aisha) was that a p computed in 2026 would not be the p computed in 2027, because the placebo pool grows with page history.

**Design.** `ripples/lab/truncation_test.py` recomputes every measured Wikipedia step (13 of the 17 measured steps; the other four are FRED, SSA, a file series and the dose-response design) exactly as the checker would have with the series cut off at Dec 31, 2024, Dec 31, 2025 and today. Same articles, same reference date, same window length. It runs in CI (`ripples-truncation.yml`) with the project's user agent and writes `ripples/docs/results/truncation_v1.json`.

**Result.** 13 steps, 0 flips. Every p and every placebo count is identical at all three cutoffs where the post-step window was complete (Tiger King 0.01 on 100 windows, Wordle 0.007 on 140, Mr Bates 0.023 on 43 and 0.006 on 175, GameStop 0.008 on 121, Squid Game 0.008 on 125, and so on). Two steps (Ocean, the Surgeon General's advisory) had no result at the 2024 cutoff because the step had not happened yet.

**Why.** Reading the checker explains it: the placebo windows are drawn from the page's history *before* the step (`range(130, ri - 200, 14)`), so the pool is fixed on the day the step happens. The only thing that can change after a step is the detection window, which closes `lag + 30` days later. Once that window is complete, the grade is a constant of the data, not of the run date.

**Decision.** The "grade with a history" UI is not built. Measured cards now carry the run date and, from the next CI run, the checker commit (`checker_sha` in the results header), with one sentence saying when a later run could change the figure: only while the post-step window is still open. The enterprise persona's larger point stands on its own merits (a result should be addressable by checker version and input hash); this test settles the narrower claim that grades drift. They do not.
