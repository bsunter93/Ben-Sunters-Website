// Retired probe (Knock-On v5 W4). Deployed over probe-og, probe-og2 and probe-sources so they no longer render
// arbitrary text on bensunter.com-branded cards or call external sources. The owner deletes them in the dashboard.
Deno.serve(() =>
  new Response("gone", {
    status: 410,
    headers: { "Content-Type": "text/plain", "Cache-Control": "public, max-age=86400", "Access-Control-Allow-Origin": "*" },
  })
);
