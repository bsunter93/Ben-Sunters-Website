// wsa.ts — small helpers shared by the v6 WS-A functions (att-econ, att-equities, att-wikidata, att-market-backfill,
// att-library). Canonical copy: functions/att-econ/wsa.ts; the other functions ship byte-identical copies next to
// index.ts (the Supabase MCP deploy uploads only listed files).
//
// Key hygiene (OWNER D-7 / D-10): keys are read ONLY at run time through public.att_secret(name) (service_role) via the
// shared att.ts attSecret (ATT_VERSION >= 2026-09-25.4), kept in memory for the run, and every string that leaves the
// function is scrubbed of the key values and of any `api_key=` / `apikey=` / `token=` / `registrationkey` / `key=` query
// parameters: att.ts Run.finish() calls run.scrub() itself; wrap() also scrubs (idempotent). One secret registry (att.ts)
// serves both, so a key read through either path is scrubbed everywhere. Keys never go into rows, meta, payloads or logs;
// no console.log of URLs anywhere.
import { attSecret, errMsg, politeFetch, type Run, scrubStr as attScrubStr } from "./att.ts";

export const WSA_VERSION = "2026-09-25.a2";

/** Read a Vault secret via public.att_secret (service_role). null when absent (collectors must then no-op cleanly). */
export async function secret(run: Run, name: string): Promise<string | null> {
  if (run.params?.simulate_missing_key === true) return null; // test hook: exercise the no-key path without touching Vault
  return await attSecret(run, name);
}

export const scrubStr = attScrubStr;
/** Remove key material from everything Run.finish() will persist or return (delegates to att.ts Run.scrub). */
export function scrub(run: Run) { run.scrub(); }
/** Wrap a mode handler: exceptions become run.errors, and the run is always scrubbed before finish(). */
export function wrap(f: (run: Run) => Promise<void>) {
  return async (run: Run) => {
    try { await f(run); } catch (e) { run.errors.push(errMsg(e)); } finally { scrub(run); }
  };
}

/** GET via politeFetch; returns parsed JSON for 2xx, else null (status recorded without the URL). */
export async function getJson(run: Run, source: string, url: string, headers: Record<string, string> = {}, timeoutMs = 60_000): Promise<any | null> {
  const res = await politeFetch(run, url, { source, headers: { accept: "application/json", ...headers }, timeoutMs });
  if (!res) return null;
  if (!res.ok) {
    const body = (await res.text().catch(() => "")).slice(0, 200);
    run.errors.push(`${source}: http ${res.status} ${scrubStr(body.replace(/\s+/g, " "))}`);
    return null;
  }
  const j = await res.json().catch(() => null);
  if (j === null) run.errors.push(`${source}: bad json`);
  return j;
}
export async function getText(run: Run, source: string, url: string, headers: Record<string, string> = {}, timeoutMs = 90_000): Promise<Response | null> {
  const res = await politeFetch(run, url, { source, headers, timeoutMs });
  if (!res) return null;
  if (!res.ok) { await res.body?.cancel(); run.errors.push(`${source}: http ${res.status}`); return null; }
  return res;
}

export const todayUtc = () => new Date().toISOString().slice(0, 10);
export const r4 = (x: number) => Math.round(x * 1e4) / 1e4;
export function median(a: number[]): number {
  if (!a.length) return NaN;
  const s = [...a].sort((x, y) => x - y);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}
export function mad(a: number[], m = median(a)): number { return median(a.map((x) => Math.abs(x - m))); }
