"""小分类器：audio embedding(1024) + context(7) -> 原因 softmax。"""
import tensorflow as tf

LABELS = ["hungry", "sleepy", "gas", "diaper", "holdMe"]

def build_model(audio_dim=1024, ctx_dim=7, n=len(LABELS)):
    a = tf.keras.Input((audio_dim,), name="audio")
    c = tf.keras.Input((ctx_dim,), name="context")
    x = tf.keras.layers.Concatenate()([tf.keras.layers.Dense(128, activation="relu")(a), c])
    x = tf.keras.layers.Dropout(0.3)(x)
    x = tf.keras.layers.Dense(64, activation="relu")(x)
    out = tf.keras.layers.Dense(n, activation="softmax", name="head")(x)  # 端上个性化只微调 head
    m = tf.keras.Model([a, c], out)
    m.compile("adam", "sparse_categorical_crossentropy", metrics=["accuracy"])
    return m

# TODO: 按宝宝分组划分训练/验证集，评估 top-1 一致率
