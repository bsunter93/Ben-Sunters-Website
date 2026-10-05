# Data day v1 (Oct 5, 2026)

A registered test that stops on a refusal waits for a later day. Until now someone had to come back and run it by hand.
The data day runs those tests on later days by itself, inside the project's rules, and remembers what it already
fetched. A test finishes once and never runs again.

Code: `ripples/lab/polite.py` (the network rules) and `ripples/lab/dataday.py` (the runner). Registry:
`ripples/lab/dataday_jobs.json`. Ledger: `ripples/docs/results/host_stops.json`. Workflow:
`.github/workflows/ripples-dataday.yml`. Results: `ripples/docs/results/dataday/`.

## How it works

1. **Once a day at 04:53 UTC** the workflow starts on `main` (night in the US, early morning in the UK, clear of the
   other daily jobs). It runs the two offline self-tests, then `dataday.py run`.
2. **The runner decides each job in registry order.** A job runs only if all of these hold:
   - its done marker is absent;
   - its gate, if it has one, is cleared;
   - no hold from an earlier attempt applies to its current revision;
   - none of its hosts is parked or has a stop dated today (UTC), by the ledger or by a stop-marker file the job names;
   - it has not been attempted today.
3. **The frozen code is taken from the registered commit** with `git archive` (only the paths the job lists) and
   checked against the sha256 in the registry. A mismatch holds the job. The code runs unchanged.
4. **It runs under `polite.py exec`,** which installs a hook on urllib before the script starts. The script keeps its own
   rules: its pause, its stop conditions, its outputs. The polite layer adds its own rules on top (next section).
5. **The runner reads the outcome.**
   - **Done:** the job's done condition holds. Its outputs are copied to `results/dataday/<job>/` and its done marker
     is written, with the plan, code commit, arguments and request count.
   - **Stopped:** a host refused. The ledger already has the stop, and the job waits for the next UTC day.
   - **Paused:** the budget or the time limit ended the attempt. The next data day resumes it.
   - **Held:** robots.txt, a 4xx under the plan's own rule, or a crash ended the attempt. Waiting would repeat the same
     answer, so the job waits for a person to raise its revision.
6. **The workflow commits back** the ledger (merged, never overwritten), `status.json`, logs and results, with
   `[skip ci]`.

**Only one place sends requests.** That is the scheduled run on `main`, or a manual run on `main` with `mode=run`. A push
to the workflow file on any other branch is a dry run: it decides every job, reports, and sends nothing. One ledger and
one status file therefore decide every real request. The Sep 28 Wikimedia breach (ledger 1300) came from a second run
queued by a push. A push-started data day cannot repeat it.

## The rules it enforces

| Rule | Where |
|---|---|
| The honest user agent `ripples-research/0.2 (+https://bensunter.com/ripples/methods/)` and no other. A request carrying a different agent is not sent | `polite.Policy.open` |
| At most one request a second per host. A job can set a host slower, never faster. A robots.txt Crawl-delay slows it further | `polite.Policy.send` |
| robots.txt is read once per host per run. A disallowed path is not requested unless the registry names an exception for that host and path, with the policy that allows it | `polite.Policy.check_robots` |
| A request budget per job and per run (1,500). When it is spent the job ends, and the next data day resumes it | `polite.Policy.send` |
| The ledger is read before every request. A 401, 403, 429, 5xx, timeout or connection error is written to it at once, and that host gets no request until the next UTC day. A plan whose own rule is stricter (the ladder: any 4xx) gets its rule | `polite.Policy.after`, `host_state` |
| A host with stops on three UTC days in a row is parked. It gets no request until an entry in the ledger's `clears` names it with a later date. A clear never lifts a same-day stop | `polite.parked` |
| A stop the script decides for itself (an access-request page, an API error inside a 200) goes into the ledger too | `script_stop` in the registry |
| Only declared hosts. A connection opened outside the layer ends the job | `polite.install` |
| An on-disk cache keyed by URL, so a stopped job resumes without asking again for what it has. It is committed only when it is under 256 KB and the plan allows it; otherwise it lives in the Actions cache | `polite` cache, `dataday.run_job` |
| A job runs once per UTC day and finishes once | `status.json`, done markers |
| Frozen code, checked by sha256, run unchanged | `dataday.materialize` |
| No secrets. The workflow uses none, and the job's environment drops any variable named like a key. Key-like query values are redacted in logs and the ledger | `dataday.run_job`, `polite.redact` |

When the polite layer refuses a request, it raises `PoliteHalt`, a BaseException. A script's own `except Exception`
cannot swallow it and carry on: the job ends, and the data day records why. A real refusal reaches the script as
itself, so the script's own stop rule still runs.

## The five jobs

All five stops happened on Oct 5, 2026 (UTC); the plans' tables give the local times of Oct 4. The ledger records each
stop with its source.

