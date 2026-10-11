"""Fill the rating page with rate/human/items.json; writes rate/human/page.html to publish.

    python3 ripples/engine/rate/human/build_page.py

The page stores each answer in its own database (ratings/<item id>: s, knew, b, t, why_shown), readable only by its
owner. Publish it with the capability {"db": {"rules": [{"path": "", "read": "owner", "write": "owner"}]}}, and export
the ratings collection to a folder of JSON files for score.py.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(HERE)))
import workdir  # noqa: E402

work = workdir.resolve(None if len(sys.argv) < 3 or sys.argv[1] != "--work" else sys.argv[2])
items = json.load(open(os.path.join(work, "rate", "human", "items.json")))
page = open(os.path.join(HERE, "page_template.html")).read().replace("/*ITEMS*/[]", json.dumps(items, ensure_ascii=False))
open(os.path.join(work, "rate", "human", "page.html"), "w").write(page)
print(len(items), "items -> rate/human/page.html")
