#!/usr/bin/env python3
"""Nightly second estimator for Ripple Map hops: BigQuery AI.CAUSAL_EFFECT (OWNER_DECISIONS D-12).

1. Ask Supabase for the work list (public.att_ce_hops_to_eval): Likely/Measured real hops whose pre-registered window
   has closed, every positive/negative control hop, and a daily sample of decoy (placebo) hops, one unit per
   (hop, series), with pre + post values as day offsets from the hop onset.
2. Load the units into BigQuery dataset ripples_ce (created if missing; 30-day default table expiration). Every unit is
   re-indexed to a common calendar (offset 0 = DATE 2000-01-01), so one intervention timestamp serves all units and
   weekly seasonality is preserved (offsets keep day-of-week period 7).
3. One AI.CAUSAL_EFFECT call per distinct horizon (num_post_intervention_points = the pre-registered horizon), with
   id_cols => ['unit_id'] and output_time_series => TRUE so the pointwise bounds are available.
4. Every query is dry-run first; the run aborts before executing anything if the total estimate exceeds --max-gib
   (default 5 GiB). Each executed job also carries maximum_bytes_billed = the same ceiling.
5. Interval: the forecast's pointwise bounds summed over the horizon, [SUM(lower), SUM(upper)], give a conservative
   interval for the expected total; with A = actual total, abs effect interval = [A - U, A - L] and relative interval
   = [(A - U)/U, (A - L)/L]. Results go back through public.att_ce_ingest.

Wording rule (D-12): p_value is stored for calibration only; it is never shown as a "probability of causal effect".
"""
from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
from collections import defaultdict

from common import GIB, Supabase, bq_client, dry_run_bytes, finite, fmt_bytes, gh_run_ref, log, run_query, summary

BASE = dt.date(2000, 1, 1)
LOWER_COLS = ["lower_bound", "prediction_interval_lower_bound", "time_series_lower_bound"]
UPPER_COLS = ["upper_bound", "prediction_interval_upper_bound", "time_series_upper_bound"]
ACTUAL_COLS = ["y", "time_series_data", "actual_value", "data_value"]
EXPIRY_MS = 30 * 24 * 3600 * 1000


def pick(cols, names):
    for n in names:
        if n in cols:
            return n
    return None


def ensure_dataset(client, project, dataset, location):
    from google.api_core.exceptions import Forbidden, NotFound
    from google.cloud import bigquery

    ref = f"{project}.{dataset}"
    try:
        ds = client.get_dataset(ref)
        if ds.default_table_expiration_ms != EXPIRY_MS:
            ds.default_table_expiration_ms = EXPIRY_MS
            try:
                client.update_dataset(ds, ["default_table_expiration_ms"])
            except Forbidden:
                log("warning: cannot set the dataset's default table expiration (tables still carry their own)")
        return ds
    except NotFound:
        pass
    ds = bigquery.Dataset(ref)
    ds.location = location
    ds.default_table_expiration_ms = EXPIRY_MS
    ds.description = "Ripple Map AI.CAUSAL_EFFECT scratch (WS-G). Tables expire after 30 days."
    try:
        return client.create_dataset(ds, exists_ok=True)
    except Forbidden as e:
        sys.exit(f"cannot create dataset {ref}: {e}. Grant the service account roles/bigquery.dataEditor on the "
                 f"project, or create {ref} ({location}) and grant it roles/bigquery.dataEditor on that dataset.")


def load_units(client, table_id, units):
    from google.cloud import bigquery

    rows = []
    for u in units:
        h = int(u["horizon"])
        for t, y in zip(u["t"], u["y"]):
            if t >= h:
                continue
            y = finite(y)
            if y is None:
                continue
            rows.append({"unit_id": u["unit_id"], "horizon": h, "ts": (BASE + dt.timedelta(days=int(t))).isoformat(), "y": y})
    schema = [bigquery.SchemaField("unit_id", "STRING", mode="REQUIRED"),
              bigquery.SchemaField("horizon", "INT64", mode="REQUIRED"),
              bigquery.SchemaField("ts", "DATE", mode="REQUIRED"),
              bigquery.SchemaField("y", "FLOAT64", mode="REQUIRED")]
    cfg = bigquery.LoadJobConfig(schema=schema, write_disposition="WRITE_TRUNCATE")
    client.load_table_from_json(rows, table_id, job_config=cfg).result()
    tbl = client.get_table(table_id)
    tbl.expires = dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=30)
    client.update_table(tbl, ["expires"])
    return len(rows)


