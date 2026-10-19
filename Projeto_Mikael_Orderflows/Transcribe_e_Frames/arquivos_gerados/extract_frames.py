import sys
import os
import av
import numpy as np
from PIL import Image

sys.stdout.reconfigure(encoding='utf-8')

video_path = r'C:\Users\Vini_Burgo\Videos\Captures\Aula do Mikael dia 16-10-2026.mp4'
output_dir = r'c:\Users\Vini_Burgo\OneDrive\Documents\Projeto Mikael 16102026\frames'
os.makedirs(output_dir, exist_ok=True)

print("Abrindo vídeo para extração visual de frames...")
container = av.open(video_path)
vstream = container.streams.video[0]

# Total duration in seconds
duration = float(container.duration) / av.time_base if container.duration else 3890.0
print(f"Duração total do vídeo: {duration/60:.2f} min ({duration:.1f}s)")

# We sample every 10 seconds, detect significant changes, and always save at least every 60 seconds
sample_step = 10.0 # seconds
min_save_interval = 40.0 # save at least every 40s
last_saved_time = -999.0
last_thumb = None

saved_count = 0
frame_log = []

for sec in np.arange(0, duration, sample_step):
    pts = int(sec / vstream.time_base)
    container.seek(pts, stream=vstream)
    
    frame = None
    for pkt in container.demux(vstream):
        for f in pkt.decode():
            frame = f
            break
        if frame is not None:
            break
            
    if frame is None:
        continue
        
    actual_sec = float(frame.pts * vstream.time_base) if frame.pts else sec
    img = frame.to_image() # PIL Image
    
    # Create thumbnail to check change
    thumb = img.resize((160, 90)).convert('L')
    thumb_arr = np.array(thumb, dtype=np.float32)
    
    is_change = False
    diff = 0.0
    if last_thumb is not None:
        diff = float(np.mean(np.abs(thumb_arr - last_thumb)))
        if diff > 12.0: # Significant visual change
            is_change = True
    else:
        is_change = True
        
    time_since_save = actual_sec - last_saved_time
    if is_change or time_since_save >= min_save_interval:
        m = int(actual_sec // 60)
        s = int(actual_sec % 60)
        fname = f"frame_{m:02d}m{s:02d}s.jpg"
        save_path = os.path.join(output_dir, fname)
        img.save(save_path, "JPEG", quality=85)
        
        last_saved_time = actual_sec
        last_thumb = thumb_arr
        saved_count += 1
        entry = {"sec": actual_sec, "time": f"{m:02d}:{s:02d}", "file": fname, "diff": diff}
        frame_log.append(entry)
        if saved_count % 10 == 0 or is_change:
            print(f"[{entry['time']}] Salvo {fname} (diff={diff:.1f}, total={saved_count})")

print(f"\nExtração concluída! Total de {saved_count} frames salvos em {output_dir}")

import json
with open(os.path.join(output_dir, "frames_index.json"), "w", encoding="utf-8") as f:
    json.dump(frame_log, f, indent=2)
