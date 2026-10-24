# isucon-template

ISUCON 用のテンプレートリポジトリ。お題に依存しない仕組みだけを置き、大会・練習ごとにここから private リポジトリを作って使う。

> [!WARNING]
> - このテンプレートから作ったリポジトリは **必ず private** にする（競技中のコード公開は禁止）。
> - Webhook URL などの秘密情報は `.env`（gitignore 済み）に書き、コミットしない。

## 方針

- 各サーバーの `/home/isucon` をそのまま git root にする
- デプロイは各サーバー上で `make deploy`。全台まとめて反映したいときは手元から `make deploy-all`
- `/etc` の設定は **コピーで反映**（symlink は使わない）。全台共通 `etc/common/` の上に、サーバー別 `etc/sN/` を上書き
- お題ごとに変わる値は `config.mk` だけに集める
- 計測結果はまずファイルに保存してコミット。Discord 通知は失敗しても止まらない best-effort
- スコアは必ずコミット SHA とメモ付きで `scores.tsv` に残す
- 計測用の別サーバー（pprotein など）は置かない（負荷と envcheck 失格のリスク）

## ディレクトリ構成

```
/home/isucon/                  # git root
├── Makefile                   # 共通処理（お題が変わっても編集しない）
├── config.mk                  # ★当日編集：サービス名・ビルド先・サーバー IP など
├── .env.example               # DISCORD_WEBHOOK_URL など（コピーして .env を作る）
├── etc/
│   ├── common/etc/...         # 全台共通の nginx / mysql / systemd / sysctl 設定
│   └── s1/ s2/ s3/etc/...     # サーバー別の差分（置いたファイルだけ common を上書き）
├── env/
│   ├── env.common.sh          # アプリの環境変数（全台共通）
│   └── env.s1.sh ...          # サーバー別の差分 → deploy 時に結合して ~/env.sh へ
├── tools/
│   ├── alp.yml                # alp 設定（matching_groups は当日書き換え）
│   ├── rotate-logs.sh         # ベンチ前のログ退避
│   ├── notify.sh              # Discord 通知（best-effort）
│   ├── snapshot.sh            # 初期状態の記録
│   └── whoami.sh              # 自分が s1〜s3 のどれか判定
├── snapshots/sN/              # 初期状態（dpkg / systemctl / ps / cpuinfo / meminfo）
├── webapp/                    # 使わない言語の実装は自動で gitignore
├── analysis/<時刻>-<SHA>/     # 計測結果（alp / slow query / SQL digest）
├── logs/                      # 退避したログ（gitignore）
├── scores.tsv                 # 時刻・SHA・スコア・メモ
└── docs/runbook.md            # 当日の手順書
```

## make コマンド

| タイミング | コマンド | 内容 |
|---|---|---|
| 開始直後 | `make setup` | alp / pt-query-digest などのツール導入、git 設定 |
| | `make git-init` | 1 台目：`git init` して初回 push。2 台目以降：fetch + reset |
| | `make snapshot` | 初期状態を `snapshots/sN/` に記録 |
| | `make pull-conf` | `/etc` の設定を `etc/sN/` に取り込み（元ファイルは `.orig` で退避） |
| 改善のたび | `make deploy` | pull → ビルド → 設定反映（`nginx -t` 確認付き） → 動いているサービスだけ再起動 → 通知 |
| | `make deploy-all` | 手元から全サーバーに `make deploy` を並列実行 |
| ベンチ前 | `make bench-prep` | ログ退避、SQL 統計リセット、スロークエリログ ON |
| ベンチ中 | `make log` | アプリのログを tail（別ペインで） |
| ベンチ後 | `make analyze` | alp / pt-query-digest / SQL digest を `analysis/` に保存して Discord へ |
| | `make score S=12345 M="メモ"` | `scores.tsv` に 1 行追記 |
| | `make pprof` | pprof を取得 |
| 終盤 | `make finalize` | ログ・計測を OFF にし、再起動テストのチェックリストを表示 |
| いつでも | `make mysql` / `make help` | DB 接続 / コマンド一覧 |

## 新しい大会・練習を始めるとき

### 前日まで

1. GitHub で **Use this template** → private リポジトリを作成
2. Deploy key 用の鍵を作り、リポジトリに登録（Allow write access にチェック）
3. 手元の `~/.ssh/config` に `s1` `s2` `s3` を書けるようにしておく（IP は当日）
4. `.env.example` をコピーして `.env` を作り、`DISCORD_WEBHOOK_URL` を設定
5. `docs/runbook.md` を読んで役割分担を決める

### 当日（最初の 30 分）

```sh
# 各サーバーで
make setup
make git-init        # 1 台目 → 2 台目以降の順
make snapshot
make pull-conf
git add . && git commit -m "初期状態" && git push
```

その後 `config.mk` を埋め、nginx のログ形式（LTSV）とスロークエリログを設定して `make deploy`。

### 改善サイクル

```
改善してコミット → make deploy → make bench-prep → ベンチ実行 → make score → make analyze → 次へ
```

- 1 コミット 1 目的。スコアが下がったら revert
- インデックス追加など DB を変える作業はチームに一声かける
- 30 分詰まったら別の改善へ

### 終了 1 時間前

- [ ] `make finalize` でログと計測を止める
- [ ] pprof などの計測コードを外す
- [ ] 全サーバーを再起動して、アプリが起動し、データが残っていることを確認
- [ ] 最終ベンチ

## 参考にしたもの

- [takonomura/isucon14](https://github.com/takonomura/isucon14)（ISUCON14 優勝）
- [narusejun/isucon13-final](https://github.com/narusejun/isucon13-final)（ISUCON13 優勝）
- [oribe1115/traP-isucon-newbie-handson2022](https://github.com/oribe1115/traP-isucon-newbie-handson2022)
- [Yuhi-Sato/isucon-ruby-ready](https://github.com/Yuhi-Sato/isucon-ruby-ready)
- [traP ISUCON14 参加記](https://trap.jp/post/2427/)
- [ISUCON チートシート](https://hackmd.io/@to-hutohu/SJuUqzdsc)
- [traP ISUCON 講習会テキスト](https://isucon-workshop.trap.show/text/chapter-0/index.html)