| Job | Branch | Stop | Status on Oct 5 | What finishes it |
|---|---|---|---|---|
| `surprise-u4`: the registered surprise score, with u4 (co-citation) | eng-surprise | en.wikipedia.org, 429, search API, during the linksto counts | **Waiting** for the next UTC day | Nothing more from a person. Runs the registration commit's scorer (2c86cd2), the plan as written, not the u4-dropped deviation. It needs about 800 requests from an empty cache, with en.wikipedia.org paced at one every 2 s, slower than the rate the 429 came at. Its own cache persists, so a second 429 costs one day, not the work. Result: `surprise_v1_registered.json` |
| `records2-lac-megantic`: the Lac-Mégantic rescan, seven final-rule texts with the GPO-code fix | eng-records | www.federalregister.gov, 429 at 06:44 UTC, the rescan's first request | **Waiting** for the next UTC day | Nothing more from a person, unless the host's robots.txt disallows the full-text path. That file could not be read today, and a disallow holds the job for the owner. The rescan saves nothing until it ends, so the polite cache keeps each text: after a stop, it asks only for what it lacks. Result: the Lac-Mégantic block of the raw file. The hand read and the build stay with the test owner |
| `ladder-finding-nemo`: UN Comtrade, US imports of HS 030110 | eng-ladder | comtradeapi.un.org, 400 at about 06:22 UTC | **Held** | A 400 answers the request, so the same six-year request would get it again on any day. The plan says the next attempt makes one request per year without the extended filters, after an addendum (Addendum 1, item 9). Then set the code commit, set `cleared` to true and raise the revision |
| `ladder-bpii-ucas`: Blue Planet II and marine biology applications (section 6.1) | eng-ladder | www.ucas.com, 404 at 06:06 UTC, a guessed page address | **Held** | `ladder.py` has no UCAS fetch, so there is no frozen code to run. The plan's own condition comes first: an addendum naming the exact table and the pool size, then the code |
| `ladder-bpii-hansard`: Blue Planet II and the plastics turn (section 6.2) | eng-ladder | hansard-api.parliament.uk, 500 at 06:07 UTC, a coverage probe | **Held** | `ladder.py` has no Hansard fetch. Once an addendum confirms the endpoint and the code exists, a 500 is the kind of stop a later day clears, and the job resumes on its own |

Two of the five resume with no one touching them. The other three cannot finish by waiting. Two of those were stopped by
an answer to a malformed or guessed request, and their plan already requires an addendum before the next request. The
data day does not write addenda or change a registered request. It holds those jobs, says what each one needs, and runs
them the first day after the gate is cleared.

## The first check

The workflow ran once, as a dry run, on the eng-dataday branch: run 37277406461, Oct 5, 2026, 07:22 to 07:23 UTC,
success. All 20 polite self-tests and all 8 runner self-tests passed. The checks covered pacing, the agent, the cache,
robots.txt and its exception, budgets, the ledger's same-day rule, parking and clears, redaction, an unswallowable halt,
a job that stops, waits, resumes from the cache and finishes, and a finished job that never runs again. The decisions
matched the table above: two waiting, three held. No request went to any outside host. The run committed `status.json`
back with `[skip ci]`.

The first push of the workflow started no run, because its commit message quoted the skip token in the body; GitHub
skips on the token anywhere in the message. A one-line comment push started the single run.

Before that, the frozen code of the three jobs that have code was started locally under the polite layer with no host
allowed. Each one loaded its inputs, reached its first request, and was halted with zero requests sent. This shows the
archive paths, arguments and hook work with the real scripts.

**Nothing runs on a schedule until this branch is merged.** GitHub starts scheduled workflows only on the default
branch. The first real data day is the first 04:53 UTC run after the merge.

## Operating it

- **Add a job:** append an entry with `plan`, `code` (commit, path, sha256), `tree`, `args`, `hosts` (with
  `min_interval_s` where a host should go slower), `budget`, `stop_rule` (`project` or `any_4xx`), `done_when`,
  `outputs` and `done_marker`. Use `{tree}`, `{out}` and `{cache}` in arguments. `python3 ripples/lab/dataday.py run
  --dry-run` shows the decision without sending anything.
- **Clear a gate:** commit the addendum and the code first. Then fill in the entry, set `gate.cleared` to true and raise
  `revision`.
- **Clear a park:** add `{"host": ..., "date": ..., "by": ..., "note": ...}` to `clears` in the ledger, after reading
  why the host kept refusing.
- **Read the state:** `python3 ripples/lab/dataday.py status`, or `ripples/docs/results/dataday/status.json`. Each job's
  log is under `results/dataday/<job>/logs/`, the last 400 lines of each attempt. The console prints 30, well under
  the job-log API's 5,000.

## Limits and judgment calls

- **The Wikimedia robots.txt exception is an owner decision.** Wikipedia's robots.txt (archived copy of Oct 3, 2026) has
  `User-agent: *` with `Disallow: /w/`, which covers the Action API at `/w/api.php`. Its comment asks crawlers to stay
  off dynamically generated pages. Wikimedia publishes the API for programs under its API etiquette and User-Agent
  policy, and every Wikipedia measurement in this project has used it. The registry names an exception for `/w/api.php`
  on en.wikipedia.org and www.wikidata.org. Delete those two entries and `surprise-u4` is held by robots.txt instead.
- **The Federal Register's robots.txt is unknown.** The archived copy answered 429 to a lookup while this was built. That
  stop is in the ledger (web.archive.org, Oct 5), and the lookup was not retried. The first real run reads the live file.
- **The ledger covers data-day jobs only.** Other workflows (the Level-4 panel, for one) keep their own stop markers
  until they adopt `polite.py`. A 429 from one host does not stop the same organization's other hosts.
- **Hand-recorded stop times are approximate.** The surprise stop's time was not recorded, so the ledger has its date
  only.
- **The Actions cache is evicted after seven days unused.** A job paused longer than that starts its fetch again. A
  finished job's cache is deleted.
- **Python's robots parser** applies the first matching rule rather than the most specific one, and reads only whole
  seconds in Crawl-delay.
- **Edits to `ripples/lab/polite.py`, `dataday.py` or `dataday_jobs.json` match the Ripples lab workflow's paths** and
  start it unless the commit carries the skip token. Adding them to that workflow's exclusions would stop this.
- **Not registered here:** the four Federal Register paragraphs of records 2, deviation 4. They were stopped by the same
  429, but their keys are the test owner's to name.
