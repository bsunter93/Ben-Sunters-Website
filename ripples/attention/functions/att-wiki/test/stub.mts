// in-memory stand-in for the Supabase RPCs used by att.ts + att-wiki
export const state: Record<string, any> = {};
export const calls: any[] = [];
export const budgets: Record<string, number> = {};   // remaining units per bucket
export const taken: Record<string, number> = {};     // total granted
export const refunded: Record<string, number> = {};
export const sources: Record<string, any> = {};
export const config: Record<string, any> = { run_caps: { wikimedia: 500, wikidata: 150 }, wm_quiet_utc: null, contact_gate: { enabled: false } };
export const rpcData: Record<string, (args: any) => any> = {};
export const ingested: any[] = []; export const cands: any[] = []; export const edges: any[] = []; export const jobsDone: any[] = [];
export function createClient() {
  return {
    rpc: async (name: string, args: any) => {
      calls.push([name, args]);
      if (rpcData[name]) return { data: rpcData[name](args), error: null };
      switch (name) {
        case "check_collector_token": return { data: true, error: null };
        case "att_state_get": return { data: state[args.p_k] ?? null, error: null };
        case "att_state_set": state[args.p_k] = JSON.parse(JSON.stringify(args.p_v)); return { data: null, error: null };
        case "att_config_get": return { data: config[args.p_key] ?? null, error: null };
        case "att_source_get": return { data: sources[args.p_source] ?? null, error: null };
        case "att_take_budget": { const left = budgets[args.p_bucket] ?? 0; const g = Math.max(0, Math.min(args.p_n, left)); budgets[args.p_bucket] = left - g; taken[args.p_bucket] = (taken[args.p_bucket] ?? 0) + g; return { data: g, error: null }; }
        case "att_budget_refund": budgets[args.p_bucket] = (budgets[args.p_bucket] ?? 0) + args.p_n; refunded[args.p_bucket] = (refunded[args.p_bucket] ?? 0) + args.p_n; return { data: args.p_n, error: null };
        case "att_host_kill": state["kill:" + args.p_host] = { status: args.p_status, until: [401,403].includes(args.p_status) || args.p_reason ? null : new Date(Date.now()+3600e3).toISOString(), permanent: [401,403].includes(args.p_status) || !!args.p_reason }; return { data: {}, error: null };
        case "att_host_lease_take": return { data: true, error: null };
        case "att_host_lease_release": return { data: 1, error: null };
        case "att_run_start": return { data: 1, error: null };
        case "att_ingest": ingested.push(...args.p_rows); return { data: { rows: args.p_rows.length, series_new: 0, rejected: [] }, error: null };
        case "att_ingest_candidates": cands.push(...args.p_rows); return { data: { rows: args.p_rows.length, rejected: 0 }, error: null };
        case "att_ingest_edges": edges.push(...args.p_rows); return { data: { rows: args.p_rows.length, rejected: 0 }, error: null };
        case "att_filter_titles": return { data: args.p_titles.filter((t: string) => !/^(Main_Page|Special:|List_of_)/.test(t)), error: null };
        case "att_jobs_done": jobsDone.push(args); return { data: args.p_jobs.length, error: null };
        default: return { data: null, error: null };
      }
    },
  };
}
