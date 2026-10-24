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

`~/.ssh/config` にサーバーを書く（IP はポータルで確認）。台数がちがうときは Host を増減し、`config.mk` の `SERVERS` も合わせる。

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

### 2. 全サーバーにリポジトリを展開（手元のリポジトリで）

1 つずつ実行し、エラーが出たらそれだけやり直す。

1. リポジトリの URL（SSH 形式）とサーバーの一覧を設定（以降のコマンドで使う。サーバーは `~/.ssh/config` の Host 名）

   ```sh
   REPO=git@github.com:<owner>/<repo>.git
   SERVERS=(s1 s2 s3)
   ```

2. Deploy key を送る

   ```sh
   for h in "${SERVERS[@]}"; do scp ~/.ssh/isucon_deploy_key $h:.ssh/id_ed25519 && ssh $h chmod 600 .ssh/id_ed25519; done
   ```

3. リポジトリを展開（既存ファイルはそのまま、履歴だけ取り込む）。3 台とも最新コミットが表示されれば成功

   ```sh
   for h in "${SERVERS[@]}"; do ssh $h "ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null && git init -q -b main && git remote add origin $REPO && git fetch -q origin main && git reset -q origin/main && git checkout -- . && git log --oneline -1"; done
   ```

   失敗して空の `.git` が残ったら、消してからやり直す

   ```sh
   for h in "${SERVERS[@]}"; do ssh $h 'test -z "$(git -C ~ rev-parse -q --verify HEAD)" && rm -rf ~/.git'; done
   ```

4. サーバー ID を設定（Host 名をそのまま使う）

   ```sh
   for h in "${SERVERS[@]}"; do ssh $h make set-id ID=$h; done
   ```

5. ツール導入と git 設定（全サーバー並列）。最後に表示される `SERVICE` と `BIN` が空なら `config.mk` で設定する

   ```sh
   make all-setup
   ```

6. `.env` を送る

   ```sh
   for h in "${SERVERS[@]}"; do scp .env $h:.env; done
   ```

### 3. 初期状態をコミット

1. s1 に入る（手元で）

   ```sh
   ssh s1
   ```

2. 初期状態の記録、`/etc` の設定と `env.sh` の取り込み、使わない言語の実装などの gitignore（s1 で）

   ```sh
   make snapshot
   make pull-conf
   make ignore-langs
   ```

3. コミットされるものを確認（s1 で）。`webapp/` の他言語の実装や巨大なファイルが入っていなければ OK

   ```sh
   git add -A && git status --short | head -n 50
   ```

4. コミットして push し、s1 から出る（s1 で）

   ```sh
   git commit -m "初期状態" && git push origin main
   exit
   ```

5. s2・s3 に s1 のコミットを取り込み、それぞれの初期状態を記録して push（手元で）。`git pull` は未追跡の `webapp/` とぶつかって失敗するので、展開時と同じく fetch → reset → checkout で取り込む

   ```sh
   for h in "${SERVERS[@]:1}"; do ssh $h 'git fetch -q origin main && git reset -q origin/main && git checkout -- . && make snapshot && git add snapshots && git commit -q -m "初期状態: $(cat .server_id)" && git push -q origin main && git log --oneline -1'; done
   ```

6. 手元にも取り込む（手元で）

   ```sh
   git pull
   ```

### 4. 計測の準備

すべて手元のリポジトリで作業する。

1. `etc/common/etc/nginx/nginx.conf` の `access_log /var/log/nginx/access.log;` の行を消す。LTSV 形式の `access_log` は `etc/common/etc/nginx/conf.d/00-isucon-log.conf` に書いてある
2. 有効な `access_log` が `00-isucon-log.conf` の 1 行だけになったことを確認（sites-available 側にもあれば消す）

   ```sh
   grep -rnE '^\s*access_log' etc/common/etc/nginx/
   ```

3. Go なら `webapp/go/main.go` に pprof を仕込む。`import (` の中に 1 行、`func main() {` の直後に 1 行足す

   ```go
   	_ "net/http/pprof"
   ```

   ```go
   	go func() { _ = http.ListenAndServe("localhost:6060", nil) }()
   ```

