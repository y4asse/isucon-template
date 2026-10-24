#!/usr/bin/env bash
# 初期状態を記録する（後から「最初どうなってたっけ」を確認するため）
# usage: snapshot.sh <出力ディレクトリ>
set -uo pipefail
out=$1
mkdir -p "$out"

lscpu > "$out/cpu.txt"
free -h > "$out/memory.txt"
df -h > "$out/disk.txt"
ip -br addr > "$out/ip.txt"
sudo ss -tlnp > "$out/ports.txt"
ps auxf > "$out/ps.txt"
systemctl list-units --type=service --state=running --no-pager > "$out/services-running.txt"
systemctl list-unit-files --type=service --no-pager > "$out/services-all.txt"
dpkg -l > "$out/packages.txt"
{
  nginx -v 2>&1
  mysql --version 2>&1
  go version 2>&1
} > "$out/versions.txt"

echo "保存先: $out"
