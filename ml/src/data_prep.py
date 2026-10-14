"""把各数据源整理成统一清单（manifest.csv）并提取特征缓存（features.npz）。

数据源：
- donateacry：公开语料 donateacry-corpus 的 cleaned 子集（ODbL 1.0 / DbCL 1.0，见 ml/README.md）
- app：supabase_export.py 导出的 App 上传片段 + 家长反馈（ml/data/app/manifest.csv）

标签对齐到 App 的 CryCause：hungry / sleepy / gas / diaper / holdMe
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from features import Embedder, context_vector, load_audio  # noqa: E402

# donateacry 原标签 → App 原因
DONATEACRY_MAP = {
    'hungry': 'hungry',      # hu
    'tired': 'sleepy',       # ti
    'burping': 'gas',        # bu 需要拍嗝
    'belly_pain': 'gas',     # bp 肚子疼（App 里"胀气"最接近）
    'discomfort': 'diaper',  # dc（含原 cold/hot）→ "不舒服/尿布"
}
AGE_MONTHS = {'04': 0.5, '48': 1.5, '26': 4.0, '72': 12.0, '22': 30.0}
NAME_RE = re.compile(r'^(?P<uuid>[0-9A-Fa-f-]{36})-.*-(?P<sex>[mf])-(?P<age>\d\d)-(?P<tag>[a-z]{2})\.wav$')


def donateacry_rows(root: str) -> list[dict]:
    base = os.path.join(root, 'donateacry_corpus_cleaned_and_updated_data')
    rows = []
    for folder, cause in DONATEACRY_MAP.items():
        for f in sorted(os.listdir(os.path.join(base, folder))):
            m = NAME_RE.match(f)
            if not m:
                continue
            rows.append({
                'path': os.path.join(base, folder, f),
                'label': cause,
                'raw_label': folder,
                'group': 'dac:' + m['uuid'].lower(),
                'age_months': AGE_MONTHS.get(m['age'], ''),
                'source': 'donateacry',
                'context': '',
            })
    return rows


def app_rows(manifest: str) -> list[dict]:
    if not os.path.exists(manifest):
        return []
    with open(manifest) as f:
        return [dict(r, source='app') for r in csv.DictReader(f)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--donateacry', default='/workspace/donateacry-corpus')
    ap.add_argument('--app-manifest', default='data/app/manifest.csv')
    ap.add_argument('--out', default='data/features.npz')
    a = ap.parse_args()

    rows = donateacry_rows(a.donateacry) + app_rows(a.app_manifest)
    print(f'{len(rows)} clips', {s: sum(r["source"] == s for r in rows) for s in ('donateacry', 'app')})
    emb = Embedder()
    X, C, scores, nframes = [], [], [], []
    for i, r in enumerate(rows):
        e, s, n = emb.clip(load_audio(r['path']))
        X.append(e)
        scores.append(s)
        nframes.append(n)
        C.append(context_vector(json.loads(r['context']) if r.get('context') else None))
        if i % 50 == 0:
            print(i, r['label'], f'cry={s:.2f}', flush=True)
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    np.savez_compressed(
        a.out,
        X=np.stack(X), C=np.stack(C),
        y=np.array([r['label'] for r in rows]),
        raw=np.array([r['raw_label'] for r in rows]),
        group=np.array([r['group'] for r in rows]),
        source=np.array([r['source'] for r in rows]),
        has_context=np.array([bool(r.get('context')) for r in rows]),
        cry_score=np.array(scores), nframes=np.array(nframes),
        path=np.array([r['path'] for r in rows]),
    )
    print('saved', a.out)


if __name__ == '__main__':
    main()