def ce_sql(input_id, out_id, horizon, confidence):
    return f"""
CREATE OR REPLACE TABLE `{out_id}`
OPTIONS (expiration_timestamp = TIMESTAMP_ADD(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)) AS
SELECT * FROM AI.CAUSAL_EFFECT(
  (SELECT unit_id, ts, y FROM `{input_id}` WHERE horizon = {int(horizon)}),
  data_col => 'y',
  timestamp_col => 'ts',
  intervention_timestamp => TIMESTAMP '{BASE.isoformat()} 00:00:00+00',
  id_cols => ['unit_id'],
  confidence_level => {float(confidence)},
  num_post_intervention_points => {int(horizon)},
  output_time_series => TRUE
)""".strip()


def summarise_sql(out_id, cols):
    lo, hi, act = pick(cols, LOWER_COLS), pick(cols, UPPER_COLS), pick(cols, ACTUAL_COLS)
    def c(name, default="NULL"):
        return f"`{name}`" if name and name in cols else default
    post = f"{c(hi)} IS NOT NULL" if hi else "FALSE"
    return f"""
SELECT unit_id,
  MAX({c('p_value')}) AS p_value,
  MAX({c('absolute_effect')}) AS absolute_effect,
  MAX({c('relative_effect')}) AS relative_effect,
  STRING_AGG(DISTINCT NULLIF(CAST({c('status', 'NULL')} AS STRING), ''), '; ') AS status,
  SUM(IF({post}, {c(lo)}, NULL)) AS sum_lower,
  SUM(IF({post}, {c(hi)}, NULL)) AS sum_upper,
  SUM(IF({post}, {c(act)}, NULL)) AS sum_actual,
  COUNTIF({post}) AS n_post
FROM `{out_id}` GROUP BY unit_id""".strip(), {"lower": lo, "upper": hi, "actual": act}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project", default="ripple-509716")
    ap.add_argument("--dataset", default="ripples_ce")
    ap.add_argument("--location", default="US")
    ap.add_argument("--as-of", default=None, help="YYYY-MM-DD (default: today UTC)")
    ap.add_argument("--max-units", type=int, default=400)
    ap.add_argument("--decoy-sample", type=int, default=120)
    ap.add_argument("--max-gib", type=float, default=5.0, help="abort if the dry-run total exceeds this")
    ap.add_argument("--dry-run-only", action="store_true")
    a = ap.parse_args()
    if a.as_of and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", a.as_of):
        sys.exit("--as-of must be YYYY-MM-DD")
    cap = int(a.max_gib * GIB)

    sb = Supabase()
    run_id = sb.rpc("att_ce_log_run", {"p": {"kind": "causal_effect", "gh_run": gh_run_ref(),
                                               "detail": {"dry_run_only": a.dry_run_only, "max_gib": a.max_gib}}})
    log(f"run_id {run_id}")

    def finish(status, **kw):
        sb.rpc("att_ce_log_run", {"p": {"run_id": run_id, "status": status, **kw}})

    try:
        work = sb.rpc("att_ce_hops_to_eval", {"p_as_of": a.as_of, "p_max_units": a.max_units,
                                              "p_decoy_sample": a.decoy_sample, "p_pre_days": None})
        units = work.get("units") or []
        model, conf, as_of = work["model_version"], float(work.get("confidence") or 0.95), work["as_of"]
        by_role = defaultdict(int)
        for u in units:
            by_role[u["role"]] += 1
        log(f"as_of {as_of} model {model}: {len(units)} units {dict(by_role)}")
        summary(f"### AI.CAUSAL_EFFECT {as_of}\n- units: {len(units)} {dict(by_role)}")
        if not units:
            finish("ok", units=0, rows_written=0, detail={"note": "nothing to evaluate"})
            return 0

        client = bq_client(a.project, a.location)
        ensure_dataset(client, a.project, a.dataset, a.location)
        tag = f"{as_of.replace('-', '')}_{run_id}"
        input_id = f"{a.project}.{a.dataset}.ce_input_{tag}"
        n_points = load_units(client, input_id, units)
        log(f"loaded {n_points} points into {input_id}")

        horizons = sorted({int(u["horizon"]) for u in units})
        plans, total = [], 0
        for h in horizons:
            out_id = f"{a.project}.{a.dataset}.ce_out_{tag}_h{h}"
            sql = ce_sql(input_id, out_id, h, conf)
            b = dry_run_bytes(client, sql)
            total += b
            plans.append((h, out_id, sql, b))
            log(f"dry-run horizon {h}: {fmt_bytes(b)}")
        log(f"dry-run total: {fmt_bytes(total)} (cap {fmt_bytes(cap)})")
        summary(f"- dry-run total: {fmt_bytes(total)} across {len(plans)} horizon group(s); cap {a.max_gib} GiB")
        if total > cap:
            finish("aborted", dry_run_bytes=total, units=len(units), detail={"reason": "dry_run_over_cap"})
            summary("- **aborted**: dry-run estimate over cap")
            log("ABORT: dry-run estimate exceeds the cap")
            return 2
        if a.dry_run_only:
            finish("ok", dry_run_bytes=total, units=len(units), rows_written=0, detail={"note": "dry run only"})
            return 0

        by_unit = {u["unit_id"]: u for u in units}
        results, billed, colmap = [], 0, {}
        for h, out_id, sql, _b in plans:
            ids = [u["unit_id"] for u in units if int(u["horizon"]) == h]
            try:
                _, bb, _ = run_query(client, sql, max_bytes_billed=max(cap - billed, 10 * 1024 ** 2))
                billed += bb
                cols = [f.name for f in client.get_table(out_id).schema]
                ssql, colmap = summarise_sql(out_id, cols)
                rows, bb2, _ = run_query(client, ssql, max_bytes_billed=max(cap - billed, 10 * 1024 ** 2))
                billed += bb2
                log(f"horizon {h}: {len(rows)} units back; columns used {colmap}")
            except Exception as e:  # one failing horizon group must not lose the others
                log(f"horizon {h} failed: {e}")
                for uid in ids:
                    results.append(row_for(by_unit[uid], model, conf, work["pre_days"], status=f"bq_error: {str(e)[:300]}"))
                continue
            seen = set()
            for r in rows:
                u = by_unit.get(r["unit_id"])
                if not u:
                    continue
                seen.add(r["unit_id"])
                results.append(effect_row(u, r, model, conf, work["pre_days"], colmap))
            for uid in ids:
                if uid not in seen:
                    results.append(row_for(by_unit[uid], model, conf, work["pre_days"], status="no_output"))

        written, rejected = 0, []
        for i in range(0, len(results), 200):
            res = sb.rpc("att_ce_ingest", {"p_run": {"run_id": run_id, "as_of": as_of}, "p_rows": results[i:i + 200]})
            written += int(res.get("rows") or 0)
            rejected += res.get("rejected") or []
        ok = sum(1 for r in results if r["status"] == "ok")
        sig = sum(1 for r in results if r["status"] == "ok" and (r["abs_lo"] > 0 or r["abs_hi"] < 0))
        log(f"billed {fmt_bytes(billed)}; results {len(results)} ok {ok} sig {sig}; written {written}; rejected {rejected[:10]}")
        summary(f"- billed: {fmt_bytes(billed)}\n- results: {len(results)} (ok {ok}, interval excludes 0: {sig}); "
                f"written {written}; rejected {len(rejected)}")
        finish("ok", dry_run_bytes=total, billed_bytes=billed, units=len(units), rows_written=written,
               detail={"ok": ok, "sig": sig, "rejected": rejected[:20], "columns": colmap, "horizons": horizons})
        return 0
    except Exception as e:
        finish("failed", detail={"error": str(e)[:1000]})
        raise


