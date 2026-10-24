# 手順書

前日の準備から当日のセットアップ・改善サイクルまで、上から順に進める。

## 前日まで

1. GitHub で **Use this template** → **private** リポジトリを作成し、メンバーをコラボレーターに招待
2. Deploy key 用の鍵を作り、リポジトリの Settings > Deploy keys に登録（Allow write access にチェック）

   ```sh
   ssh-keygen -t ed25519 -f ~/.ssh/isucon_deploy_key -N ""
   ```

3. Discord 通知を使うなら、手元のリポジトリで `.env` を作り `DISCORD_WEBHOOK_URL` を書く（Git 管理外なのでコミットされない）

   ```sh
   cp .env.example .env
   ```

   Webhook URL は Discord のチャンネル設定 → 連携サービス → ウェブフック → 新しいウェブフック → URL をコピー
4. 各メンバーの SSH 公開鍵が GitHub に登録されていることを確認（本番はその鍵で `isucon` ユーザーに入る）
5. 下の役割分担を決める

## 役割分担（3 人の例）

| 担当 | 主な仕事 |
|---|---|
| A：インフラ・計測 | 初期セットアップ、nginx / MySQL 設定、ベンチと計測、複数台構成 |
| B：アプリ | 計測結果をもとにコードの改善（N+1、重い処理） |
| C：アプリ・DB | インデックス、クエリ改善、お題特有のロジック（マッチングなど） |

1 人なら上から順にやる。

## 時間の目安（10:00〜18:00）

| 時刻 | やること |
|---|---|
| 10:00 | 全員でマニュアルを読む（スコアの計算方法・失格条件を必ず確認） |
| 10:20 | A：セットアップ（下の手順）／ B・C：アプリのコードと DB スキーマを読む |
| 10:50 | 初回ベンチ → `make analyze` → 全員で結果を見て方針決め |
| 11:00〜 | 改善サイクル |
| 14:00 | 複数台構成にするか判断 |
| 17:00 | 計測を止める（`make finalize`）、pprof 削除 |
| 17:20 | 全台で再起動テスト |
| 17:40 | 最終ベンチ。以降は変更しない |

## セットアップ手順（A が担当）

### 1. 手元の準備

`~/.ssh/config` にサーバーを書く（IP はポータルで確認）。

```
Host s1
  HostName <s1 の IP>
  User isucon
Host s2
  HostName <s2 の IP>
  User isucon
Host s3
  HostName <s3 の IP>
  User isucon
```

前日に作った Deploy key を各サーバーに送る（手元で）。

```sh
for h in s1 s2 s3; do scp ~/.ssh/isucon_deploy_key $h:~/.ssh/id_ed25519 && ssh $h chmod 600 .ssh/id_ed25519; done
```

### 2. 各サーバーでリポジトリを展開（s1 → s2 → s3 の順）

```sh
cd ~
git init -b main
git remote add origin git@github.com:<owner>/<repo>.git
git fetch origin main
git reset origin/main     # 既存ファイルはそのまま、履歴だけ取り込む
git checkout -- .         # Makefile などを展開
make set-id ID=s1         # s2 / s3 ではそれぞれの ID
make setup
```

`make setup` の最後に表示される `SERVICE` と `BIN` が空なら `config.mk` で設定する。

3 台とも終わったら、前日に作った `.env` を送る（手元で）。

```sh
for h in s1 s2 s3; do scp .env $h:~/.env; done
```

### 3. 初期状態をコミット（s1 だけ）

```sh
make snapshot
make pull-conf            # /etc の設定と env.sh を取り込む
make ignore-langs         # 使わない言語の実装などを gitignore
git add -A && git commit -m "初期状態" && git push origin main
```

s2・s3 では `git pull` してから `make snapshot` → コミット。

### 4. 計測の準備

1. `etc/common/etc/nginx/nginx.conf` の `access_log` を `access_log /var/log/nginx/access.log ltsv;` に変更
2. Go なら pprof を仕込む（下記）
3. コミットして `make deploy`

```go
import _ "net/http/pprof"

// main() の最初の方に追加
go func() { log.Println(http.ListenAndServe("localhost:6060", nil)) }()
```

### 5. 初回ベンチ

```sh
make all-bench-prep       # 手元から（全サーバーでログ退避・slow log ON）
# ポータルからベンチ実行。別ペインで make log
make score S=<スコア> M="初期状態"   # s1 で
make all-analyze
```

## 改善サイクル

```
手元で改善してコミット・push
  → make deploy-all（または各サーバーで make deploy）
  → make all-bench-prep
  → ポータルでベンチ
  → make score S=... M="..."（どれか 1 台で）
  → make all-analyze
```

- 1 コミット 1 目的。スコアが下がったら `git revert`
- DB のスキーマ・インデックスを変えるときはチームに一声かける
- 30 分詰まったら別の改善へ
- 計測結果（`~/analysis/`）は Git には入れない。Discord に投稿されたものをチームで見る

## 複数台構成にするとき

- サーバー別の設定は `etc/sN/etc/...` に置く（同じパスのファイルは common より優先）
- サーバー別の環境変数は `env/env.sN.sh`
- 使わないサービスは止めて自動起動も切る：`sudo systemctl disable --now <サービス>`
- DB を分けたら `99-isucon.cnf` の `bind-address` を有効化し、アプリ側の DB ホストを変更

## トラブル時

| 症状 | 確認すること |
|---|---|
| ベンチが失敗する | `make log` でアプリのエラー、`sudo tail /var/log/nginx/error.log` |
| deploy で nginx がエラー | `sudo nginx -t` の出力を見る（反映前に止まるので nginx は動いたまま） |
| 変更が反映されない | `make info` で SERVICE / BIN を確認、`git log -1` で最新か確認 |
| 壊れた | `git revert` → `make deploy`。設定ファイルは `etc/common/` が元の状態 |
