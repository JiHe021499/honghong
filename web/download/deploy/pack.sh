#!/bin/sh
# 打包分发页：给 HTML 引用的 css/js 加 ?v=<提交号>，让 Cloudflare 缓存的旧资源失效（HTML 本身不被缓存）。
# 用法：web/download/deploy/pack.sh [输出文件，默认 /tmp/download-page.tgz]
# 只打包 index.html、beta/、assets/；不含 deploy/、README、data/、files/。
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-/tmp/download-page.tgz}
cd "$here"
if [ -n "$(git status --porcelain -- . 2>/dev/null)" ]; then
  echo "web/download 有未提交的改动，先提交再打包（版本号取自提交号）" >&2; exit 1
fi
v=$(git rev-parse --short=10 HEAD)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp -R index.html beta assets "$tmp/"
for f in "$tmp/index.html" "$tmp/beta/index.html"; do
  sed -E -i.orig "s#(assets/[A-Za-z0-9_.-]+\.(css|js))\"#\1?v=$v\"#g" "$f" && rm -f "$f.orig"
done
n=$(grep -cE "\.(css|js)\?v=$v\"" "$tmp/index.html" "$tmp/beta/index.html" | awk -F: '{s+=$2} END{print s}')
[ "$n" -ge 8 ] || { echo "只替换了 $n 处资源引用，预期至少 8 处" >&2; exit 1; }
tar czf "$out" -C "$tmp" index.html beta assets
echo "已打包 $out（v=$v，替换 $n 处）"
