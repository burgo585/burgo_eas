import json
import os

brain_dir = r"C:\Users\Vini_Burgo\.gemini\antigravity\brain"
conv = "f4d907a0-8b6a-47d6-8520-58699a9fbf6a"
t_path = os.path.join(brain_dir, conv, ".system_generated", "logs", "transcript_full.jsonl")

if os.path.exists(t_path):
    with open(t_path, "r", encoding="utf-8") as f:
        for line in f:
            obj = json.loads(line)
            if obj.get("type") == "PLANNER_RESPONSE":
                for tc in obj.get("tool_calls", []):
                    if tc.get("name") in ("write_to_file", "replace_file_content"):
                        print("Full Tool:", tc.get("name"), "Args:", tc.get("arguments", {}).get("TargetFile"))
                        break
