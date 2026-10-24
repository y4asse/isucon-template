# isucon14-practice

ISUCON14（ISURIDE）の練習用リポジトリ。
構成は [traP-isucon-newbie-handson2022](https://github.com/oribe1115/traP-isucon-newbie-handson2022) を参考にしている。

> [!WARNING]
> このリポジトリは private のまま運用する（本番の ISUCON では競技中のコード公開は禁止）。

## ディレクトリ構成（予定）

```
.
├── Makefile             # 当日の操作をまとめたもの
├── env.sh               # サーバーごとの環境変数（SERVER_ID など）
├── s1/ s2/ s3/          # サーバーごとの設定ファイル（サーバーと同じパス構造）
│   ├── etc/mysql/
│   ├── etc/nginx/
│   ├── etc/systemd/system/
│   └── home/isucon/
├── tool-config/
│   └── alp/config.yml   # alp の URI 集約設定
├── webapp/              # 当日サーバーから取得したアプリ
├── scores.md            # ベンチスコアの記録（make bench で自動追記）
└── logs/                # 計測結果（alp / pt-query-digest）の保存先
```

## 当日の流れ

### 1. サーバーの準備（各サーバーで実施）

```sh
# 1. Deploy key を作成して GitHub に登録（Settings > Deploy keys、Allow write access にチェック）
ssh-keygen -t ed25519 -C "isucon-s1"
cat ~/.ssh/id_ed25519.pub

# 2. ホームディレクトリをこのリポジトリと紐付ける
cd ~
git init
git remote add origin git@github.com:y4asse/isucon14-practice.git
git fetch origin main
git reset origin/main   # 既存ファイルは残したまま履歴だけ取り込む
git checkout -- Makefile tool-config

# 3. サーバー ID を設定してツールを入れる
make set-as-s1          # s2 / s3 のサーバーではそれぞれ set-as-s2 / set-as-s3
make setup
```

### 2. 初期状態をコミット

```sh
make get-conf           # /etc の設定ファイルを s1/ 以下にコピー
git add .
git commit -m "初期状態"
git push origin main
```

`webapp/` もこのタイミングでコミットする。

### 3. 計測の準備

- nginx のログ形式を LTSV に変更（`s1/etc/nginx/nginx.conf`）
- MySQL のスロークエリログを有効化（`s1/etc/mysql/...`）
- `make deploy-conf` で反映

### 4. 改善サイクル

```
改善する → make bench → ベンチマーク実行 → make alp / make slow-query → 次の改善へ
```

| コマンド | 内容 |
|---|---|
| `make bench` | ログ退避 → ビルド → 設定反映 → 再起動（ベンチ直前に実行） |
| `make alp` | アクセスログを集計して遅いエンドポイントを確認 |
| `make slow-query` | スロークエリを集計して遅い SQL を確認 |
| `make pprof-record` | pprof でプロファイルを取得 |
| `make access-db` | MySQL に接続 |

ルール：

- 1 つ変えたら必ずベンチを回して `scores.md` に記録
- 変更は小さくコミット。スコアが下がったら戻す
- 30 分詰まったら別の改善へ移る

### 5. 仕上げ（終了 30 分前）

- [ ] nginx のアクセスログ・スロークエリログを OFF にする
- [ ] pprof を外す
- [ ] 全サーバーを再起動しても動くことを確認
- [ ] 最終ベンチ

## ISUCON14 メモ（当日確認して埋める）

| 項目 | 値 |
|---|---|
| 言語 | Go |
| サービス名 | `isuride-go.service`（要確認：`systemctl list-units \| grep isu`） |
| DB | MySQL（バージョン要確認） |
| スロークエリログのパス | |
| 初期スコア | |

## 参考

- [ISUCON14 公式リポジトリ](https://github.com/isucon/isucon14)
- [traP ISUCON 講習会テキスト](https://isucon-workshop.trap.show/text/chapter-0/index.html)
- [traP-isucon-newbie-handson2022](https://github.com/oribe1115/traP-isucon-newbie-handson2022)
