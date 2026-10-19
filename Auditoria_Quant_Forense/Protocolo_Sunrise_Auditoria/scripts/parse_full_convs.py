import os
import sys
import json

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

brain_dir = r"C:\Users\Vini_Burgo\.gemini\antigravity\brain"
conv_dirs = [d for d in os.listdir(brain_dir) if os.path.isdir(os.path.join(brain_dir, d)) and d != "tempmediaStorage"]

conversations = []

for d in conv_dirs:
    c_path = os.path.join(brain_dir, d)
    full_path = os.path.join(c_path, ".system_generated", "logs", "transcript_full.jsonl")
    compact_path = os.path.join(c_path, ".system_generated", "logs", "transcript.jsonl")
    
    t_path = full_path if os.path.exists(full_path) else compact_path
    
    first_user_text = ""
    all_user_prompts = []
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
                        all_user_prompts.append(txt.strip())
                    elif t == "PLANNER_RESPONSE":
                        for tc in obj.get("tool_calls", []):
                            fn = tc.get("name")
                            args = tc.get("args") or tc.get("arguments") or {}
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
                    
    artifacts = [os.path.join(c_path, f) for f in os.listdir(c_path) if os.path.isfile(os.path.join(c_path, f))]
    
    scratch_files = []
    scratch_dir = os.path.join(c_path, "scratch")
    if os.path.exists(scratch_dir):
        for root, dirs, files in os.walk(scratch_dir):
            for file in files:
                scratch_files.append(os.path.join(root, file))
                
    uploaded_files = []
    up_dir = os.path.join(c_path, ".user_uploaded")
    if os.path.exists(up_dir):
        for root, dirs, files in os.walk(up_dir):
            for file in files:
                uploaded_files.append(os.path.join(root, file))
                
    conversations.append({
        "uuid": d,
        "date": date_str,
        "first_prompt": first_user_text[:200].replace("\n", " "),
        "prompt_count": len(all_user_prompts),
        "files_written": list(files_written),
        "files_viewed": list(files_viewed),
        "cwds": list(cwds),
        "artifacts": artifacts,
        "scratch_files": scratch_files,
        "uploaded_files": uploaded_files
    })

conversations.sort(key=lambda x: x["date"])

with open(r"C:\Users\Vini_Burgo\.gemini\antigravity\brain\4148e527-451e-4431-8215-17e8fa4d8cd6\scratch\detailed_convs.json", "w", encoding="utf-8") as f:
    json.dump(conversations, f, indent=2, ensure_ascii=False)

print(f"Parsed {len(conversations)} conversations successfully.")
for c in conversations:
    print(f"\n--- [{c['date']}] {c['uuid']} (Prompts: {c['prompt_count']}) ---")
    print(f"Prompt: {c['first_prompt'][:120]}")
    if c['cwds']:
        print(f"CWDs: {c['cwds']}")
    if c['files_written']:
        print(f"Files written ({len(c['files_written'])}):")
        for fw in c['files_written'][:5]:
            print(f"   * {fw}")
    if c['artifacts']:
        print(f"Artifacts ({len(c['artifacts'])}): {[os.path.basename(a) for a in c['artifacts']]}")
    if c['scratch_files']:
        print(f"Scratch files ({len(c['scratch_files'])})")
    if c['uploaded_files']:
        print(f"Uploaded files ({len(c['uploaded_files'])})")
