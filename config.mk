# ===== お題ごとに当日編集する値 =====
# 空欄やコメントアウトのままなら Makefile 側で自動検出 or デフォルト値を使う

# 手元から deploy-all するときのサーバー（~/.ssh/config の Host 名）
SERVERS := s1 s2 s3

# デプロイするブランチ
BRANCH ?= main

# 実装言語（make ignore-langs で他言語のディレクトリを gitignore するのに使う）
APP_LANG := go

# アプリの systemd サービス名（未設定なら isu*-go.service / isu*.go.service を自動検出）
# SERVICE := isuride-go.service

# ビルド（未設定なら systemd の ExecStart からバイナリパスを取って go build）
# BIN := /home/isucon/webapp/go/isuride
# BUILD_CMD := cd /home/isucon/webapp/go && go build -o isuride .

# DB
DB_SERVICE := mysql
MYSQL_HOST := 127.0.0.1
MYSQL_PORT := 3306
MYSQL_USER := isucon
MYSQL_PASS := isucon
MYSQL_DB   :=

# その他 deploy 時に「動いていれば再起動」するサービス（redis, memcached など）
EXTRA_SERVICES :=

# ログ
NGINX_LOG := /var/log/nginx/access.log
SLOW_LOG  := /var/log/mysql/mysql-slow.log

# make pull-conf で取り込む設定（ファイル or ディレクトリ）
CONF_PATHS = /etc/nginx/nginx.conf /etc/nginx/sites-available /etc/nginx/conf.d \
             /etc/mysql/mysql.conf.d /etc/systemd/system/$(SERVICE)

# アプリの環境変数ファイル（systemd の EnvironmentFile）
ENV_FILE := $(HOME)/env.sh

# pprof
PPROF_PORT := 6060
