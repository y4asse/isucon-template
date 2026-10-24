include config.mk

SHELL := /bin/bash
export PATH := $(HOME)/local/golang/bin:$(HOME)/go/bin:/usr/local/go/bin:$(PATH)
# scores.tsv やログ・解析フォルダ名の時刻を JST にする（サーバーのタイムゾーンはアプリや DB に影響するので変えない）
export TZ := Asia/Tokyo

# ----- 自動検出（config.mk で設定されていればそちらを優先） -----
SERVER_ID = $(shell cat .server_id 2>/dev/null)
SERVICE ?= $(shell systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $$1}' | grep -E '^isu.*[-.]$(APP_LANG)\.service$$' | head -1)
BIN ?= $(shell systemctl show -p ExecStart --value $(SERVICE) 2>/dev/null | sed -n 's/.*path=\([^ ;]*\).*/\1/p' | head -1)
BUILD_CMD ?= cd $(dir $(BIN)) && go build -o $(BIN) .
SHA = $(shell git rev-parse --short HEAD)
# 動いているコードの SHA（make deploy で記録。score のコミットで HEAD が進んでも変わらない）
DEPLOYED_SHA = $(shell cat .deployed_sha 2>/dev/null || git rev-parse --short HEAD)
TS = $(shell TZ=$(TZ) date +%m%d-%H%M%S)

.DEFAULT_GOAL := help

# ===== 開始直後 =====

.PHONY: setup
setup: ## ツール導入と git 設定（各サーバーで 1 回）
	sudo apt-get update
	sudo apt-get install -y percona-toolkit graphviz jq tree htop unzip
	ARCH=$$(dpkg --print-architecture); \
	curl -sSL -o /tmp/alp.tar.gz https://github.com/tkuchiki/alp/releases/download/v1.0.22/alp_linux_$${ARCH}.tar.gz && \
	tar -xzf /tmp/alp.tar.gz -C /tmp alp && sudo install /tmp/alp /usr/local/bin/alp && rm -f /tmp/alp /tmp/alp.tar.gz
	git config --global user.name "isucon-$(SERVER_ID)"
	git config --global user.email "isucon@example.com"
	git config --global pull.ff only
	mkdir -p ~/.ssh && ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
	@echo "== 検出結果 =="; echo "SERVER_ID=$(SERVER_ID) SERVICE=$(SERVICE) BIN=$(BIN)"

.PHONY: set-id
set-id: ## サーバー ID を設定（make set-id ID=s1）
	@test -n "$(ID)" || (echo "ID を指定してください: make set-id ID=s1"; exit 1)
	echo "$(ID)" > .server_id

.PHONY: snapshot
snapshot: check-server-id ## 初期状態を snapshots/sN/ に記録
	tools/snapshot.sh snapshots/$(SERVER_ID)

.PHONY: pull-conf
pull-conf: check-server-id ## /etc の設定と env.sh を etc/common/・env/ に取り込み（s1 で実行）
	@for p in $(CONF_PATHS); do \
	  case "$$p" in */) continue;; esac; \
	  if sudo test -e "$$p"; then \
	    mkdir -p "etc/common$$(dirname $$p)"; \
	    sudo cp -rL "$$p" "etc/common$$(dirname $$p)/"; \
	    echo "取得: $$p"; \
	  fi; \
	done
	sudo chown -R $$(id -u):$$(id -g) etc/common
	@if [ -f "$(ENV_FILE)" ] && [ ! -f env/env.common.sh ]; then cp "$(ENV_FILE)" env/env.common.sh; echo "取得: $(ENV_FILE)"; fi

.PHONY: ignore-langs
ignore-langs: ## 使わない言語の実装・ビルド成果物・10MB 超のファイルを gitignore
	@for d in go nodejs node ruby python php perl rust java kotlin dotnet csharp; do \
	  if [ "$$d" != "$(APP_LANG)" ] && [ -d "webapp/$$d" ]; then echo "/webapp/$$d/" >> .gitignore; fi; \
	done
	@if [ -n "$(BIN)" ]; then echo "/$$(realpath --relative-to=$(HOME) $(BIN))" >> .gitignore; fi
	@find webapp -type f -size +10M 2>/dev/null | sed 's|^|/|' >> .gitignore
	@awk '!seen[$$0]++' .gitignore > .gitignore.tmp && mv .gitignore.tmp .gitignore
	@echo "== .gitignore の自動追記分 =="; sed -n '/make ignore-langs が自動追記/,$$p' .gitignore

