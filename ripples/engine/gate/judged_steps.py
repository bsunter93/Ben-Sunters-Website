"""The blind predictability gate: inputs and logs for its two judged steps, prediction and then matching.

    python3 ripples/engine/gate/judged_steps.py predict-inputs <wave>      # new stones -> blind/predict_in/<wave>_bNN.json
    python3 ripples/engine/gate/judged_steps.py assemble-predictions        # blind/predict_raw/*.jsonl -> data/predictions.jsonl
    python3 ripples/engine/gate/judged_steps.py match-inputs <wave>         # candidates -> blind/match_in/<wave>_cNN.json
    python3 ripples/engine/gate/judged_steps.py assemble-matches            # blind/match_raw/*.jsonl -> data/matches.jsonl
    python3 ripples/engine/gate/judged_steps.py status                      # what is done and what is waiting

Between the script steps, predict_v1.txt is applied to each prediction batch and match_v1.txt to each match chunk, each
in a fresh context that reads only the prompt and its own input file (python3 ripples/engine/runner.py predict|match
<file> prints those instructions). Predictions are made from the stone's name and date only, and all of them are
finished before any candidate text reaches the prediction step; matching sees one candidate's outcome and claim plus
its stone's 25 predictions, nothing else.

Pass the gate = the outcome is not matched at any rank. Rank and level are logged for every candidate either way.

Stones come from data/stones.json ({stone_id: {name, date, cache_id or null}}); candidates from
data/candidates_core.json. A stone with a cache_id reuses an earlier run's predictions: pass that run's predictions
file with --cache (one JSON object per line with catalyst_id, input, predictions, prompt_sha256 and run).
Options: --runner LABEL is written into each assembled record (free text naming how the fresh contexts were run).
"""
import argparse
import datetime
import glob
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import workdir  # noqa: E402

