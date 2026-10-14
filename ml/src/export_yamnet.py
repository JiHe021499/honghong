"""把 TF Hub YAMNet 转成端上用的 TFLite：一帧（15600 采样，16kHz）→ 521 类得分 + 1024 维 embedding。
App 用同一个模型做哭声检测（scores）和猜原因的音频特征（embedding）。"""
import argparse, hashlib
import numpy as np
import tensorflow as tf
import tensorflow_hub as hub

ap = argparse.ArgumentParser()
ap.add_argument('--out', default='build/yamnet_embed.tflite')
ap.add_argument('--quant', choices=['none', 'dynamic', 'fp16'], default='dynamic')
a = ap.parse_args()

yam = hub.load('https://tfhub.dev/google/yamnet/1')

class M(tf.Module):
    @tf.function(input_signature=[tf.TensorSpec([15600], tf.float32, name='waveform')])
    def serve(self, w):
        scores, emb, _ = yam(w)
        return {'scores': scores[:1], 'embedding': emb[:1]}

m = M()
conv = tf.lite.TFLiteConverter.from_concrete_functions([m.serve.get_concrete_function()], m)
conv.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
if a.quant != 'none':
    conv.optimizations = [tf.lite.Optimize.DEFAULT]
if a.quant == 'fp16':
    conv.target_spec.supported_types = [tf.float16]
b = conv.convert()
import os; os.makedirs(os.path.dirname(a.out) or '.', exist_ok=True)
open(a.out, 'wb').write(b)
print(a.out, len(b), hashlib.sha256(b).hexdigest())
