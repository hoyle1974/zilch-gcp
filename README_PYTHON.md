# Zilch Python Implementation (Beta)

This is the **new Python-based implementation** of the Zilch deployment tool. It replaces the bash scripts with a more maintainable, testable, and type-safe Python CLI.

## Why Python?

The original `deploy.sh` (1,356 lines) and `teardown.sh` (318 lines) are now refactored into modular Python code with:

- **Type safety** via Pydantic config validation
- **Better error handling** with custom exceptions and user-friendly messages  
- **Testable code** with >80% coverage (pytest)
- **Cleaner orchestration** using Click for CLI and ThreadPoolExecutor for parallel operations
- **Same zero-install experience** in Cloud Shell (Python pre-installed)

## Quick Start

### Prerequisites

- Google Cloud SDK (`gcloud` CLI)
- Terraform
- Python 3.8+ (pre-installed in Cloud Shell)

### Installation

```bash
# Install dependencies (one-time)
pip install -r requirements.txt

# OR use the Makefile
make install
```

### Deployment

```bash
# Interactive mode (prompts for configuration)
python3 zilch.py deploy

# Auto mode (uses existing .zilch.config)
python3 zilch.py deploy --auto

# Teardown infrastructure
python3 zilch.py teardown [--force]

# Check deployment status
python3 zilch.py status
```

## Module Structure

```
zilch.py           # Main entry point (commands: deploy, teardown, status)
├── config.py      # Configuration management (Pydantic models)
├── cli.py         # Interactive prompts (Click)
├── gcp.py         # GCP validation and operations
├── terraform.py   # Terraform orchestration
├── health_check.py # Post-deployment checks
└── output.py      # Formatting and output
```

### Key Classes

**`config.py`**
- `ZilchConfig`: Pydantic model for all configuration
  - Type-safe fields with validation
  - `load_from_file()`, `save_to_file()`, `to_terraform_vars()`

**`gcp.py`**
- `GCPError`: Exception for GCP operations
- `check_required_tools()`: Verify gcloud, terraform, etc.
- `validate_gcloud_auth()`: Check authentication
- `validate_project()`, `validate_iam_permissions()`: Verify access
- `create_state_bucket()`: Setup Terraform state storage
- Resource permission checks and setup

**`terraform.py`**
- `TerraformExecutor`: Execute Terraform commands
  - `init()`, `apply()`, `destroy()`, `list_resources()`, `get_output()`
  - `import_resource()`: Import pre-existing resources
- `ParallelImporter`: Import resources in parallel with error tracking

**`cli.py`**
- Interactive prompt functions (using Click)
- `get_project_id()`, `get_app_name()`, `get_region()`
- `get_services_interactive()`: Interactive arrow-key service menu with toggles
- `get_scheduler_config()`, `get_monitoring_config()`

**`health_check.py`**
- `check_cloud_run_health()`: Verify Cloud Run endpoint responsiveness

## Configuration

Configuration is stored in `.zilch.config` (plain text, backward compatible with bash version):

```ini
gcp_project_id=my-project
app_name=my-app
gcp_region=us-central1
enable_firestore=true
enable_cloud_build=true
# ... more options
```

### Configuration Validation

Pydantic validates all fields:

```python
from config import ZilchConfig

# Raises ValueError if app_name is invalid
config = ZilchConfig(
    gcp_project_id="my-project",
    app_name="my-app",  # Must be 3-30 lowercase/numbers/hyphens
)
```

## Testing

```bash
# Run all tests
make test

# Run tests with coverage report
make test-coverage

# Run specific test file
pytest tests/test_config.py -v
```

### Test Structure

```
tests/
├── conftest.py           # Shared fixtures
├── test_config.py        # Config loading/validation
├── test_gcp.py           # GCP operations
└── test_terraform.py     # Terraform orchestration (TBD)
```

## Development

### Setup Development Environment

```bash
# Install all dependencies including dev tools
make install-dev

# Run tests
make test

# Run tests with coverage
make test-coverage

# Clean build artifacts
make clean
```

### Code Style

- PEP 8 compliant
- Type hints on function signatures
- Docstrings for public functions (Google style)
- Comments only for "why", not "what"

### Error Handling

All user-facing errors should:
1. **State what failed** (clear, no jargon)
2. **Explain why** (context)
3. **Suggest recovery** (actionable next step)

Example:
```python
raise GCPError(
    "Failed to set quota project. "
    "You may not have permissions. "
    "Try: gcloud auth application-default set-quota-project <project-id>"
)
```

## Migration from Bash

The Python version is **a drop-in replacement** for the bash scripts:

```bash
# Old way (bash)
bash deploy.sh

# New way (Python)
python3 zilch.py deploy

# Both use same config file (.zilch.config)
# Both support --auto flag
# Both have identical behavior
```

### Known Differences

- `requests` library required (for health checks)
  - Added to `requirements.txt`
  - Lightweight, reliable

- Error messages are more user-friendly
  - Provides recovery suggestions
  - Shows actual error details

- Parallel imports are cleaner
  - Uses `ThreadPoolExecutor` instead of background jobs
  - Better error tracking

## Phase 2 Roadmap

- [ ] Convert `db/migrate.sh` to Python
- [ ] Config format: `.zilch.config` → `zilch.toml`
- [ ] Enhanced GCP operations: Use `google-cloud-python` SDK (more type-safe)
- [ ] Package distribution: Publish to PyPI
- [ ] Watch mode: `zilch.py watch` for real-time deployment logs

## Troubleshooting

### ModuleNotFoundError: No module named 'click'

```bash
pip install -r requirements.txt
```

### ModuleNotFoundError: No module named 'pydantic'

```bash
pip install pydantic
```

### Terraform state lock error

The Python version detects stale locks and offers to remove them:

```
⚠  Found existing Terraform state lock
Remove stale lock and continue? [Y/n]:
```

If it fails, manually clean up:

```bash
gcloud storage rm gs://<project>-zilch-tfstate/terraform/state/<app-name>/default.tflock
```

### Health check timeout

Post-deployment health check may time out if Cloud Run is slow to start:

```
⚠  Health check timed out
```

This is informational. The deployment succeeded; the container is just still starting. Wait a moment and check manually:

```bash
python3 zilch.py status
```

## Fallback to Bash

If the Python version doesn't work, the original bash scripts are still available:

```bash
bash deploy.sh      # Original deploy
bash teardown.sh    # Original teardown
```

Both versions work with the same configuration file, so you can switch between them as needed.

## Feedback & Issues

This is an **alpha release** (Phase 1 of migration). Please report issues or suggest improvements.

Key metrics:
- **Tests**: >80% coverage target
- **Reliability**: Identical behavior to bash version
- **Maintainability**: <800 LOC (vs 1,815 in bash)
