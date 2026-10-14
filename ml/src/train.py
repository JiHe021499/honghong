"""训练猜原因的小分类头，并做诚实评估。

输入：data_prep.py 产出的 features.npz（YAMNet embedding [+ 上下文]）。
评估：按 group（donateacry 的 app 安装 id ≈ 同一个宝宝/家庭；App 数据按 device）分组的
分层 5 折交叉验证，重复 R 次换随机种子；同一宝宝不会同时出现在训练和验证集。
报告：每类 precision/recall/F1、宏平均 F1、平衡准确率、top-2、混淆矩阵，以及"全猜最多的类"
和"按先验随机猜"两个基线。
模型：标准化 + 多项逻辑回归（class_weight=balanced，输出近似"均匀先验下的音频似然"，
在 App 端和上下文规则做对数线性融合）。超参数 C 在同一套外层 CV 上挑选 —— 会有轻微乐观偏差，报告里写明。
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os

import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import balanced_accuracy_score, confusion_matrix, f1_score, precision_recall_fscore_support
from sklearn.model_selection import StratifiedGroupKFold
from sklearn.pipeline import make_pipeline
from sklearn.preprocessing import StandardScaler

import features as F

ALL_CAUSES = ['hungry', 'sleepy', 'gas', 'diaper', 'holdMe']


def make_model(C: float):
    return make_pipeline(StandardScaler(), LogisticRegression(C=C, class_weight='balanced', max_iter=5000))


def cv_eval(X, y, groups, classes, C, repeats, seed=0):
    res = []
    cm_sum = np.zeros((len(classes), len(classes)), int)
    for r in range(repeats):
        skf = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=seed + r)
        P = np.zeros((len(y), len(classes)))
        for tr, te in skf.split(X, y, groups):
            m = make_model(C).fit(X[tr], y[tr])
            P[te] = m.predict_proba(X[te])[:, [list(m.classes_).index(c) for c in classes]]
        pred = np.array(classes)[P.argmax(1)]
        top2 = np.mean([y[i] in np.array(classes)[np.argsort(-P[i])[:2]] for i in range(len(y))])
        p, rc, f, _ = precision_recall_fscore_support(y, pred, labels=classes, zero_division=0)
        res.append({'macro_f1': f1_score(y, pred, labels=classes, average='macro', zero_division=0),
                    'balanced_acc': balanced_accuracy_score(y, pred), 'acc': float(np.mean(pred == y)), 'top2': top2,
                    'precision': p, 'recall': rc, 'f1': f})
        cm_sum += confusion_matrix(y, pred, labels=classes)
    agg = {k: (float(np.mean([r[k] for r in res])), float(np.std([r[k] for r in res])))
           for k in ['macro_f1', 'balanced_acc', 'acc', 'top2']}
    per = {c: {m: round(float(np.mean([r[m][i] for r in res])), 3) for m in ['precision', 'recall', 'f1']}
           for i, c in enumerate(classes)}
    return agg, per, cm_sum


def baselines(y, classes, repeats=200, seed=0):
    maj = max(classes, key=lambda c: np.sum(y == c))
    pred = np.full(len(y), maj)
    rng = np.random.default_rng(seed)
    prior = np.array([np.mean(y == c) for c in classes])
    rnd = [f1_score(y, rng.choice(classes, len(y), p=prior), labels=classes, average='macro', zero_division=0) for _ in range(repeats)]
    return {
        'majority': {'class': maj, 'macro_f1': float(f1_score(y, pred, labels=classes, average='macro', zero_division=0)),
                     'balanced_acc': float(balanced_accuracy_score(y, pred)), 'acc': float(np.mean(pred == y))},
        'prior_random': {'macro_f1': float(np.mean(rnd)), 'balanced_acc': 1 / len(classes)},
    }


def export_tflite(model, classes, out_path, dim):
    import tensorflow as tf

    sc, lr = model.named_steps['standardscaler'], model.named_steps['logisticregression']
    order = [list(lr.classes_).index(c) for c in classes]
    W = (lr.coef_[order] / sc.scale_).T.astype(np.float32)               # [dim, k]
    b = (lr.intercept_[order] - (lr.coef_[order] * sc.mean_ / sc.scale_).sum(1)).astype(np.float32)

    class Head(tf.Module):
        def __init__(self):
            self.W = tf.constant(W)
            self.b = tf.constant(b)

        @tf.function(input_signature=[tf.TensorSpec([1, dim], tf.float32, name='features')])
        def serve(self, x):
            return {'probs': tf.nn.softmax(tf.matmul(x, self.W) + self.b)}

    h = Head()
    conv = tf.lite.TFLiteConverter.from_concrete_functions([h.serve.get_concrete_function()], h)
    data = conv.convert()
    open(out_path, 'wb').write(data)
    return data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--features', default='data/features.npz')
    ap.add_argument('--version', required=True)
    ap.add_argument('--out', default='build')
    ap.add_argument('--context', action='store_true', help='拼接上下文特征（只用有上下文的样本）')
    ap.add_argument('--repeats', type=int, default=10)
    ap.add_argument('--C', type=float, nargs='+', default=[0.001, 0.003, 0.01, 0.03, 0.1])
    a = ap.parse_args()

    d = np.load(a.features, allow_pickle=False)
    X, y, groups = d['X'], d['y'], d['group']
    mask = d['has_context'] if a.context else np.ones(len(y), bool)
    X = np.hstack([X, d['C']]) if a.context else X
    X, y, groups = X[mask], y[mask], groups[mask]
    classes = [c for c in ALL_CAUSES if np.sum(y == c) >= 5]
    keep = np.isin(y, classes)
    X, y, groups = X[keep], y[keep], groups[keep]
    counts = {c: int(np.sum(y == c)) for c in classes}
    print('samples', len(y), counts, 'groups', len(set(groups)))

    sweep = {}
    for C in a.C:
        agg, per, cm = cv_eval(X, y, groups, classes, C, a.repeats)
        sweep[C] = (agg, per, cm)
        print(f'C={C}: macroF1={agg["macro_f1"][0]:.3f}±{agg["macro_f1"][1]:.3f} balAcc={agg["balanced_acc"][0]:.3f} acc={agg["acc"][0]:.3f} top2={agg["top2"][0]:.3f}')
    best = max(sweep, key=lambda C: sweep[C][0]['macro_f1'][0])
    agg, per, cm = sweep[best]
    base = baselines(y, classes)
    print('best C', best, json.dumps(per, ensure_ascii=False))
    print('confusion (rows=true, cols=pred, summed over repeats)', classes)
    print(cm)
    print('baselines', base)

    chance = 1 / len(classes)
    blend_w = 0.0 if agg['balanced_acc'][0] < chance + 0.05 else 0.35
    print('blend weight', blend_w, f'(balanced acc {agg["balanced_acc"][0]:.3f} vs chance {chance:.3f})')
    model = make_model(best).fit(X, y)
    os.makedirs(a.out, exist_ok=True)
    tfl = os.path.join(a.out, f'cry_head_{a.version}.tflite')
    data = export_tflite(model, classes, tfl, X.shape[1])
    sha = hashlib.sha256(data).hexdigest()
    embed_sha = hashlib.sha256(open(F.EMBED_MODEL, 'rb').read()).hexdigest()
    probe = X[:1].astype(np.float32)
    expected = model.predict_proba(probe)[0][[list(model.classes_).index(c) for c in classes]]
    src_counts = {s: int(np.sum(d['source'][mask][keep] == s)) for s in ('donateacry', 'app')}
    meta = {
        'version': a.version,
        'kind': 'classifier',
        'created_at': dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds'),
        'classes': classes,
        'file': os.path.basename(tfl),
        'sha256': sha,
        'size': len(data),
        'input': {
            'embedding': {'dim': 1024, 'model': 'yamnet_embed.tflite', 'model_sha256': embed_sha,
                          'sample_rate': F.SR, 'frame': F.FRAME, 'hop': F.HOP,
                          'fir_taps': F.FIR_TAPS, 'fir_cutoff_hz': F.FIR_CUTOFF_HZ,
                          'pool': 'mean', 'cry_frame_min': F.CRY_FRAME_MIN, 'cry_class_idx': list(F.CRY_IDX)},
            'context': [n for n, _, _ in F.CONTEXT_FEATURES] if a.context else [],
        },
        # App 端融合：p ∝ p_rule^(1-w) · p_model^w，w = blend_weight × 置信度系数；
        # 模型最高概率 < min_confidence 或没有有效哭声音频时只用规则
        # 交叉验证的平衡准确率没有比随机猜（1/k）高出 0.05 时，权重设为 0：模型只"影子运行"，
        # 输出记进预测记录，用家长反馈在端上和以后的训练里验证，不影响给家长看的结果
        'blend': {'weight': blend_w, 'min_confidence': 0.4, 'min_cry_score': 0.1,
                  'mode': 'shadow' if blend_w == 0 else 'blend'},
        'selftest': {'input': [round(float(v), 6) for v in probe[0]], 'expected': [round(float(v), 6) for v in expected], 'tol': 1e-3},
        'training': {'sources': src_counts, 'counts': counts, 'groups': int(len(set(groups))),
                     'license': 'donateacry-corpus: ODbL 1.0 / DbCL 1.0 (https://github.com/gveres/donateacry-corpus)'},
        'eval': {
            'protocol': f'StratifiedGroupKFold(5) by baby/install id, {a.repeats} repeats; C chosen on the same CV (slightly optimistic)',
            'C': best,
            'macro_f1': [round(v, 3) for v in agg['macro_f1']],
            'balanced_acc': [round(v, 3) for v in agg['balanced_acc']],
            'acc': [round(v, 3) for v in agg['acc']],
            'top2': [round(v, 3) for v in agg['top2']],
            'per_class': per,
            'confusion': {'labels': classes, 'matrix': cm.tolist(), 'note': 'rows=true, cols=pred, summed over repeats'},
            'baselines': base,
            'sweep': {str(C): {k: round(v[0], 3) for k, v in s[0].items()} for C, s in sweep.items()},
        },
    }
    json.dump(meta, open(os.path.join(a.out, f'cry_head_{a.version}.json'), 'w'), ensure_ascii=False, indent=1)
    print('exported', tfl, len(data), sha)


if __name__ == '__main__':
    main()
