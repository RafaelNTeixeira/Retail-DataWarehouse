COMPOSE := docker compose -f superset/docker-compose-win.yml
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

manage-data:
	@echo "Installing Python dependencies for data processing..."
	pip install -r requirements.txt
	$(MAKE) clean-data

clean-data:
	@echo "Cleaning up raw data..."
	python3 scripts/clean_data.py

build:
	@echo "Building Superset service..."
	@$(COMPOSE) build --no-cache $(SERVICE_SUPERSET)

up:
	@echo "Starting Superset service..."
	@$(COMPOSE) up -d

down:
	@echo "Stopping Superset service..."
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
