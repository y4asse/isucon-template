#!/usr/bin/env bash
# Discord に通知する。失敗しても呼び出し元を止めない（best-effort）
# usage: notify.sh "メッセージ" [添付ファイル...]
cd "$(dirname "$0")/.." || exit 0

[ -f .env ] && . ./.env
if [ -z "${DISCORD_WEBHOOK_URL:-}" ]; then
  echo "(notify: DISCORD_WEBHOOK_URL 未設定のためスキップ)"
  exit 0
fi

id=$(cat .server_id 2>/dev/null || hostname)
msg="[$id] $1"
shift

payload=$(python3 -c 'import json,sys; print(json.dumps({"content": sys.argv[1][:1900]}))' "$msg")
args=(-F "payload_json=$payload")
i=0
for f in "$@"; do
  # Discord の添付上限（8MB）を超えるものは送らない
  if [ -f "$f" ] && [ "$(stat -c %s "$f")" -lt 8000000 ]; then
    args+=(-F "files[$i]=@$f")
    i=$((i + 1))
  fi
done

curl -sS --max-time 15 -o /dev/null "${args[@]}" "$DISCORD_WEBHOOK_URL" \
  || echo "(notify: 送信に失敗しました)"
exit 0
