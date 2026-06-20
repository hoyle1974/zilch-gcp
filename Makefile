.PHONY: install install-dev test lint clean help

help:
	@echo "Zilch Development Commands"
	@echo ""
	@echo "  make install         - Install runtime dependencies"
	@echo "  make install-dev     - Install development dependencies"
	@echo "  make test            - Run tests"
	@echo "  make test-coverage   - Run tests with coverage report"
	@echo "  make lint            - Check code style"
	@echo "  make clean           - Remove build artifacts"
	@echo ""
	@echo "Usage:"
	@echo "  python3 zilch.py deploy [--auto]"
	@echo "  python3 zilch.py teardown [--force]"
	@echo "  python3 zilch.py status"

install:
	pip install -r requirements.txt

install-dev:
	pip install -r requirements-dev.txt

test:
	pytest tests/ -v

test-coverage:
	pytest tests/ --cov=. --cov-report=html --cov-report=term

lint:
	python3 -m pytest tests/ -v --tb=short

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete
	rm -rf .pytest_cache
	rm -rf htmlcov
	rm -rf .coverage