4. コミットして push し、全サーバーにデプロイ。各サーバーで `reload: nginx` と `restart: isuride-go.service` が出れば OK（nginx の設定エラーなら `nginx -t` の出力が出て止まる）

   ```sh
   git add -A && git commit -m "計測の準備" && git push origin main
   ```

   ```sh
   make deploy-all
   ```

5. LTSV でログが出ていることを確認。`time:` で始まる行が出れば OK

   ```sh
   ssh s1 'curl -sk -o /dev/null https://localhost/ && sudo tail -n 1 /var/log/nginx/access.log'
   ```

6. pprof が動いていることを確認。`200` が出れば OK

   ```sh
   ssh s1 'curl -s -o /dev/null -w "%{http_code}\n" localhost:6060/debug/pprof/'
   ```

### 5. 初回ベンチ

すべて手元のリポジトリで実行する。

1. 全サーバーでログ退避・slow log ON

   ```sh
   make all-bench-prep
   ```

2. ポータルからベンチ実行。ベンチ中は別ペインで s1 のアプリのログを見る（Ctrl+C で抜ける）

   ```sh
   ssh -t s1 make log
   ```

3. s1 でスコアを記録して push（`12345` をスコアに置き換える）

   ```sh
   ssh s1 'make score S=12345 M="初期状態"'
   ```

4. 全サーバーで解析。結果は Discord に投稿され、各サーバーの `~/analysis/` にも保存される

   ```sh
   make all-analyze
   ```

5. s1 が push したスコアを手元に取り込む

   ```sh
   git pull
   ```

## 改善サイクル

すべて手元のリポジトリで実行する。

1. 最新を取り込む（スコアの記録で s1 が push しているため）

   ```sh
   git pull
   ```

2. 改善してコミット・push（1 コミット 1 目的）

   ```sh
   git add -A && git commit -m "変更内容" && git push origin main
   ```

3. 全サーバーにデプロイ

   ```sh
   make deploy-all
   ```

4. ベンチの準備

   ```sh
   make all-bench-prep
   ```

5. ポータルからベンチ実行。別ペインで s1 のアプリのログを見る

   ```sh
   ssh -t s1 make log
   ```

   pprof を取るなら、ベンチ開始直後にさらに別ペインで（60 秒取得して s1 の `~/pprof/` に保存）

   ```sh
   ssh s1 make pprof
   ```

6. スコアを記録（`12345` と `変更内容` を置き換える）

   ```sh
   ssh s1 'make score S=12345 M="変更内容"'
   ```

7. 解析

   ```sh
   make all-analyze
   ```

8. pprof を見るなら、s1 で表示サーバーを立ててブラウザで <http://localhost:8090> を開く（Ctrl+C で終了）

   ```sh
   ssh -L 8090:localhost:8090 s1 make pprof-web
   ```

スコアが下がったら直前のコミットを打ち消してデプロイし直す。

```sh
git revert --no-edit HEAD && git push origin main && make deploy-all
```

- DB のスキーマ・インデックスを変えるときはチームに一声かける
- 30 分詰まったら別の改善へ
- 計測結果（`~/analysis/`）は Git には入れない。Discord に投稿されたものをチームで見る

## 複数台構成にするとき

- サーバー別の設定は `etc/sN/etc/...` に置く（同じパスのファイルは common より優先）
- サーバー別の環境変数は `env/env.sN.sh`
- DB を分けたら `99-isucon.cnf` の `bind-address` を有効化し、アプリ側の DB ホストを変更
- 使わないサービスは止めて自動起動も切る（手元で。`s2` と `<サービス>` を置き換える）

  ```sh
  ssh s2 sudo systemctl disable --now <サービス>
  ```

## トラブル時

| 症状 | 確認すること（手元で。`s1` は該当サーバーに置き換える） |
|---|---|
| ベンチが失敗する | アプリのエラー：`ssh -t s1 make log`<br>nginx のエラー：`ssh s1 sudo tail -n 50 /var/log/nginx/error.log` |
| deploy で nginx がエラー | `ssh s1 sudo nginx -t` の出力を見る（反映前に止まるので nginx は古い設定のまま動いている） |
| 変更が反映されない | `ssh s1 make info` で SERVICE / BIN を確認、`ssh s1 git log --oneline -1` で最新か確認 |
| 壊れた | `git revert --no-edit HEAD && git push origin main && make deploy-all`。設定ファイルは `etc/common/` の最初のコミットが元の状態 |
