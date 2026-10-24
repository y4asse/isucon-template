#!/usr/bin/env bash
# etc/common → etc/<server_id> の順に /etc へコピーし、変更があったものだけ反映する
# usage: deploy-conf.sh <server_id> <env_file> <db_service>
set -euo pipefail
cd "$(dirname "$0")/.."

ID=$1
ENV_FILE=$2
DB_SERVICE=$3
ROOT=${DEPLOY_ROOT:-}   # テスト用。通常は空（= /）
changed=()

# 反映するファイルを決める（同じパスなら etc/<id> を優先）
declare -A src=()
for base in etc/common "etc/$ID"; do
  [ -d "$base" ] || continue
  while IFS= read -r -d '' f; do
    src[${f#"$base"}]=$f
  done < <(find "$base" -type f ! -name .gitkeep -print0)
done

for rel in "${!src[@]}"; do
  f=${src[$rel]}
  if ! sudo cmp -s "$f" "$ROOT$rel"; then
    sudo install -D -m 644 "$f" "$ROOT$rel"
    changed+=("$rel")
    echo "更新: $rel"
  fi
done

# アプリの環境変数: env.common.sh + env.<id>.sh を結合
if [ -f env/env.common.sh ]; then
  tmp=$(mktemp)
  cat env/env.common.sh > "$tmp"
  [ -f "env/env.$ID.sh" ] && cat "env/env.$ID.sh" >> "$tmp"
  if ! cmp -s "$tmp" "$ENV_FILE"; then
    cp "$tmp" "$ENV_FILE"
    echo "更新: $ENV_FILE"
  fi
  rm -f "$tmp"
fi

has() { printf '%s\n' "${changed[@]}" | grep -q "^$1"; }

if [ ${#changed[@]} -gt 0 ]; then
  if has /etc/systemd/; then sudo systemctl daemon-reload && echo "daemon-reload"; fi
  if has /etc/sysctl; then sudo sysctl --system > /dev/null && echo "sysctl 反映"; fi
  if has /etc/nginx/ && systemctl is-active --quiet nginx; then
    if ! sudo nginx -t; then
      echo "nginx の設定エラーのため中断します（nginx は古い設定のまま動いています）"
      exit 1
    fi
    sudo systemctl reload nginx && echo "reload: nginx"
  fi
  if has /etc/mysql/ && systemctl is-active --quiet "$DB_SERVICE"; then
    sudo systemctl restart "$DB_SERVICE" && echo "restart: $DB_SERVICE"
  fi
fi
