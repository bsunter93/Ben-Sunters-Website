#!/usr/bin/env python3
"""Extract the JSON text a Supabase MCP `select ...::text s` query returned (saved tool result) and write it to a file.
usage: mcp-result.py <saved-result.txt> <out.json>"""
import json, sys, re
raw = json.load(open(sys.argv[1]))['result']
m = re.search(r'<untrusted-data-[^>]+>\n(.*)\n</untrusted-data-', raw, re.S)
rows = json.loads(m.group(1))
obj = json.loads(rows[0]['s'])
json.dump(obj, open(sys.argv[2], 'w'), ensure_ascii=False, separators=(',', ':'))
print('wrote', sys.argv[2], len(json.dumps(obj)))
