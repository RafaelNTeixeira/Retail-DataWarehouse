.PHONY: build up down restart ps logs logs-superset init clean-data setup

setup:
	$(MAKE) manage-data

manage-data:
	@echo "Installing Python dependencies for data processing..."
	pip install -r requirements.txt
	$(MAKE) clean-data

clean-data:
	@echo "Cleaning up raw data..."
	python3 scripts/clean_data.py