# ===== デプロイ =====

.PHONY: deploy
deploy: check-server-id ## pull → ビルド → 設定反映 → 再起動 → 通知
	git fetch origin
	git checkout $(BRANCH)
	git pull origin $(BRANCH)
	@# pull で Makefile が変わっていても新しい方で続きを実行する
	$(MAKE) --no-print-directory deploy-after-pull

.PHONY: deploy-after-pull
deploy-after-pull: build deploy-conf restart
	@echo $(SHA) > .deployed_sha
	@tools/notify.sh "deploy: $(BRANCH)@$(SHA)"

.PHONY: deploy-all
deploy-all: ## 【手元で実行】全サーバーで make deploy を並列実行
	@if [ -n "$$(git log origin/$(BRANCH)..$(BRANCH) 2>/dev/null)" ]; then echo "push していないコミットがあります"; exit 1; fi
	@for h in $(SERVERS); do \
	  ssh $$h "cd ~ && make deploy BRANCH=$(BRANCH)" 2>&1 | sed "s/^/[$$h] /" & \
	done; wait

all-%: ## 【手元で実行】全サーバーで make <target>（例: make all-bench-prep）
	@for h in $(SERVERS); do \
	  ssh $$h "cd ~ && make $*" 2>&1 | sed "s/^/[$$h] /" & \
	done; wait

.PHONY: build
build: ## アプリをビルド
	@test -n "$(BIN)" || (echo "BIN を検出できません。config.mk で設定してください"; exit 1)
	$(BUILD_CMD)

.PHONY: deploy-conf
deploy-conf: check-server-id ## etc/common → etc/sN の順に /etc へ反映し、変更があったものだけ reload
	tools/deploy-conf.sh $(SERVER_ID) "$(ENV_FILE)" "$(DB_SERVICE)"

.PHONY: restart
restart: ## 動いているアプリ・追加サービスを再起動
	@for s in $(SERVICE) $(EXTRA_SERVICES); do \
	  if systemctl is-active --quiet $$s; then sudo systemctl restart $$s && echo "restart: $$s"; fi; \
	done

# ===== ベンチ =====

.PHONY: bench-prep
bench-prep: check-server-id ## ログ退避・SQL 統計リセット・スロークエリログ ON
	tools/rotate-logs.sh "$(NGINX_LOG)" "$(SLOW_LOG)" "$(DB_SERVICE)"
	@if systemctl is-active --quiet $(DB_SERVICE); then \
	  echo "SET GLOBAL slow_query_log_file='$(SLOW_LOG)'; SET GLOBAL long_query_time=0; SET GLOBAL slow_query_log=ON; TRUNCATE performance_schema.events_statements_summary_by_digest;" | sudo mysql && echo "slow log: ON"; \
	fi
	@tools/notify.sh "bench-prep: $(BRANCH)@$(DEPLOYED_SHA)"

.PHONY: log
log: ## アプリのログを tail（ベンチ中に別ペインで）
	sudo journalctl -u $(SERVICE) -n 30 -f

# ===== ベンチ後 =====

