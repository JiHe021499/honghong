"""导出 TFLite（float16 量化）并写出 sha256，供 Supabase 下发。"""
import argparse, hashlib
import tensorflow as tf

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    conv = tf.lite.TFLiteConverter.from_keras_model(tf.keras.models.load_model(a.model))
    conv.optimizations = [tf.lite.Optimize.DEFAULT]
    conv.target_spec.supported_types = [tf.float16]
    data = conv.convert()
    open(a.out, "wb").write(data)
    print("sha256:", hashlib.sha256(data).hexdigest())

if __name__ == "__main__":
    main()
