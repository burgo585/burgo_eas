import os
import json
import glob
import re

brain_dir = r"C:\Users\Vini_Burgo\.gemini\antigravity\brain"
conv_dirs = [d for d in os.listdir(brain_dir) if os.path.isdir(os.path.join(brain_dir, d)) and d != "tempmediaStorage"]

conversations_info = []

for d in conv_dirs:
    c_path = os.path.join(brain_dir, d)
    t_path = os.path.join(c_path, ".system_generated", "logs", "transcript.jsonl")
    
    first_user_text = ""
    all_user_texts = []
    files_created_or_modified = set()
    date_str = ""
    
    if os.path.exists(t_path):
        with open(t_path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                try:
                    obj = json.loads(line)
                    t = obj.get("type")
                    if t == "USER_INPUT":
                        txt = obj.get("content", "")
                        if not first_user_text:
                            first_user_text = txt.strip()
                            date_str = obj.get("created_at", "")[:10]
                        all_user_texts.append(txt)
                    elif t == "PLANNER_RESPONSE":
                        tcalls = obj.get("tool_calls", [])
                        for tc in tcalls:
                            fn = tc.get("name", "")
                            args = tc.get("arguments", {})
                            if fn in ("write_to_file", "replace_file_content"):
                                target = args.get("TargetFile")
                                if target:
                                    files_created_or_modified.add(target)
                except Exception:
                    pass
                    
    artifacts = [f for f in os.listdir(c_path) if os.path.isfile(os.path.join(c_path, f))]
    scratch_dir = os.path.join(c_path, "scratch")
    scratch_files = []
    if os.path.exists(scratch_dir):
        for root, dirs, files in os.walk(scratch_dir):
            for file in files:
                scratch_files.append(os.path.relpath(os.path.join(root, file), c_path))
                
    conversations_info.append({
        "uuid": d,
        "date": date_str,
        "first_prompt": first_user_text[:140].replace("\n", " "),
        "files_modified": list(files_created_or_modified),
        "artifacts": artifacts,
        "scratch_files": scratch_files,
        "msg_count": len(all_user_texts)
    })

print(f"Total parsed: {len(conversations_info)}")
for c in sorted(conversations_info, key=lambda x: x["date"]):
    print(f"[{c['date']}] {c['uuid'][:8]} | Msgs: {c['msg_count']} | Artifacts: {len(c['artifacts'])} | Scratch: {len(c['scratch_files'])}")
    print(f"   Prompt: {c['first_prompt'][:100]}")
    if c['files_modified']:
        print(f"   Touched files: {c['files_modified'][:2]}")
