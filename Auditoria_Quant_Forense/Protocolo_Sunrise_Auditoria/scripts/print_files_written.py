import json
import os
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

with open(r"C:\Users\Vini_Burgo\.gemini\antigravity\brain\4148e527-451e-4431-8215-17e8fa4d8cd6\scratch\conv_summary.json", "r", encoding="utf-8") as f:
    data = json.load(f)

for c in data:
    if c.get("files_written"):
        print(f"[{c['date']}] UUID: {c['uuid'][:8]} (Total written: {len(c['files_written'])})")
        for fw in c["files_written"]:
            print(f"   -> {fw}")
