"""把训练好的分类头发布到自建 Supabase：
  models/classifier/{version}.tflite + {version}.json，再 upsert model_versions（含 meta）。
service_role key 只从本机 env 文件读取（绝不入库）：
  python src/publish_model.py --env /cursor/stores/<store>/secrets/supabase-nc_am.env --version cls-1 --rollout 100
回滚：--rollout 0（eligible_model 就不再返回它，设备保留已装版本），或发布更高版本。
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import urllib.request

from supabase_export import read_env


def req(method, url, key, data=None, headers=None):
    h = {'apikey': key, 'Authorization': f'Bearer {key}', 'User-Agent': 'honghong-ml/1.0'}
    h.update(headers or {})
    r = urllib.request.Request(url, data=data, method=method, headers=h)
    with urllib.request.urlopen(r, timeout=60) as resp:
        return resp.status, resp.read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--env', required=True)
    ap.add_argument('--version', required=True)
    ap.add_argument('--build', default='build')
    ap.add_argument('--rollout', type=int, default=100)
    ap.add_argument('--notes', default='')
    a = ap.parse_args()
    env = read_env(a.env)
    base = (env.get('SUPABASE_URL') or env['API_EXTERNAL_URL']).rstrip('/')
    key = env['SERVICE_ROLE_KEY']
    tfl = open(os.path.join(a.build, f'cry_head_{a.version}.tflite'), 'rb').read()
    meta = json.load(open(os.path.join(a.build, f'cry_head_{a.version}.json')))
    sha = hashlib.sha256(tfl).hexdigest()
    assert sha == meta['sha256'] and meta['version'] == a.version, 'meta 与文件不一致'
    path = f'classifier/{a.version}.tflite'
    for p, body, ct in [(path, tfl, 'application/octet-stream'),
                        (f'classifier/{a.version}.json', json.dumps(meta, ensure_ascii=False).encode(), 'application/json')]:
        s, _ = req('POST', f'{base}/storage/v1/object/models/{p}', key, body, {'Content-Type': ct, 'x-upsert': 'true'})
        print('uploaded', p, s)
    row = {'version': a.version, 'kind': 'classifier', 'storage_path': path, 'sha256': sha,
           'rollout_percent': a.rollout, 'meta': meta, 'size_bytes': len(tfl), 'notes': a.notes or None}
    s, _ = req('POST', f'{base}/rest/v1/model_versions?on_conflict=version', key, json.dumps(row).encode(),
               {'Content-Type': 'application/json', 'Prefer': 'resolution=merge-duplicates,return=minimal'})
    print('model_versions upsert', s, a.version, sha, f'rollout={a.rollout}')


if __name__ == '__main__':
    main()
