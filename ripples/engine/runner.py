"""Print the instructions for one judged step: a fixed prompt applied in a fresh context.

A judged step is the part of the engine a script cannot do: reading an abstract, predicting consequences, matching an
outcome to a prediction, judging fetched text, rating an item. Each run of one starts in a fresh context that reads only
the fixed prompt and its own input file and writes only its output file. This script prints those instructions with the
real paths filled in, so every batch gets the same words.

    python3 ripples/engine/runner.py list                                    # judged inputs with no output yet
    python3 ripples/engine/runner.py extract data/extract_in/w1_b01.json     # extraction (generate)
    python3 ripples/engine/runner.py predict blind/predict_in/w1_b01.json    # blind prediction (gate)
    python3 ripples/engine/runner.py match   blind/match_in/w1_c01.json      # blind matching (gate)
    python3 ripples/engine/runner.py verify  verify/judge_in/w1_j01.json     # verification judgment (verify)
    python3 ripples/engine/runner.py rate 1                                  # simulated rater 1 to 5 (rate)

Input paths are relative to the work directory, or absolute.
"""
import argparse
import glob
import json
import os
import sys

ENGINE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ENGINE)
import workdir  # noqa: E402

STEPS = {
    # step: (runner template, fixed prompt, input dir, output dir, output extension)
    "extract": ("generate/run_extract.txt", "generate/extract_prompt.txt", "data/extract_in", "data/extract_out", ".jsonl"),
    "predict": ("gate/run_predict.txt", "gate/predict_v1.txt", "blind/predict_in", "blind/predict_raw", ".jsonl"),
    "match": ("gate/run_match.txt", "gate/match_v1.txt", "blind/match_in", "blind/match_raw", ".jsonl"),
    "verify": ("verify/run_judge.txt", "verify/judge_prompt.txt", "verify/judge_in", "verify/judge_raw", ".jsonl"),
}


def out_path(work, step, inp):
    _, _, _, odir, ext = STEPS[step]
    return os.path.join(work, odir, os.path.splitext(os.path.basename(inp))[0] + ext)


def main():
    ap = argparse.ArgumentParser(description="Print the instructions for one judged step.")
    ap.add_argument("step", choices=["list", "extract", "predict", "match", "verify", "rate"])
    ap.add_argument("target", nargs="?", help="the input file, or the rater number for rate")
    workdir.add_arg(ap)
    a = ap.parse_args()
    work = workdir.resolve(a.work)
    if a.step == "list":
        n = 0
        for step, (_, _, idir, _, _) in STEPS.items():
            for f in sorted(glob.glob(os.path.join(work, idir, "*.json"))):
                if not os.path.exists(out_path(work, step, f)):
                    print(step, os.path.relpath(f, work))
                    n += 1
        items = os.path.join(work, "rate", "items.json")
        if os.path.exists(items):
            for r in json.load(open(os.path.join(ENGINE, "rate", "personas.json")))["raters"]:
                if not os.path.exists(os.path.join(work, "rate", f"ratings_r{r['rater']}.json")):
                    print("rate", r["rater"])
                    n += 1
        print(f"{n} judged runs waiting in {work}")
        return
    if not a.target:
        ap.error("give the input file (or the rater number for rate)")
    if a.step == "rate":
        raters = {str(r["rater"]): r for r in json.load(open(os.path.join(ENGINE, "rate", "personas.json")))["raters"]}
        if a.target not in raters:
            ap.error("rater must be one of " + ", ".join(sorted(raters)))
        r = raters[a.target]
        inp = os.path.join(work, "rate", "items.json")
        n = len(json.load(open(inp)))
        print(workdir.fill(os.path.join(ENGINE, "rate", "rater_prompt.txt"), persona=r["persona"], **{"as": r["as"], "from": r["from"]},
                           input=inp, n=n, seed=r["seed"], output=os.path.join(work, "rate", f"ratings_r{r['rater']}.json")))
        return
    tpl, prompt, _, _, _ = STEPS[a.step]
    inp = a.target if os.path.isabs(a.target) else os.path.join(work, a.target)
    if not os.path.exists(inp):
        raise SystemExit(f"no such input: {inp}")
    print(workdir.fill(os.path.join(ENGINE, tpl), prompt=os.path.join(ENGINE, prompt), input=inp,
                       output=out_path(work, a.step, inp)))


if __name__ == "__main__":
    main()
