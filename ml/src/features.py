"""提取 YAMNet embedding（帧均值，1024 维）并拼接上下文特征。"""
import numpy as np
import tensorflow_hub as hub

_yamnet = None

def yamnet_embedding(wav: np.ndarray) -> np.ndarray:
    global _yamnet
    if _yamnet is None:
        _yamnet = hub.load("https://tfhub.dev/google/yamnet/1")
    _, emb, _ = _yamnet(wav.astype(np.float32))
    return emb.numpy().mean(axis=0)

CONTEXT_KEYS = ["since_feed_min", "since_wake_min", "since_diaper_min", "since_burp_min", "baby_age_months"]

def context_vector(ctx: dict) -> np.ndarray:
    v = [min((ctx.get(k) or 0) / 300.0, 3.0) for k in CONTEXT_KEYS]
    h = ctx.get("hour", 0)
    v += [np.sin(2 * np.pi * h / 24), np.cos(2 * np.pi * h / 24)]
    return np.array(v, dtype=np.float32)

# TODO: main()：遍历 labels.csv，保存 X_audio, X_ctx, y 到 npz
