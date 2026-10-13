"""读取 App 导出 / Supabase 下载的录音与标注，统一为 16kHz 单声道 wav 并生成 labels.csv。"""
import argparse
import librosa
import soundfile as sf
from pathlib import Path

SR = 16000

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    for f in Path(a.input).rglob("*.wav"):
        y, _ = librosa.load(f, sr=SR, mono=True)
        y, _ = librosa.effects.trim(y, top_db=30)
        sf.write(out / f.name, y, SR)
    # TODO: 合并 events.json 生成 labels.csv（event_id, path, label, context...）

if __name__ == "__main__":
    main()