PRED_PROMPT = os.path.join(HERE, "predict_v1.txt")
MATCH_PROMPT = os.path.join(HERE, "match_v1.txt")
PRED_BATCH, MATCH_CHUNK = 10, 25


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def mtime_utc(p):
    return datetime.datetime.fromtimestamp(os.path.getmtime(p), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_jsonl(p):
    return [json.loads(l) for l in open(p) if l.strip()] if p and os.path.exists(p) else []


def predict_inputs(W, wave):
    S = json.load(open(f"{W}/data/stones.json"))
    have = {r["stone_id"] for r in load_jsonl(f"{W}/data/predictions.jsonl")}
    queued = set()
    for f in glob.glob(f"{W}/blind/predict_in/*.json"):
        queued |= {r["catalyst_id"] for r in json.load(open(f))}
    todo = [{"catalyst_id": sid, "name": s["name"], "date": s["date"]} for sid, s in sorted(S.items())
            if not s.get("cache_id") and sid not in have and sid not in queued]
    n = 0
    for i in range(0, len(todo), PRED_BATCH):
        n += 1
        base = f"{W}/blind/predict_in/{wave}_b{n:02d}"
        if os.path.exists(base + ".json"):
            raise SystemExit(f"{base}.json exists; use a new wave name")
        json.dump(todo[i:i + PRED_BATCH], open(base + ".json", "w"), indent=1, ensure_ascii=False)
        open(base + ".started_utc", "w").write(now() + "\n")
    print("new stones", len(todo), "batches", n, "prompt sha256", sha(PRED_PROMPT))


def assemble_predictions(W, cache_path, runner):
    S = json.load(open(f"{W}/data/stones.json"))
    cache = {r["catalyst_id"]: r for r in load_jsonl(cache_path)}
    pred_sha = sha(PRED_PROMPT)
    out = {}
    for sid, s in S.items():
        if s.get("cache_id"):
            if s["cache_id"] not in cache:
                raise SystemExit(f"stone {sid} has cache_id {s['cache_id']} but --cache has no such catalyst")
            c = cache[s["cache_id"]]
            if c["prompt_sha256"] != pred_sha:
                raise SystemExit(f"cached predictions for {s['cache_id']} were made with another prompt")
            out[sid] = {"stone_id": sid, "input": c["input"], "predictions": c["predictions"], "prompt_sha256": c["prompt_sha256"],
                        "run": {"cached_from": f"{os.path.basename(cache_path)}:{s['cache_id']}", **c.get("run", {})}}
    for f in sorted(glob.glob(f"{W}/blind/predict_raw/*.jsonl")):
        b = os.path.basename(f)[:-6]
        inp = json.load(open(f"{W}/blind/predict_in/{b}.json"))
        rows = load_jsonl(f)
        assert [r["catalyst_id"] for r in rows] == [i["catalyst_id"] for i in inp], f"{b}: order differs from its input"
        st = open(f"{W}/blind/predict_in/{b}.started_utc").read().strip()
        for r, i in zip(rows, inp):
            assert len(r["predictions"]) == 25, (b, r["catalyst_id"])
            out[r["catalyst_id"]] = {"stone_id": r["catalyst_id"], "input": {"name": i["name"], "date": i["date"]},
                                     "predictions": r["predictions"], "prompt_sha256": pred_sha,
                                     "run": {"batch": b, "runner": runner, "started_utc": st, "finished_utc": mtime_utc(f)}}
    with open(f"{W}/data/predictions.jsonl", "w") as fo:
        for sid in sorted(out):
            fo.write(json.dumps(out[sid], ensure_ascii=False) + "\n")
    missing = sorted(sid for sid in S if sid not in out)
    print("predictions", len(out), "missing", missing)


def match_inputs(W, wave):
    P = {r["stone_id"]: r for r in load_jsonl(f"{W}/data/predictions.jsonl")}
    C = json.load(open(f"{W}/data/candidates_core.json"))
    missing = sorted({c["stone_id"] for c in C if c["stone_id"] not in P})
    if missing:
        raise SystemExit(f"predictions missing for {len(missing)} stones (finish prediction first): {missing[:5]}")
    have = {r["candidate_id"] for r in load_jsonl(f"{W}/data/matches.jsonl")}
    queued = set()
    for f in glob.glob(f"{W}/blind/match_in/*.json"):
        queued |= {r["candidate_id"] for r in json.load(open(f))}
    todo = [c for c in C if c["candidate_id"] not in have and c["candidate_id"] not in queued and not c.get("drop")]
    todo.sort(key=lambda c: (c["stone_id"], c["candidate_id"]))
    n = 0
    for i in range(0, len(todo), MATCH_CHUNK):
        n += 1
        base = f"{W}/blind/match_in/{wave}_c{n:02d}"
        if os.path.exists(base + ".json"):
            raise SystemExit(f"{base}.json exists; use a new wave name")
        items = [{"candidate_id": c["candidate_id"],
                  "catalyst": f"{P[c['stone_id']]['input']['name']} ({P[c['stone_id']]['input']['date']})",
                  "outcome": c["outcome"], "claim": c["claim"], "myth_check": False, "predictions": P[c["stone_id"]]["predictions"]}
                 for c in todo[i:i + MATCH_CHUNK]]
        json.dump(items, open(base + ".json", "w"), indent=1, ensure_ascii=False)
        open(base + ".started_utc", "w").write(now() + "\n")
    print("candidates to match", len(todo), "chunks", n, "rule sha256", sha(MATCH_PROMPT))


def assemble_matches(W, runner):
    out = {}
    match_sha = sha(MATCH_PROMPT)
    for f in sorted(glob.glob(f"{W}/blind/match_raw/*.jsonl")):
        b = os.path.basename(f)[:-6]
        inp = json.load(open(f"{W}/blind/match_in/{b}.json"))
        rows = {r["candidate_id"]: r for r in load_jsonl(f)}
        assert set(rows) == {i["candidate_id"] for i in inp}, f"{b}: ids differ from its input"
        st = open(f"{W}/blind/match_in/{b}.started_utc").read().strip()
        for i in inp:
            r = rows[i["candidate_id"]]
            rank = r.get("rank")
            assert rank is None or (isinstance(rank, int) and 1 <= rank <= 25), (b, r)
            assert (rank is None) == (r.get("level") is None), (b, r)
            out[i["candidate_id"]] = {"candidate_id": i["candidate_id"], "rank": rank, "level": r.get("level"),
                                      "prediction": r.get("prediction"), "reason": r.get("reason"), "outcome": i["outcome"],
                                      "prompt_sha256": match_sha,
                                      "run": {"chunk": b, "runner": runner, "started_utc": st, "finished_utc": mtime_utc(f)}}
    with open(f"{W}/data/matches.jsonl", "w") as fo:
        for cid in sorted(out):
            fo.write(json.dumps(out[cid], ensure_ascii=False) + "\n")
    print("matches", len(out), "passed the gate (not predicted)", sum(1 for r in out.values() if r["rank"] is None))


def status(W):
    S = json.load(open(f"{W}/data/stones.json")) if os.path.exists(f"{W}/data/stones.json") else {}
    C = json.load(open(f"{W}/data/candidates_core.json")) if os.path.exists(f"{W}/data/candidates_core.json") else []
    P = load_jsonl(f"{W}/data/predictions.jsonl")
    M = load_jsonl(f"{W}/data/matches.jsonl")
    wait_p = [f for f in glob.glob(f"{W}/blind/predict_in/*.json")
              if not os.path.exists(f"{W}/blind/predict_raw/{os.path.basename(f)[:-5]}.jsonl")]
    wait_m = [f for f in glob.glob(f"{W}/blind/match_in/*.json")
              if not os.path.exists(f"{W}/blind/match_raw/{os.path.basename(f)[:-5]}.jsonl")]
    print(f"stones {len(S)} (cached {sum(1 for s in S.values() if s.get('cache_id'))}), predictions assembled {len(P)}, "
          f"prediction batches waiting {len(wait_p)}")
    print(f"candidates {len(C)}, matches assembled {len(M)}, passed {sum(1 for r in M if r['rank'] is None)}, "
          f"match chunks waiting {len(wait_m)}")
    print("prompt sha256: predict", sha(PRED_PROMPT), "match", sha(MATCH_PROMPT))


def main():
    ap = argparse.ArgumentParser(description="Inputs and logs for the gate's judged steps.")
    ap.add_argument("cmd", choices=["predict-inputs", "assemble-predictions", "match-inputs", "assemble-matches", "status"])
    ap.add_argument("wave", nargs="?", help="a short name for this round (predict-inputs, match-inputs)")
    ap.add_argument("--cache", help="an earlier run's predictions file, for stones with a cache_id")
    ap.add_argument("--runner", default="fresh context per batch; read only the prompt and its input file")
    workdir.add_arg(ap)
    a = ap.parse_args()
    W = workdir.resolve(a.work)
    if a.cmd in ("predict-inputs", "match-inputs") and not a.wave:
        ap.error(a.cmd + " needs a wave name")
    if a.cmd == "predict-inputs":
        predict_inputs(W, a.wave)
    elif a.cmd == "assemble-predictions":
        assemble_predictions(W, a.cache, a.runner)
    elif a.cmd == "match-inputs":
        match_inputs(W, a.wave)
    elif a.cmd == "assemble-matches":
        assemble_matches(W, a.runner)
    else:
        status(W)


if __name__ == "__main__":
    main()
