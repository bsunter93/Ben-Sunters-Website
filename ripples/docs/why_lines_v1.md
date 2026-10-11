# Why lines on study stories (Oct 11, 2026)

Each study story now shows the paper's own reason for its finding under the headline, and again on the study's step
in "Every step and how we know it".

- Source: the study's abstract only. Every line has a `why_quote` in `chains/batch18.json` and `batch19.json`, copied
  word for word from the abstract.
- Label: "Why, per the authors:" when the abstract reports evidence for the reason (9 stories); "The authors' best
  guess:" when the authors only propose it (19). 20 stories show no line: 18 abstracts give no reason and 2 papers
  have no abstract.
- No line is written by us. In the owner's blind ratings, a planted false claim shown with a made-up reason was rated
  fully believable, so an unsourced reason never goes on a card.

## Why add them

A test on 95 study findings (five simulated raters, registered before rating): a one-line reason raised "I understand
why" by 0.41 on a 5-point scale and belief by 0.06. In the owner's own blind ratings of 50 findings, belief was 4.07
with a reason and 3.73 without (15 each). Reasons quoted from the paper did better than reasons written for the test.

## Checks

`tools/qa/why_test.js`: the line shows on every study story that has one and is hidden on the rest, with the right
label, at 1440x900 and 375x812, with no sideways scroll.
