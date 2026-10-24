# isucon-template

ISUCON 用のテンプレートリポジトリ。お題に依存しない仕組みだけを置き、大会・練習ごとにここから private リポジトリを作って使う。

> [!WARNING]
> - このテンプレートから作ったリポジトリは **必ず private** にする（競技中のコード公開は禁止）。
> - Webhook URL などの秘密情報は `.env`（gitignore 済み）に書き、コミットしない。

## 方針

- 各サーバーの `/home/isucon` をそのまま git root にする（`.gitignore` は許可リスト方式なので `.ssh` などは入らない）
- デプロイは各サーバー上で `make deploy`。全台まとめてなら手元から `make deploy-all`
- `/etc` の設定は **コピーで反映**（symlink は使わない）。全台共通 `etc/common/` に、サーバー別 `etc/sN/` が同じパスなら優先
- 設定ファイルは変更があったものだけ reload / restart（nginx は `nginx -t` が通らなければ中断）
- お題ごとに変わる値は `config.mk` だけに集める。サービス名とバイナリは systemd から自動検出
- 計測結果は各サーバーの `~/analysis/` に保存（Git には入れない）し、Discord に添付で投稿。通知は失敗しても止まらない
- スコアは必ずコミット SHA とメモ付きで `scores.tsv` に残す
- 計測用の別サーバー（pprotein など）は置かない（負荷と envcheck 失格のリスク）

## ディレクトリ構成

```
/home/isucon/                  # git root
├── Makefile                   # 共通処理（お題が変わっても編集しない）
├── config.mk                  # ★当日編集：サーバー一覧・DB・ログのパスなど
├── .env.example               # DISCORD_WEBHOOK_URL（コピーして .env を作る。.env は Git 管理外）
├── etc/
│   ├── common/etc/...         # 全台共通（中身は下の「etc/ の中身」）
│   └── s1/ s2/ s3/etc/...     # サーバー別（同じパスなら common より優先）
├── env/
│   ├── env.common.sh          # アプリの環境変数（make pull-conf で ~/env.sh から取り込み）
│   └── env.sN.sh              # サーバー別の追加分 → deploy 時に結合して ~/env.sh へ
├── tools/
│   ├── deploy-conf.sh         # etc/ → /etc への反映と reload
│   ├── rotate-logs.sh         # ベンチ前のログ退避
│   ├── notify.sh              # Discord 通知（ファイル添付対応）
│   ├── snapshot.sh            # 初期状態の記録
│   ├── alp.yml                # alp 設定（matching_groups は当日書き換え）
│   └── sql-digest.sql         # performance_schema の SQL 集計
├── snapshots/sN/              # 初期状態（サービス一覧・ポート・パッケージなど）
├── webapp/                    # 使わない言語の実装は make ignore-langs で gitignore
├── scores.tsv                 # 時刻・サーバー・ブランチ・SHA・スコア・メモ
└── docs/runbook.md            # 手順書（前日の準備・役割分担・時間配分・セットアップ・トラブル対応）

# Git 管理外
~/.server_id                   # make set-id で作成
~/analysis/<時刻>-<SHA>-sN/    # make analyze の結果
~/logs/<時刻>/                 # make bench-prep で退避したログ
```

## etc/ の中身

`etc/common/etc/` には出どころの違うファイルが混ざる。**ファイル名に `isucon` が入っているものがテンプレート製**、それ以外は `make pull-conf` で `/etc` から取り込んだお題の設定。

```
etc/common/etc/
├── nginx/
│   ├── conf.d/00-isucon-log.conf     ← テンプレート（LTSV ログ形式と access_log）
│   ├── nginx.conf                    ← pull-conf
│   └── sites-available/*             ← pull-conf
├── mysql/mysql.conf.d/
│   ├── 99-isucon.cnf                 ← テンプレート（mysqld.cnf より後に読まれて上書き）
│   └── mysqld.cnf, mysql.cnf         ← pull-conf
├── sysctl.d/99-isucon.conf           ← テンプレート（接続数の上限引き上げ）
└── systemd/system/<アプリ>.service    ← pull-conf
```

- テンプレート製のファイルは `/etc` にない名前なので、`pull-conf` で上書きされない
- `make deploy` は出どころに関係なく、`etc/common/` → `etc/sN/` の順に全ファイルを `/etc` へコピーし、変更があったものだけ reload / restart する
- 競技中はどちらも直接編集してよい。設定を足すときは元のファイルより、テンプレート製のファイル（後から読まれて上書きする）に書くほうが差分が小さい

## make コマンド

| タイミング | コマンド | 内容 |
|---|---|---|
| 開始直後 | `make set-id ID=s1` | サーバー ID を設定 |
| | `make setup` | alp / pt-query-digest などのツール導入、git 設定 |
| | `make snapshot` | 初期状態を `snapshots/sN/` に記録 |
| | `make pull-conf` | `/etc` の設定と `env.sh` を取り込み（s1 で） |
| | `make ignore-langs` | 使わない言語・ビルド成果物・10MB 超のファイルを gitignore |
| 改善のたび | `make deploy` | pull → ビルド → 設定反映 → 動いているサービスだけ再起動 → 通知 |
| | `make deploy-all` | 【手元】全サーバーで `make deploy`（未 push なら中断） |
| ベンチ前 | `make bench-prep` | ログ退避、SQL 統計リセット、スロークエリログ ON |
| ベンチ中 | `make log` | アプリのログを tail |
| ベンチ後 | `make score S=12345 M="メモ"` | `scores.tsv` に追記して push |
| | `make analyze` | alp / pt-query-digest / SQL 集計を保存して Discord へ |
| | `make pprof` / `make pprof-web` | pprof を取得 / ブラウザで表示 |
| 終盤 | `make finalize` | スロークエリログ OFF と提出前チェック |
| いつでも | `make all-<target>` | 【手元】全サーバーで任意のコマンド（例：`make all-bench-prep`） |
| | `make info` / `make mysql` / `make help` | 検出値の表示 / DB 接続 / 一覧 |

## 新しい大会・練習を始めるとき

前日の準備から当日の流れまで、すべて [docs/runbook.md](docs/runbook.md) に沿って進める。

```
前日の準備 → セットアップ（30 分）→ 初回ベンチ → 改善サイクル → 17:00 finalize → 再起動テスト → 最終ベンチ
```

## 参考にしたもの

- [takonomura/isucon14](https://github.com/takonomura/isucon14)（ISUCON14 優勝）
- [narusejun/isucon13-final](https://github.com/narusejun/isucon13-final)（ISUCON13 優勝）
- [oribe1115/traP-isucon-newbie-handson2022](https://github.com/oribe1115/traP-isucon-newbie-handson2022)
- [Yuhi-Sato/isucon-ruby-ready](https://github.com/Yuhi-Sato/isucon-ruby-ready)
- [traP ISUCON14 参加記](https://trap.jp/post/2427/)
- [ISUCON チートシート](https://hackmd.io/@to-hutohu/SJuUqzdsc)
- [traP ISUCON 講習会テキスト](https://isucon-workshop.trap.show/text/chapter-0/index.html)
