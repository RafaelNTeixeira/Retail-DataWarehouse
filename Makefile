COMPOSE := docker compose -f superset/docker-compose.yml
SERVICE_SUPERSET := superset
SERVICE_MYSQL := mysql

ADMIN_USER ?= admin
ADMIN_PASS ?= admin
ADMIN_EMAIL ?= admin@example.com

.PHONY: build up down restart ps logs logs-superset init clean-data setup

setup:
	$(MAKE) build
	$(MAKE) up
	$(MAKE) init

clean-data:
	python3 scripts/clean_data.py

build:
	@$(COMPOSE) build --no-cache $(SERVICE_SUPERSET)

up:
	@$(COMPOSE) up -d

down:
	@$(COMPOSE) down -v

restart:
	@$(COMPOSE) restart

ps:
	@$(COMPOSE) ps

logs:
	@$(COMPOSE) logs -f

logs-superset:
	@$(COMPOSE) logs -f $(SERVICE_SUPERSET)

init:
	@echo "Running migrations..."
	@$(COMPOSE) exec -T $(SERVICE_SUPERSET) superset db upgrade
	@echo "Creating admin user (may fail if already exists)…"
	@$(COMPOSE) exec -T $(SERVICE_SUPERSET) superset fab create-admin --username $(ADMIN_USER) --password $(ADMIN_PASS) --firstname Admin --lastname User --email $(ADMIN_EMAIL) || true
	@echo "Initializing superset…"
	@$(COMPOSE) exec -T $(SERVICE_SUPERSET) superset init
