// ripples-bot: builds (and, from v5.1, posts) yesterday's Knock-On reveal card for Bluesky (SPEC §5.5). Token-gated
// (x-collector-token).
// DEFERRED (OWNER_DECISIONS D-3): automated Bluesky posting is deferred to v5.1; the owner posts by hand for the
// first 14 days. POSTING_ENABLED is false, so a normal call (including the daily 07:35 cron job ripples-bot-daily)
// always returns {"skipped":true,"reason":"deferred_v5_1"} and posts nothing. {"dry_run": true} builds the post text,
// facets, alt text and checks the reveal PNG, so the owner can copy it for a manual post. Turning posting on in v5.1 =
// set POSTING_ENABLED = true, redeploy, and add the two vault secrets bsky_handle + bsky_app_password.
// Never targets a puzzle that is still current: ripples_bot_context() only returns a live, published puzzle dated
// the day before the current puzzle date, whose ripples_og_data(n).past is true AND that is older than the live
// puzzle ripples_latest() is serving (on a delayed day yesterday's puzzle stays playable, so it has no target).
// One post per n (ripples.bot_posts claim).
import { createClient } from "jsr:@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const db = createClient(SB_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
const ENTRYWAY = "https://bsky.social";
const LINK = "bensunter.com/ripples";
const MAX_GRAPHEMES = 300;
const POSTING_ENABLED = false; // D-3: deferred to v5.1 (see header)
// SPEC §12.1 wording lint (same patterns as ripples/contract/tools/validate.py CAUSAL_RE / FLOW_RE). AI social copy
// that trips either falls back to the template, which never uses them.
const CAUSAL_RE = /\b(caus(e|es|ed|ing)|dr(o|i)ve[ns]?|driving|flood(s|ed|ing)?\s+(in)?to|a flood of|sen(t|ds?|ding) (readers|traffic|people|visitors)|went from\b[^.;:!?]{1,80}?\bto)\b/i;
const FLOW_RE = /\b(readers?|clicked|clicks?|click(ed)? through|looked up|went on to|moved (on )?to|followed|navigat\w*)\b/i;

const seg = new Intl.Segmenter("en", { granularity: "grapheme" });
const graphemes = (s: string) => Array.from(seg.segment(s)).length;
function clipG(s: string, max: number): string {
  const g = Array.from(seg.segment(s)).map((x) => x.segment);
  return g.length <= max ? s : g.slice(0, max - 1).join("").trimEnd() + "…";
}
const clean = (s: unknown) => String(s ?? "").replace(/[\u0000-\u001f\u007f-\u009f]/g, " ").replace(/\s+/g, " ").trim();

type Og = {
  n: number; date: string; R: number;
  seed: { title: string; emoji: string };
  rounds: { i: number; continues: boolean; seed_emoji: string | null; emoji: string; title: string; multiple: number }[];
};

function templateText(og: Og): string {
  const head = `Yesterday's Knock-On #${og.n}: `;
  const tail = ` Measured attention, not proof of cause. Play today: ${LINK}`;
  const parts: string[] = [clean(og.seed.title)];
  for (const r of og.rounds) parts.push((r.continues ? " → " : " · … → ") + clean(r.title));
  let chain = parts.join("");
  const budget = MAX_GRAPHEMES - graphemes(head) - graphemes(tail) - 1;
  if (graphemes(chain) > budget) chain = clipG(chain, budget);
  return `${head}${chain}${chain.endsWith("…") ? "" : "."}${tail}`;
}
function socialText(s: string): string {
  const tail = `\n${LINK}`;
  return clipG(clean(s), MAX_GRAPHEMES - graphemes(tail)) + tail;
}
// link facet for the bensunter.com/ripples substring (byte offsets in UTF-8)
function facets(text: string) {
  const i = text.lastIndexOf(LINK);
  if (i < 0) return [];
  const enc = new TextEncoder();
  const start = enc.encode(text.slice(0, i)).length;
  return [{
    index: { byteStart: start, byteEnd: start + enc.encode(LINK).length },
    features: [{ $type: "app.bsky.richtext.facet#link", uri: `https://${LINK}/` }],
  }];
}

async function xrpc(base: string, method: string, init: RequestInit): Promise<Response> {
  return await fetch(`${base}/xrpc/${method}`, init);
}

