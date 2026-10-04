import json, sys
d = json.load(open("wider.json"))
print("stones", len(d), "| forward sentences", sum(len(o["forward"]) for o in d), "| reverse pairs", sum(len(o["reverse"]) for o in d))
n = 0
print("\n== REVERSE PAIRS (mark article names the stone; dated at or after)")
for o in d:
    for r in o["reverse"]:
        n += 1; print(f"R{n:02d}. {o['stone'][:24]:24s} ({o['year']}) -> {r['mark'][:52]} ({r['mark_year']}, {r['how']})\n      {r['text'][:220]}")
m = 0
print("\n== FORWARD SENTENCES (enacted-thing filter, year at or after the stone)")
for o in d:
    for f in o["forward"]:
        m += 1; print(f"F{m:03d}. [{o['stone'][:22]} {o['year']} | {f['section'][:18]} | {','.join(f['years'][:3])}] {f['text'][:210]}")
