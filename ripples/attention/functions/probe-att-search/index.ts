// Retired probe (Ripples v5 attention probes, 2026-09-25). No outbound calls. Owner: delete this function.
Deno.serve(() => new Response(JSON.stringify({ ok: false, gone: true, note: "probe retired; see ripples/attention/README.md" }), { status: 410, headers: { "content-type": "application/json" } }));