Deno.serve(async (req: Request) => {
  const token = req.headers.get("x-collector-token") ?? "";
  const { data: authed } = await db.rpc("check_collector_token", { t: token });
  if (authed !== true) return new Response("forbidden", { status: 403 });
  // deno-lint-ignore no-explicit-any
  const body: any = await req.json().catch(() => ({}));
  const dry = body?.dry_run === true;

  const { data: ctx, error } = await db.rpc("ripples_bot_context");
  if (error) return Response.json({ ok: false, error: error.message }, { status: 500 });
  if (!dry && !POSTING_ENABLED) {
    console.log("ripples-bot skipped: automated posting deferred to v5.1 (OWNER_DECISIONS D-3); use dry_run");
    return Response.json({ skipped: true, reason: "deferred_v5_1", has_secrets: ctx.has_secrets === true });
  }
  if (!ctx.has_secrets && !dry) {
    console.log("ripples-bot skipped: no vault secrets bsky_handle / bsky_app_password");
    return Response.json({ skipped: true, reason: "no_secrets" });
  }
  if (ctx.target_n === null || !ctx.og) {
    console.log("ripples-bot skipped: no passed puzzle for yesterday");
    return Response.json({ skipped: true, reason: "no_target", current_n: ctx.current_n });
  }
  if (ctx.post_status === "posted") return Response.json({ skipped: true, reason: "already_posted", n: ctx.target_n });

  const og = ctx.og as Og;
  let text = templateText(og), textSource = "template";
  const soc = ctx.social?.text ? clean(ctx.social.text) : "";
  if (soc && !CAUSAL_RE.test(soc) && !FLOW_RE.test(soc) && !/https?:|www\./i.test(soc)) {
    text = socialText(soc); textSource = ctx.social.source;
  }
  const alt = clipG(`Knock-On #${og.n} answer card: ${clean(og.seed.title)}` +
    og.rounds.map((r) => (r.continues ? " → " : " · ") + clean(r.title)).join("") +
    ". Measured attention, not proof of cause.", 900);

  const imgRes = await fetch(`${SB_URL}/functions/v1/ripples-og?n=${og.n}&v=reveal`);
  const imgOk = imgRes.ok && imgRes.headers.get("content-type") === "image/png" && imgRes.headers.get("x-card-variant") === "reveal";
  const png = imgOk ? new Uint8Array(await imgRes.arrayBuffer()) : null;
  if (!imgOk) await imgRes.body?.cancel();
  if (dry) {
    return Response.json({ dry_run: true, n: og.n, text, text_source: textSource, graphemes: graphemes(text), facets: facets(text), alt, image_bytes: png?.length ?? 0, has_secrets: ctx.has_secrets });
  }
  if (!png) return Response.json({ ok: false, error: "reveal card unavailable", n: og.n }, { status: 502 });

  const { data: claimed } = await db.rpc("ripples_bot_log", { p_n: og.n, p_action: "claim" });
  if (claimed !== true) return Response.json({ skipped: true, reason: "claimed_elsewhere", n: og.n });
  try {
    const s = await xrpc(ENTRYWAY, "com.atproto.server.createSession", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ identifier: ctx.handle, password: ctx.app_password }),
    });
    if (!s.ok) throw new Error(`createSession ${s.status}`);
    const sess = await s.json();
    // deno-lint-ignore no-explicit-any
    const pds: string = sess.didDoc?.service?.find((x: any) => x.id === "#atproto_pds")?.serviceEndpoint ?? ENTRYWAY;
    const auth = { Authorization: `Bearer ${sess.accessJwt}` };
    const up = await xrpc(pds, "com.atproto.repo.uploadBlob", { method: "POST", headers: { ...auth, "Content-Type": "image/png" }, body: png });
    if (!up.ok) throw new Error(`uploadBlob ${up.status}`);
    const blob = (await up.json()).blob;
    const record = {
      $type: "app.bsky.feed.post", text, facets: facets(text), createdAt: new Date().toISOString(), langs: ["en"],
      embed: { $type: "app.bsky.embed.images", images: [{ alt, image: blob, aspectRatio: { width: 1200, height: 630 } }] },
    };
    const cr = await xrpc(pds, "com.atproto.repo.createRecord", {
      method: "POST", headers: { ...auth, "Content-Type": "application/json" },
      body: JSON.stringify({ repo: sess.did, collection: "app.bsky.feed.post", record }),
    });
    if (!cr.ok) throw new Error(`createRecord ${cr.status}`);
    const out = await cr.json();
    await db.rpc("ripples_bot_log", { p_n: og.n, p_action: "posted", p_uri: out.uri ?? null });
    return Response.json({ ok: true, n: og.n, uri: out.uri ?? null, text_source: textSource });
  } catch (e) {
    const msg = String(e instanceof Error ? e.message : e).slice(0, 300);
    await db.rpc("ripples_bot_log", { p_n: og.n, p_action: "failed", p_err: msg });
    return Response.json({ ok: false, n: og.n, error: msg }, { status: 502 });
  }
});
