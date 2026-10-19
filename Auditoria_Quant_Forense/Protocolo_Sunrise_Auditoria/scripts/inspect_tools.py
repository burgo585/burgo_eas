import json
import os
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

brain_dir = r"C:\Users\Vini_Burgo\.gemini\antigravity\brain"
conv_dirs = [d for d in os.listdir(brain_dir) if os.path.isdir(os.path.join(brain_dir, d)) and d != "tempmediaStorage"]

tool_counts = {}

for d in conv_dirs:
    c_path = os.path.join(brain_dir, d)
    t_path = os.path.join(c_path, ".system_generated", "logs", "transcript.jsonl")
    if os.path.exists(t_path):
        with open(t_path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                try:
                    obj = json.loads(line)
                    if obj.get("type") == "PLANNER_RESPONSE":
                        for tc in obj.get("tool_calls", []):
                            name = tc.get("name")
                            tool_counts[name] = tool_counts.get(name, 0) + 1
                            if name in ("write_to_file", "replace_file_content"):
                                print(f"Found {name} in {d[:8]}: {tc.get('arguments', {}).get('TargetFile')}")
                except Exception:
                    pass

print("Tool call counts across all conversations:")
for k, v in sorted(tool_counts.items(), key=lambda x: x[1], reverse=True):
    print(f"  {k}: {v}")
