"""特征提取：和 App 端（lib/services/audio/cry_embedder.dart）逐步一致。

音频 → 16kHz 单声道 float(-1..1) → 63 阶 FIR 低通 3.8kHz（公开数据集是 8kHz 录音，
端上统一限带，减少训练/推理的频带差异）→ 每 15600 采样一帧、步长 7800 →
yamnet_embed.tflite（与 App 内置的是同一个文件）→ 每帧 1024 维 embedding + 哭声得分
→ 只对哭声得分 >= 0.2 的帧取均值（没有则全部帧）。

上下文特征（FEATURE_SPEC['context']）：公开数据集没有护理记录，v1 模型不用；
有了 App 上传的带上下文样本后，train.py --context 会把它们拼到 embedding 后面。
"""
from __future__ import annotations

import math
import os

import numpy as np

SR = 16000
FRAME = 15600
HOP = 7800
FIR_TAPS = 63
FIR_CUTOFF_HZ = 3800.0
CRY_IDX = (19, 20)
CRY_FRAME_MIN = 0.2
HERE = os.path.dirname(os.path.abspath(__file__))
EMBED_MODEL = os.path.join(HERE, '..', '..', 'app', 'assets', 'models', 'yamnet_embed.tflite')

# 上下文特征：名字、取值方式和归一化，App 端按这个顺序拼向量
CONTEXT_FEATURES = [
    # name, source key in CryContext.toJson(), transform
    ('since_feed_h', 'since_feed_min', 'hours_cap12'),
    ('since_wake_h', 'since_wake_min', 'hours_cap12'),
    ('since_diaper_h', 'since_diaper_min', 'hours_cap12'),
    ('since_burp_h', 'since_burp_min', 'hours_cap12'),
    ('is_sleeping', 'is_sleeping', 'bool'),
    ('hour_sin', 'hour', 'hour_sin'),
    ('hour_cos', 'hour', 'hour_cos'),
    ('age_months', 'baby_age_months', 'cap24'),
]


def fir_lowpass(taps: int = FIR_TAPS, cutoff: float = FIR_CUTOFF_HZ, sr: int = SR) -> np.ndarray:
    """Hamming 窗 sinc 低通，系数之和为 1。Dart 端同公式。"""
    fc = cutoff / sr
    m = taps - 1
    h = np.zeros(taps, dtype=np.float64)
    for n in range(taps):
        k = n - m / 2
        s = 2 * fc if k == 0 else math.sin(2 * math.pi * fc * k) / (math.pi * k)
        w = 0.54 - 0.46 * math.cos(2 * math.pi * n / m)
        h[n] = s * w
    return (h / h.sum()).astype(np.float32)


def lowpass(x: np.ndarray) -> np.ndarray:
    return np.convolve(x, fir_lowpass(), mode='same').astype(np.float32)


def frames(x: np.ndarray) -> list[np.ndarray]:
    if len(x) < FRAME:
        y = np.zeros(FRAME, np.float32)
        y[: len(x)] = x
        return [y]
    return [x[i : i + FRAME] for i in range(0, len(x) - FRAME + 1, HOP)]


def load_audio(path: str) -> np.ndarray:
    import librosa  # 只在训练机需要

    y, _ = librosa.load(path, sr=SR, mono=True)
    return y.astype(np.float32)


class Embedder:
    def __init__(self, model_path: str = EMBED_MODEL):
        try:
            from ai_edge_litert.interpreter import Interpreter
        except ImportError:
            import tensorflow as tf
            Interpreter = tf.lite.Interpreter
        self.it = Interpreter(model_path=model_path)
        self.it.allocate_tensors()
        self.inp = self.it.get_input_details()[0]['index']
        outs = self.it.get_output_details()
        self.emb_idx = next(o['index'] for o in outs if o['shape'][-1] == 1024)
        self.score_idx = next(o['index'] for o in outs if o['shape'][-1] == 521)

    def frame(self, f: np.ndarray) -> tuple[np.ndarray, float]:
        self.it.set_tensor(self.inp, f.astype(np.float32))
        self.it.invoke()
        e = self.it.get_tensor(self.emb_idx)[0].copy()
        s = self.it.get_tensor(self.score_idx)[0]
        return e, float(max(s[CRY_IDX[0]], s[CRY_IDX[1]]))

    def clip(self, x: np.ndarray) -> tuple[np.ndarray, float, int]:
        """返回 (pooled embedding, 平均哭声得分, 帧数)"""
        x = lowpass(x)
        es, ss = zip(*(self.frame(f) for f in frames(x)))
        es, ss = np.stack(es), np.array(ss)
        keep = ss >= CRY_FRAME_MIN
        if not keep.any():
            keep[:] = True
        return es[keep].mean(0), float(ss.mean()), len(ss)


def context_vector(ctx: dict | None) -> np.ndarray:
    ctx = ctx or {}
    out = []
    for _, key, t in CONTEXT_FEATURES:
        v = ctx.get(key)
        if t == 'hours_cap12':
            out.append(min((v if v is not None else 360) / 60.0, 12.0) / 12.0)
        elif t == 'bool':
            out.append(1.0 if v else 0.0)
        elif t == 'hour_sin':
            out.append(math.sin(2 * math.pi * (v or 0) / 24))
        elif t == 'hour_cos':
            out.append(math.cos(2 * math.pi * (v or 0) / 24))
        elif t == 'cap24':
            out.append(min(float(v or 0), 24.0) / 24.0)
    return np.array(out, np.float32)
