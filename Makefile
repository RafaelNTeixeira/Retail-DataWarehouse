.PHONY: setup requirements clean-data

setup:
	$(MAKE) requirements
	$(MAKE) clean-data

requirements:
	@echo "Installing Python dependencies for data processing..."
	pip3 install -r requirements.txt

clean-data:
	@echo "Cleaning up raw data..."
	python3 scripts/clean_data.py
