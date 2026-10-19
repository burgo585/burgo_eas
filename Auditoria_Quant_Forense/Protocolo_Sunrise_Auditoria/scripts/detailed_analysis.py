import os
import sys
import json
import re

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

brain_dir = r"C:\Users\Vini_Burgo\.gemini\antigravity\brain"
conv_dirs = [d for d in os.listdir(brain_dir) if os.path.isdir(os.path.join(brain_dir, d)) and d != "tempmediaStorage"]

results = []

for d in conv_dirs:
    c_path = os.path.join(brain_dir, d)
    t_path = os.path.join(c_path, ".system_generated", "logs", "transcript.jsonl")
    
    first_user_text = ""
    user_prompts = []
    files_written = set()
    files_viewed = set()
    cwds = set()
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
                        user_prompts.append(txt.strip()[:100])
                    elif t == "PLANNER_RESPONSE":
                        tcalls = obj.get("tool_calls", [])
                        for tc in tcalls:
                            fn = tc.get("name", "")
                            args = tc.get("arguments", {})
                            if fn in ("write_to_file", "replace_file_content"):
                                target = args.get("TargetFile")
                                if target:
                                    files_written.add(target)
                            elif fn in ("view_file",):
                                ab = args.get("AbsolutePath")
                                if ab:
                                    files_viewed.add(ab)
                            elif fn in ("run_command",):
                                cwd = args.get("Cwd")
                                if cwd:
                                    cwds.add(cwd)
                except Exception:
                    pass
                    
    # Find artifacts and scratch
    artifacts = [os.path.join(c_path, f) for f in os.listdir(c_path) if os.path.isfile(os.path.join(c_path, f))]
    scratch_files = []
    scratch_dir = os.path.join(c_path, "scratch")
    if os.path.exists(scratch_dir):
        for root, dirs, files in os.walk(scratch_dir):
            for file in files:
                scratch_files.append(os.path.join(root, file))
                
    user_uploaded_files = []
    up_dir = os.path.join(c_path, ".user_uploaded")
    if os.path.exists(up_dir):
        for root, dirs, files in os.walk(up_dir):
            for file in files:
                user_uploaded_files.append(os.path.join(root, file))
                
    results.append({
        "uuid": d,
        "date": date_str,
        "first_prompt": first_user_text[:120].replace("\n", " "),
        "all_prompts": user_prompts,
        "files_written": list(files_written),
        "files_viewed": list(files_viewed),
        "cwds": list(cwds),
        "artifacts": artifacts,
        "scratch_files": scratch_files,
        "user_uploaded": user_uploaded_files
    })

results.sort(key=lambda x: x["date"])

with open(r"C:\Users\Vini_Burgo\.gemini\antigravity\brain\4148e527-451e-4431-8215-17e8fa4d8cd6\scratch\conv_summary.json", "w", encoding="utf-8") as out_f:
    json.dump(results, out_f, indent=2, ensure_ascii=False)

print(f"Total analyzed: {len(results)}")
for r in results:
    print(f"=== [{r['date']}] UUID: {r['uuid']} ===")
    print(f"Prompt: {r['first_prompt']}")
    if r['cwds']:
        print(f"  CWDs: {r['cwds']}")
    if r['files_written']:
        print(f"  Files written: {len(r['files_written'])} files (e.g. {r['files_written'][:2]})")
    if r['artifacts']:
        print(f"  Artifacts in brain: {[os.path.basename(a) for a in r['artifacts']]}")
    if r['scratch_files']:
        print(f"  Scratch files: {len(r['scratch_files'])}")
    if r['user_uploaded']:
        print(f"  Uploaded: {len(r['user_uploaded'])}")