def row_for(u, model, conf, pre_days, status):
    return {"hop_id": u["hop_id"], "series_id": u["series_id"], "model_version": model, "horizon_days": int(u["horizon"]),
            "pre_days": int(pre_days), "n_pre": u.get("n_pre"), "n_post": u.get("n_post"), "confidence": conf,
            "status": status}


def effect_row(u, r, model, conf, pre_days, colmap):
    row = row_for(u, model, conf, pre_days, status="ok")
    st = (r.get("status") or "").strip()
    ae, re_, p = finite(r.get("absolute_effect")), finite(r.get("relative_effect")), finite(r.get("p_value"))
    L, U = finite(r.get("sum_lower")), finite(r.get("sum_upper"))
    A = finite(r.get("sum_actual"))
    if A is None:  # actual column not found in the output: use the series we uploaded
        h = int(u["horizon"])
        A = sum(finite(y) or 0.0 for t, y in zip(u["t"], u["y"]) if 0 <= t < h)
    row.update({"abs_effect": ae, "rel_effect": re_, "p_value": p,
                "detail": {"sum_actual": A, "sum_lower": L, "sum_upper": U, "n_post_bq": r.get("n_post"),
                           "exp_sign": u.get("exp_sign"), "role": u.get("role"), "columns": colmap}})
    if st:
        row["status"] = st[:500]
        return row
    if ae is None or L is None or U is None:
        row["status"] = "missing_output_columns"
        return row
    row["abs_lo"], row["abs_hi"] = A - U, A - L
    row["rel_lo"] = (A - U) / U if U > 0 else None
    row["rel_hi"] = (A - L) / L if L > 0 else None
    return row


if __name__ == "__main__":
    sys.exit(main())
