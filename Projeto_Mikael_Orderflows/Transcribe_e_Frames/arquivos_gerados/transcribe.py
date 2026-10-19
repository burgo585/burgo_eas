import sys
import os
import av
import numpy as np
import time
import faster_whisper

sys.stdout.reconfigure(encoding='utf-8')

video_path = r'C:\Users\Vini_Burgo\Videos\Captures\Aula do Mikael dia 16-10-2026.mp4'
output_txt = r'c:\Users\Vini_Burgo\OneDrive\Documents\Projeto Mikael 16102026\transcricao_aula.txt'

print("Abrindo vídeo para extrair áudio...")
container = av.open(video_path)
stream = container.streams.audio[0]

# Seek para perto de 12:45 onde o áudio começa
start_sec = 12 * 60 + 45
container.seek(int(start_sec / stream.time_base), stream=stream)

resampler = av.AudioResampler(format='s16', layout='mono', rate=16000)

audio_frames = []
for frame in container.decode(stream):
    frame.pts = None
    res = resampler.resample(frame)
    if res:
        audio_frames.append(res[0].to_ndarray())

print(f"Decodificação de áudio concluída. Juntando {len(audio_frames)} buffers...")
audio_data = np.concatenate(audio_frames, axis=1).squeeze().astype(np.float32) / 32768.0
total_sec = len(audio_data) / 16000.0
print(f"Duração do áudio extraído: {total_sec/60:.2f} minutos.")

print("Carregando modelo Whisper small com VAD...")
model = faster_whisper.WhisperModel("small", device="cpu", compute_type="int8")

print("Iniciando transcrição com VAD (Voice Activity Detection)...")
t0 = time.time()
segments, info = model.transcribe(
    audio_data,
    language="pt",
    vad_filter=True,
    vad_parameters=dict(min_silence_duration_ms=500),
    beam_size=5
)

lines = []
with open(output_txt, "w", encoding="utf-8") as f:
    for s in segments:
        real_start = start_sec + s.start
        real_end = start_sec + s.end
        line = f"[{int(real_start//60):02d}:{real_start%60:05.2f} -> {int(real_end//60):02d}:{real_end%60:05.2f}] {s.text}"
        print(line)
        f.write(line + "\n")
        f.flush()

print(f"\nTranscrição concluída em {time.time() - t0:.1f}s e salva em: {output_txt}")
