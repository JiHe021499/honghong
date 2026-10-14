#!/usr/bin/env bash
# 在本机临时 Postgres 上跑 0001–0004 迁移、家庭 RLS 测试和日记性别测试（不连任何服务器）
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bin=$(ls -d /usr/lib/postgresql/*/bin | tail -1)
d=$(mktemp -d); port=55432
"$bin/initdb" -D "$d" -U postgres -A trust >/dev/null
"$bin/pg_ctl" -D "$d" -o "-p $port -k $d" -l "$d/log" start >/dev/null
trap '"$bin/pg_ctl" -D "$d" stop >/dev/null; rm -rf "$d"' EXIT
q() { psql -h "$d" -p $port -U postgres -d postgres -v ON_ERROR_STOP=1 -q "$@"; }
q -f "$here/local_stub.sql"
q -f "$here/../migrations/0001_init.sql"
q -f "$here/../migrations/0002_family.sql"
q -f "$here/../migrations/0003_models.sql"
q -f "$here/../migrations/0004_diary.sql"
q -f "$here/family_rls_test.sql"
q -f "$here/diary_gender_test.sql"