.PHONY: analyze
analyze: check-server-id ## alp / pt-query-digest / SQL digest を analysis/ に保存して Discord へ
	$(eval OUT := $(HOME)/analysis/$(TS)-$(DEPLOYED_SHA)-$(SERVER_ID))
	mkdir -p $(OUT)
	@if sudo test -s $(NGINX_LOG); then sudo alp ltsv --config tools/alp.yml --file $(NGINX_LOG) > $(OUT)/alp.txt; fi
	@if sudo test -s $(SLOW_LOG); then sudo pt-query-digest $(SLOW_LOG) > $(OUT)/slow.txt 2>/dev/null; fi
	@if systemctl is-active --quiet $(DB_SERVICE); then sudo mysql -t < tools/sql-digest.sql > $(OUT)/sql-digest.txt 2>&1; fi
	@ls $(OUT)/* >/dev/null 2>&1 || (echo "解析対象のログがありません"; exit 0)
	@test ! -f $(OUT)/alp.txt || head -n 25 $(OUT)/alp.txt
	@echo "保存先: $(OUT)"
	@tools/notify.sh "analyze: $(BRANCH)@$(DEPLOYED_SHA)" $(OUT)/*.txt

.PHONY: score
score: ## スコアを記録（make score S=12345 M="メモ"）
	@test -n "$(S)" || (echo 'make score S=12345 M="メモ"'; exit 1)
	$(eval DEPLOYED := $(DEPLOYED_SHA))
	git pull --rebase --autostash origin $(BRANCH)
	printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$$(date '+%F %T')" "$(SERVER_ID)" "$(BRANCH)" "$(DEPLOYED)" "$(S)" "$(M)" >> scores.tsv
	git add scores.tsv && git commit -q -m "score: $(S) $(M)" && (git push -q origin HEAD:$(BRANCH) || echo "push に失敗しました。あとで git push してください")
	@tools/notify.sh "score: $(S) ($(BRANCH)@$(DEPLOYED)) $(M)"

.PHONY: pprof
pprof: ## pprof を 60 秒取得して ~/pprof/ に保存
	mkdir -p ~/pprof
	go tool pprof -proto -seconds 60 http://localhost:$(PPROF_PORT)/debug/pprof/profile > ~/pprof/$(TS)-$(DEPLOYED_SHA).pb.gz
	@echo "保存先: ~/pprof/$(TS)-$(DEPLOYED_SHA).pb.gz（make pprof-web で表示）"

.PHONY: pprof-web
pprof-web: ## 最新の pprof を :8090 で表示（手元で ssh -L 8090:localhost:8090）
	-@fuser -k 8090/tcp 2>/dev/null
	go tool pprof -http=localhost:8090 $$(ls -t ~/pprof/*.pb.gz | head -1)

# ===== 終盤 =====

.PHONY: finalize
finalize: ## スロークエリログ OFF と、提出前チェック
	@if systemctl is-active --quiet $(DB_SERVICE); then echo "SET GLOBAL slow_query_log=OFF;" | sudo mysql && echo "✓ slow log: OFF"; fi
	@if grep -rqsE '^\s*access_log\s+[^o;][^;]*;' /etc/nginx/; then echo "✗ nginx の access_log が有効です（etc/common/etc/nginx/conf.d/00-isucon-log.conf の access_log を off; にして deploy）"; grep -rnsE '^\s*access_log\s' /etc/nginx/; else echo "✓ nginx access_log: off"; fi
	@if grep -rqsE 'net/http/pprof|fgprof' webapp/ 2>/dev/null; then echo "✗ pprof のコードが残っています"; grep -rlsE 'net/http/pprof|fgprof' webapp/; else echo "✓ pprof: なし"; fi
	@for s in $(SERVICE) nginx $(DB_SERVICE) $(EXTRA_SERVICES); do printf '  %-28s active=%-9s enabled=%s\n' $$s "$$(systemctl is-active $$s)" "$$(systemctl is-enabled $$s 2>/dev/null)"; done
	@echo
	@echo "残りのチェック（全サーバー）:"
	@echo "  [ ] 使うサービスが enabled、使わないサービスが disabled になっている"
	@echo "  [ ] sudo reboot → 再起動後にアプリが動き、ベンチ前のデータが残っている"
	@echo "  [ ] 最終ベンチ"

# ===== ユーティリティ =====

.PHONY: mysql
mysql: ## MySQL に接続
	mysql -h $(MYSQL_HOST) -P $(MYSQL_PORT) -u $(MYSQL_USER) -p$(MYSQL_PASS) $(MYSQL_DB)

.PHONY: info
info: ## 検出・設定値を表示
	@echo "SERVER_ID=$(SERVER_ID)"; echo "SERVICE=$(SERVICE)"; echo "BIN=$(BIN)"; echo "BUILD_CMD=$(BUILD_CMD)"; echo "BRANCH=$(BRANCH) SHA=$(SHA) DEPLOYED_SHA=$(DEPLOYED_SHA)"

.PHONY: check-server-id
check-server-id:
	@test -n "$(SERVER_ID)" || (echo "サーバー ID が未設定です: make set-id ID=s1"; exit 1)

.PHONY: help
help: ## コマンド一覧
	@grep -hE '^[a-zA-Z_%-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
