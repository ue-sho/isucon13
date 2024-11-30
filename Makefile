include env
ENV_FILE:=env

USER:=isucon
SERVICE_NAME:=isupipe-go.service

DB_PATH:=/etc/mysql
MYSQL_LOG:=/var/log/mysql/slow.log

NGINX_PATH:=/etc/nginx
NGINX_LOG:=/var/log/nginx/access.log

PROJECT_ROOT:=/home/isucon
BUILD_DIR:=/home/isucon/webapp/go

ALP_LOG:=/home/isucon/logs/alp.txt
PT_QUERY_LOG:=/home/isucon/logs/pt-query-digest.txt


# アプリケーションのみ再起動
.PHONY: restart
restart:
	sudo systemctl daemon-reload
	sudo systemctl restart $(SERVICE_NAME)

# ベンチマーク実行する前に実行する。デプロイして再起動する。
.PHONY: bench
bench: check-server-id deploy-conf log-truncate restart watch-service-log

# DB, nginxをデプロイする
.PHONY: deploy-conf
deploy-conf: deploy-db-conf deploy-nginx-conf deploy-env

# アプリケーションのログを見る
.PHONY: watch-service-log
watch-service-log:
	sudo journalctl -u $(SERVICE_NAME) -n10 -f

# alp, pt-query-digestを実行する
.PHONY: analyse
analyse: slow alp

# alp, pt-query-digestを実行してslackに通知する
.PHONY: analyse-slack
analyse-slack: slow-slack alp-slack
	git branch --contains=HEAD | notify_slack
	git log -n 1 --pretty=format:"コミットハッシュ: %h , コミットログ: %s" | notify_slack
	echo "---------- analyse done! ----------" | notify_slack

# ログをローテートする
.PHONY: log-truncate
log-truncate:
	$(eval when := $(shell date "+%s"))
	mkdir -p ~/logs/$(when)
	sudo touch $(NGINX_LOG);
	sudo mv -f $(NGINX_LOG) ~/logs/$(when)/ ;
	sudo touch $(MYSQL_LOG);
	sudo mv -f $(MYSQL_LOG) ~/logs/$(when)/ ;
	sudo systemctl restart nginx
	sudo systemctl restart mysql

# DBへアクセスする
.PHONY: access-db
access-db:
	mysql -h $(ISUCON_DB_HOST) -P $(ISUCON_DB_PORT) -u $(ISUCON_DB_USER) -p$(ISUCON_DB_PASSWORD) $(ISUCON_DB_NAME)

# サーバーとgitのセットアップをする
.PHONY: setup
setup: install-tool get-db-conf get-nginx-conf git-setup get-env

# pt-query-digestを実行する
.PHONY: slow
slow:
	sudo pt-query-digest $(MYSQL_LOG)

# pt-query-digestを実行してslackに通知する
.PHONY: slow-slack
slow-slack:
	sudo pt-query-digest $(MYSQL_LOG) > $(PT_QUERY_LOG)
	notify_slack $(PT_QUERY_LOG)

# alpを実行する
.PHONY: alp
alp:
	sudo alp ltsv --file=$(NGINX_LOG) --config=/home/isucon/tool/alp/config.yml

# alpを実行してslackに通知する
.PHONY: alp-slack
alp-slack:
	sudo alp ltsv --file=$(NGINX_LOG) --config=/home/isucon/tool/alp/config.yml > $(ALP_LOG)
	notify_slack $(ALP_LOG)

# ツールをインストールする
.PHONY: install-tool
install-tool:
	sudo apt-get update
	sudo apt-get install htop unzip jq

	# pt-query-digest
	wget https://github.com/percona/percona-toolkit/archive/refs/tags/v3.5.5.tar.gz
	tar zxvf v3.5.5.tar.gz
	sudo install ./percona-toolkit-3.5.5/bin/pt-query-digest /usr/local/bin
	# alp
	wget https://github.com/tkuchiki/alp/releases/download/v1.0.11/alp_linux_amd64.zip
	unzip alp_linux_amd64.zip
	sudo mv alp /usr/local/bin/
	# notify_slack
	wget https://github.com/catatsuy/notify_slack/releases/download/v0.4.14/notify_slack-linux-amd64.tar.gz
	tar zxvf notify_slack-linux-amd64.tar.gz
	sudo mv notify_slack /usr/local/bin/

	rm -rf v3.5.5.tar.gz percona-toolkit-3.5.5 alp_linux_amd64.zip notify_slack-linux-amd64.tar.gz LICENSE README.md CHANGELOG.md

# gitのセットアップをする
.PHONY: git-setup
git-setup:
	git config --global user.email "tssu45@gmail.com"
	git config --global user.name "ue-sho"

# サーバー1にIDを設定する
.PHONY: set-as-s1
set-as-s1:
	echo "SERVER_ID=s1" >> $(ENV_FILE)

# サーバー2にIDを設定する
.PHONY: set-as-s2
set-as-s2:
	echo "SERVER_ID=s2" >> $(ENV_FILE)

# サーバー3にIDを設定する
.PHONY: set-as-s3
set-as-s3:
	echo "SERVER_ID=s3" >> $(ENV_FILE)

# DBの設定をgitに含められるようにhomeにコピーする
.PHONY: get-db-conf
get-db-conf:
	mkdir -p /home/isucon/$(SERVER_ID)/etc/mysql
	mkdir -p /home/isucon/backup/etc
	sudo cp -r /etc/mysql /home/isucon/backup/etc
	sudo cp -R $(DB_PATH)/* ~/$(SERVER_ID)/etc/mysql
	sudo chown $(USER) -R ~/$(SERVER_ID)/etc/mysql

# nginxの設定をgitに含められるようにhomeにコピーする
.PHONY: get-nginx-conf
get-nginx-conf:
	mkdir -p /home/isucon/$(SERVER_ID)/etc/nginx
	mkdir -p /home/isucon/backup/etc
	cp -r /etc/nginx /home/isucon/backup/etc
	sudo cp -R $(NGINX_PATH)/* ~/$(SERVER_ID)/etc/nginx
	sudo chown $(USER) -R ~/$(SERVER_ID)/etc/nginx

# 環境変数をgitに含められるようにhomeにコピーする
.PHONY: get-env
get-env:
	mkdir -p  ~/$(SERVER_ID)/home/isucon
	ln ~/$(ENV_FILE) ~/$(SERVER_ID)/home/isucon/$(ENV_FILE)

# DBの設定をデプロイする
.PHONY: deploy-db-conf
deploy-db-conf:
	sudo cp -R ~/$(SERVER_ID)/etc/mysql/* $(DB_PATH)

# nginxの設定をデプロイする
.PHONY: deploy-nginx-conf
deploy-nginx-conf:
	sudo cp -R ~/$(SERVER_ID)/etc/nginx/* $(NGINX_PATH)

# 環境変数をデプロイする
.PHONY: deploy-env
deploy-envsh:
	cp ~/$(SERVER_ID)/home/isucon/$(ENV_FILE) ~/$(ENV_FILE)

# server id を確認する
.PHONY: check-server-id
check-server-id:
ifdef SERVER_ID
	@echo "SERVER_ID=$(SERVER_ID)"
else
	@echo "SERVER_ID is unset"
	@exit 1
endif

# サーバースペックを確認する
.SILENT: mspec
mspec:
	(grep processor /proc/cpuinfo; free -m)