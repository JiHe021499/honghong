"""从自建 Supabase 导出 App 上传的哭声片段 + 家长反馈，写 data/app/manifest.csv。

用 service_role key 读取（绕过 RLS），key 只从本机 env 文件读取，绝不入库：
  python src/supabase_export.py --env /cursor/stores/<store>/secrets/supabase-nc_am.env
env 文件需要 API_EXTERNAL_URL（或 SUPABASE_URL）和 SERVICE_ROLE_KEY。
只导出有反馈（resolved_cause != unknown）且有片段的事件；按 device_id 分组，评估时同一设备不跨训练/验证集。
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import urllib.parse
import urllib.request

CAUSES = {'hungry', 'sleepy', 'gas', 'diaper', 'holdMe'}


def read_env(path: str) -> dict:
    env = {}
    for line in open(path):
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            k, v = line.split('=', 1)
            env[k] = v.strip().strip('"')
    return env


def get(url: str, key: str, raw=False):
    req = urllib.request.Request(url, headers={'apikey': key, 'Authorization': f'Bearer {key}', 'User-Agent': 'honghong-ml/1.0'})
    with urllib.request.urlopen(req, timeout=60) as r:
        b = r.read()
    return b if raw else json.loads(b)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--env', required=True)
    ap.add_argument('--out', default='data/app')
    a = ap.parse_args()
    env = read_env(a.env)
    base = (env.get('SUPABASE_URL') or env['API_EXTERNAL_URL']).rstrip('/')
    key = env['SERVICE_ROLE_KEY']
    sel = urllib.parse.quote('id,cry_event_id,device_id,resolved_cause,created_at,cry_events(id,clip_path,context,baby_id)')
    fbs = get(f'{base}/rest/v1/feedbacks?select={sel}&order=created_at.asc', key)
    # 每个事件取最后一次反馈
    latest = {}
    for fb in fbs:
        latest[fb['cry_event_id']] = fb
    os.makedirs(os.path.join(a.out, 'clips'), exist_ok=True)
    rows = []
    for ev_id, fb in latest.items():
        ev = fb.get('cry_events') or {}
        if fb['resolved_cause'] not in CAUSES or not ev.get('clip_path'):
            continue
        path = ev['clip_path'].removeprefix('cry-clips/')
        local = os.path.join(a.out, 'clips', f'{ev_id}.wav')
        if not os.path.exists(local):
            data = get(f'{base}/storage/v1/object/cry-clips/{urllib.parse.quote(path)}', key, raw=True)
            open(local, 'wb').write(data)
        ctx = ev.get('context') or {}
        rows.append({
            'path': os.path.abspath(local), 'label': fb['resolved_cause'], 'raw_label': fb['resolved_cause'],
            'group': 'app:' + fb['device_id'], 'age_months': ctx.get('baby_age_months', ''),
            'source': 'app', 'context': json.dumps(ctx),
        })
    with open(os.path.join(a.out, 'manifest.csv'), 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=['path', 'label', 'raw_label', 'group', 'age_months', 'source', 'context'])
        w.writeheader()
        w.writerows(rows)
    print(f'{len(fbs)} feedbacks, {len(rows)} labelled clips exported → {a.out}/manifest.csv')


if __name__ == '__main__':
    main()
