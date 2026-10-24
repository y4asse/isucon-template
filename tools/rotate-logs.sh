#!/usr/bin/env bash
# ベンチ前にログを ~/logs/<時刻>/ に退避する
# usage: rotate-logs.sh <nginx_log> <slow_log> <db_service>
set -uo pipefail

NGINX_LOG=$1
SLOW_LOG=$2
DB_SERVICE=$3
dest=~/logs/$(date +%m%d-%H%M%S)
mkdir -p "$dest"

for f in "$NGINX_LOG" "$SLOW_LOG"; do
  if sudo test -s "$f"; then
    sudo mv "$f" "$dest/"
    echo "退避: $f → $dest/"
  fi
done

# 再起動せずに新しいログファイルへ書き始めさせる
if systemctl is-active --quiet nginx; then sudo nginx -s reopen; fi
if systemctl is-active --quiet "$DB_SERVICE"; then echo "FLUSH SLOW LOGS;" | sudo mysql; fi
exit 0
