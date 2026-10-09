"""Where the engine reads and writes.

Tracked inputs (queries, prompts, personas, baselines) live next to the scripts under ripples/engine/. Everything a run
produces (harvested records, raw responses, logs, judged outputs, scores) goes to one work directory, which is never
committed:

  --work DIR                     on any script, or
  RIPPLE_ENGINE_WORK=DIR         in the environment, or
  ripples/engine/work/           the default (listed in .gitignore)

Layout inside the work directory:
  data/      harvest, papers, raw pairs, candidates, predictions, matches, verification verdicts, scores
  raw/       cached responses, keyed by the sha1 of the request URL (the URL never carries a key)
  logs/      requests.log, blocked_hosts.log, harvest_run.log
  blind/     the gate's inputs and outputs: predict_in, predict_raw, match_in, match_raw
  verify/    fetched verification text, judge_in, judge_raw
  rate/      the rater packet and the ratings
"""
import os

ENGINE = os.path.dirname(os.path.abspath(__file__))
RIPPLES = os.path.dirname(ENGINE)
REPO = os.path.dirname(RIPPLES)
DEFAULT_WORK = os.path.join(ENGINE, "work")
SUBDIRS = ["data", "raw", "logs", "blind/predict_in", "blind/predict_raw", "blind/match_in", "blind/match_raw",
           "verify", "verify/judge_in", "verify/judge_raw", "rate", "data/extract_in", "data/extract_out"]


def add_arg(ap):
    """Add the shared --work option to an argparse parser."""
    ap.add_argument("--work", default=None,
                    help="work directory (default: $RIPPLE_ENGINE_WORK, else ripples/engine/work)")
    return ap


def resolve(work=None, create=True):
    """Return the absolute work directory, creating its layout unless create is False."""
    w = os.path.abspath(work or os.environ.get("RIPPLE_ENGINE_WORK") or DEFAULT_WORK)
    if create:
        for s in SUBDIRS:
            os.makedirs(os.path.join(w, s), exist_ok=True)
    return w


def fill(template_path, **values):
    """Read a text template and replace {name} placeholders. Unknown braces are left alone."""
    t = open(template_path).read()
    for k, v in values.items():
        t = t.replace("{" + k + "}", str(v))
    return t
