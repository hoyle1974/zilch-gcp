# Python + Terraform Migration Plan

## Executive Summary

Refactor the bash orchestration layer (1,356 lines in `deploy.sh` + 318 in `teardown.sh`) into Python while keeping Terraform for infrastructure-as-code. This improves maintainability, testability, and reduces cognitive load, while preserving the zero-install experience for Cloud Shell users.

**Total effort**: Medium (60-80 hours over 2-3 sprints)  
**Breaking change**: No (users don't need to change how they invoke deployment)  
**Rollback path**: Keep bash scripts as fallback during transition

---

## Architecture Decision Matrix

### 1. GCP Interaction Strategy

| Approach | Pros | Cons | Recommendation |
|----------|------|------|---|
| **gcloud CLI (subprocess)** | Keep existing commands, proven, no new deps | Slower, harder to mock/test, loose typing | ✅ **Start here** |
| **google-cloud Python SDK** | Native types, better async, official | Adds dependency, more complex, migration work | 🔄 **Phase 2 option** |
| **Hybrid (selective)** | Get best of both | Scattered patterns, harder to maintain | ❌ **Avoid** |

**Decision**: Keep calling `gcloud`, `terraform`, `bq` via subprocess. Wrap in Python functions. Reason: Minimal risk, tests existing behavior, no new runtime dependencies beyond Click.

### 2. Terraform Orchestration Strategy

| Approach | Pros | Cons | Recommendation |
|----------|------|------|---|
| **Subprocess (terraform CLI)** | How bash does it now, simple | Process management complexity | ✅ **Phase 1** |
| **python-terraform lib** | Cleaner API, error handling | Outdated, less maintained | 🚫 **Avoid** |
| **terraform-exec** | Official Terraform Library for Python | Adds dependency, overkill for orchestration | 🔄 **Phase 2 option** |

**Decision**: Subprocess for Phase 1 (matches current behavior exactly). Can upgrade to `terraform-exec` in Phase 2 if we need better error handling or state manipulation.

### 3. Configuration Format

| Format | Pros | Cons | Recommendation |
|--------|------|------|---|
| **Keep .zilch.config** | No user behavior change, familiar | Manual parsing, fragile quotes | ⚠️ **Bridge phase** |
| **YAML** | Human-friendly, hierarchical | Extra dependency (PyYAML) | 🔄 **Phase 2** |
| **TOML** | Python 3.11+ (tomllib), clean, typed | Still a format migration | 🔄 **Phase 2** |
| **Pydantic + env vars** | Type-safe, code-driven, no file format | Requires env var setup | 🚫 **Too different** |

**Decision**: Keep `.zilch.config` format in Phase 1 (use Pydantic to load/validate it). Migrate to TOML in Phase 2 after proving Python approach works.

### 4. Distribution & Installation

| Model | Pros | Cons | Recommendation |
|-------|------|------|---|
| **Single script (`zilch.py`)** | Simple, discoverable | Not scalable as code grows | ✅ **Phase 1** |
| **Package (`pip install zilch`)** | Professional, versioned | Requires PyPI/private registry | 🔄 **Phase 2+** |
| **Vendored script + deps** | Works offline, no pip needed | Large, hard to update | ❌ **Avoid** |

**Decision**: Single `zilch.py` script in Phase 1. Move to package structure in Phase 2 if this gets adopted widely.

### 5. Dependency Management

| Option | Recommendation |
|--------|---|
| `Click` (CLI framework) | ✅ **Required** — only sane way to handle interactive prompts |
| `Pydantic` (config validation) | ✅ **Already available** on user systems, use it |
| `pytest` + `pytest-mock` (testing) | ✅ **Dev only** — drastically improves test quality |
| `python-terraform`, `google-cloud-python` | 🚫 **Phase 2+** — don't add in Phase 1 |

**Phase 1 deps**:
```
click>=8.1.0          # Interactive CLI
pydantic>=2.0.0       # Config validation (may be pre-installed)
```

**Phase 1 dev deps**:
```
pytest>=7.0.0
pytest-mock
```

---

## Directory Structure (Phase 1)

```
zilch-gcp/
├── zilch.py                    # NEW: Single entry point (CLI + orchestration)
├── deploy.sh                   # DEPRECATED: Kept for fallback only
├── teardown.sh                 # DEPRECATED: Kept for fallback only
├── common.sh                   # DEPRECATED: Kept for fallback only
│
├── Makefile                    # NEW: Development convenience
├── requirements.txt            # NEW: pip dependencies
├── requirements-dev.txt        # NEW: Testing dependencies
│
├── terraform/                  # EXISTING: No changes
│   ├── *.tf
│   └── backend.tf
│
├── db/
│   ├── migrate.sh              # KEEP (for now): Database migrations
│   └── migrations/
│
├── .gitignore                  # ENSURE: Includes __pycache__, *.pyc, venv/
│
└── tests/                      # NEW: Test directory (Phase 1B)
    ├── __init__.py
    ├── test_cli.py
    ├── test_config.py
    ├── test_terraform.py
    └── conftest.py
```

---

## Phase 1: Core Orchestration (Bash → Python)

### What moves to Python

**Module 1: `cli.py` (interactive prompts)**
- Replace lines 13-660 of deploy.sh (interactive menus, prompts)
- Class: `ConfigCollector` with methods like:
  - `get_project_id()`
  - `get_app_name()`
  - `get_region()`
  - `get_services()`  ← replaces `interactive_service_menu()`
  - `get_monitoring_config()` ← replaces monitoring prompts

**Module 2: `config.py` (validation & loading)**
- Replace lines 73-185 of deploy.sh (config file parsing)
- Pydantic model: `ZilchConfig` with:
  - Type validation (enums for regions, booleans for features)
  - Default values
  - Methods: `load_from_file()`, `save_to_file()`, `merge_with_prompts()`
- Replace manual quote-stripping (lines 127-140) with Pydantic validation

**Module 3: `gcp.py` (GCP operations)**
- Replace lines 36-222 of deploy.sh (tool checks, gcloud auth, IAM validation)
- Functions:
  - `check_required_tools()` → calls subprocess
  - `validate_gcloud_auth()` → calls gcloud CLI
  - `validate_project_access()` → IAM checks
  - `validate_firestore_permissions()` → Firestore role checks
  - `create_storage_bucket()` → state bucket setup

**Module 4: `terraform.py` (Terraform orchestration)**
- Replace lines 807-1240 of deploy.sh (terraform init, apply, import)
- Functions:
  - `TerraformExecutor` class:
    - `init(bucket, prefix)` → wraps `terraform init`
    - `apply(vars_dict)` → wraps `terraform apply`
    - `destroy()` → wraps `terraform destroy`
    - `import_resource(resource_type, resource_id)` → wraps `terraform import`
  - `ParallelImporter` class for state reconciliation (lines 1000-1198)

**Module 5: `health_check.py` (post-deployment)**
- Replace lines 1250-1274 of deploy.sh (endpoint health checks)
- Functions:
  - `check_cloud_run_health(url, retries=3)` → HTTP health checks
  - `wait_for_endpoint(url, timeout)` → retry logic

**Module 6: `output.py` (formatting)**
- Replace ANSI color definitions + formatted output
- Functions:
  - `success(msg)`, `error(msg)`, `warning(msg)`, `info(msg)`
  - `print_deployment_summary(config, outputs)` → replaces lines 1289-1347

### Main entry point: `zilch.py`

```python
@click.group()
def cli():
    """Zilch infrastructure deployment tool"""
    pass

@cli.command()
@click.option('--auto', is_flag=True, help='Use config defaults, skip prompts')
def deploy(auto):
    """Deploy infrastructure"""
    # 1. collect config (or load from file if --auto)
    # 2. validate GCP access
    # 3. create state bucket
    # 4. terraform init
    # 5. import existing resources (parallel)
    # 6. terraform apply
    # 7. health checks
    # 8. print summary

@cli.command()
@click.option('--force', is_flag=True, help='Skip safety confirmations')
def teardown(force):
    """Destroy all infrastructure"""
    # Replaces teardown.sh logic

@cli.command()
def status():
    """Show current deployment status"""
    # NEW: Query Terraform state, show outputs

if __name__ == '__main__':
    cli()
```

### Error Handling Strategy

**Current state (bash)**: Error handling is scattered, sometimes silent failures
**Python approach**:
- Custom exception classes:
  ```python
  class ZilchError(Exception): pass
  class GCPError(ZilchError): pass
  class TerraformError(ZilchError): pass
  class ConfigError(ZilchError): pass
  ```
- All subprocess calls wrapped in try/except
- User-friendly error messages with recovery suggestions
- Exit codes: 0 (success), 1 (user error), 2 (system error)

---

## Phase 2: Enhanced Features (Post-Phase 1)

- **Config format migration**: `.zilch.config` → TOML
- **Secrets handling**: Use `google-cloud-python` SDK directly (more secure)
- **Database migrations**: Convert `db/migrate.sh` to Python
- **Terraform state inspection**: Better visibility into what's deployed
- **Package distribution**: Publish to PyPI or internal registry
- **Watch mode**: `zilch watch` for real-time deployment logs
- **Multi-region support**: Better orchestration for multi-region deployments

---

## Phase 1 Implementation Roadmap

### Sprint 1: Foundation (1-2 weeks)
- [ ] Create project structure (zilch.py, modules)
- [ ] Set up testing infrastructure (pytest, conftest)
- [ ] Implement `config.py` module
- [ ] Implement `output.py` module (formatting)
- [ ] Write tests for config loading/validation

**Success criteria**: 
- Config loads from file, validated, saveable
- No manual quote stripping needed
- Tests cover all validation paths

### Sprint 2: GCP Layer (1-2 weeks)
- [ ] Implement `gcp.py` (validation, permissions, bucket setup)
- [ ] Implement `cli.py` (interactive prompts)
- [ ] Wire together in `zilch.py deploy --auto`
- [ ] Write integration tests (gcloud mock calls)

**Success criteria**:
- `zilch.py deploy --auto` works with saved config
- All GCP validations pass/fail with clear messages
- Tests mock gcloud calls

### Sprint 3: Terraform & Orchestration (1-2 weeks)
- [ ] Implement `terraform.py` (init, apply, import, destroy)
- [ ] Implement `health_check.py`
- [ ] Full `zilch.py deploy` flow (with prompts)
- [ ] Full `zilch.py teardown` flow
- [ ] Integration tests (real Terraform plan output)

**Success criteria**:
- Full deploy flow matches bash behavior exactly
- Teardown works cleanly
- Health checks work, reasonable timeouts

### Sprint 4: Testing & Hardening (1 week)
- [ ] End-to-end testing (test deployment in test project)
- [ ] Edge case testing (missing tools, bad credentials, etc.)
- [ ] Documentation (README, examples)
- [ ] Bash → Python migration guide for users

**Success criteria**:
- E2E test passes in test GCP project
- All edge cases handled gracefully
- Users can understand code and contribute

---

## Migration Safety & Rollback

### Parallel Execution Strategy

**Phase 1A-1B**: Both bash and Python exist, operate independently
- Users can choose: `bash deploy.sh` or `python3 zilch.py deploy`
- Keep bash scripts as fallback during testing
- Symlink or wrapper script points to Python version by default

**Rollback plan**:
```bash
# If Python version breaks, users can:
bash deploy.sh  # Still works
```

### Testing Before Cutover

1. **Unit tests** (local, fast)
   - Config loading/validation
   - Argument parsing
   - Output formatting

2. **Integration tests** (mock gcloud/terraform)
   - Subprocess calls with mocked responses
   - Error handling paths
   - State reconciliation logic

3. **E2E test** (real test GCP project, monthly)
   - Full deploy → health check → teardown flow
   - Against real GCP (test project, throwaway)
   - Validates against current bash behavior

### Cutover Timeline

- **Week 1-2**: Phase 1 Sprint 1-2, collect feedback
- **Week 2-3**: Phase 1 Sprint 3-4, fix edge cases
- **Week 3-4**: Run E2E test against test project
- **Week 4**: Soft cutover (Python default, bash available)
- **Week 5+**: Monitor, gather feedback
- **Month 2**: Bash support EOL (optional, can keep indefinitely)

---

## Code Quality Standards (Phase 1)

### Testing Coverage

- Target: >80% coverage on core modules
- Exempt from coverage: ANSI color codes, help text
- Test structure:
  ```
  tests/
  ├── unit/         # Pure function tests, no subprocess
  ├── integration/  # Subprocess with mocking
  └── fixtures/     # Mock responses, sample configs
  ```

### Type Hints

- **Required** for all function signatures
- Optional for internal logic (but encouraged)
- Validate with `mypy --strict` (optional, Phase 2)

### Code Style

- PEP 8 (use `black` for formatting, Phase 2)
- Docstrings for public functions (Google style)
- Comments: only for *why*, not *what*

### Error Messages

Every error should:
1. **State what failed** (clear, no jargon)
2. **Explain why** (context)
3. **Suggest recovery** (actionable next step)

Example (bad):
```
Error: gcloud auth failed
```

Example (good):
```
✗ Authentication failed
You're not logged in to GCP. Run:
  gcloud auth login
```

---

## Specific Code Refactoring Examples

### Example 1: Config Loading

**Bash (lines 122-175 of deploy.sh)**:
```bash
while IFS='=' read -r key value; do
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    while [[ "$value" == \"* ]] && [[ "$value" == *\" ]]; do
        value="${value#\"}"
        value="${value%\"}"
    done
    case "$key" in
        gcp_project_id) PROJECT_ID="$value" ;;
        # ... 30 more variables
    esac
done < .zilch.config
```

**Python (config.py)**:
```python
from pydantic import BaseModel, Field, field_validator
from typing import Optional

class ZilchConfig(BaseModel):
    gcp_project_id: str
    app_name: str
    gcp_region: str = "us-central1"  # default
    enable_firestore: bool = False
    # ... other fields
    
    @field_validator('app_name')
    @classmethod
    def validate_app_name(cls, v):
        if not re.match(r'^[a-z0-9-]{3,30}$', v):
            raise ValueError('Invalid app name')
        return v
    
    @classmethod
    def load_from_file(cls, path: str) -> 'ZilchConfig':
        """Load config from .zilch.config file"""
        config_dict = {}
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                key, value = line.split('=', 1)
                config_dict[key.strip()] = value.strip().strip('"')
        return cls(**config_dict)
    
    def save_to_file(self, path: str):
        """Save config to .zilch.config file"""
        with open(path, 'w') as f:
            for key, value in self:
                f.write(f"{key}={value}\n")
```

Benefits:
- Type safety: Pydantic catches bad values at load time
- Validation: `@field_validator` replaces 30 lines of case logic
- Maintainability: Easy to add new fields
- Testability: Can test validation independently

### Example 2: Parallel Resource Import

**Bash (lines 1000-1198 of deploy.sh)**:
```bash
declare -a import_pids
check_and_import_resource "google_service_account.app" ... &
import_pids+=($!)
check_and_import_resource "google_service_account.cloud_build" ... &
import_pids+=($!)
# ... 15 more resources
for pid in "${import_pids[@]}"; do
    if ! wait $pid; then
        import_failed=true
    fi
done
```

**Python (terraform.py)**:
```python
from concurrent.futures import ThreadPoolExecutor, as_completed

class ParallelImporter:
    def import_all(self, resources: List[Resource]) -> ImportResult:
        """Import resources in parallel with error tracking"""
        results = {}
        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = {
                executor.submit(self.import_resource, r): r 
                for r in resources
            }
            for future in as_completed(futures):
                resource = futures[future]
                try:
                    results[resource.name] = future.result()
                except TerraformError as e:
                    results[resource.name] = None
                    logger.error(f"Import failed: {resource.name}: {e}")
        
        failed = [r for r, result in results.items() if result is None]
        if failed:
            logger.warning(f"Some imports failed: {failed}, continuing...")
        return ImportResult(results, failed)
```

Benefits:
- Uses Python's ThreadPoolExecutor (cleaner than bash background jobs)
- Better error handling and collection
- Easier to test and debug
- Self-documenting code

### Example 3: Interactive Menu

**Bash (lines 319-399 of deploy.sh)**:
```bash
prompt_toggle() {
    local feature_name=$1
    local current_value=$2
    # ... 20 lines of conditional logic
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo "true"
    else
        echo "false"
    fi
}

interactive_service_menu() {
    # ... 80 lines with manual formatting
    ENABLE_FIRESTORE=$(prompt_toggle "Firestore" "$ENABLE_FIRESTORE")
    ENABLE_CLOUD_STORAGE=$(prompt_toggle "Cloud Storage" "$ENABLE_CLOUD_STORAGE")
    # ... 14 more toggles
}
```

**Python (cli.py with Click)**:
```python
import click

def get_services(current_config: ZilchConfig) -> Dict[str, bool]:
    """Interactive service menu using Click"""
    services = {
        'firestore': ('Firestore', 'NoSQL: document storage, real-time sync'),
        'cloud_storage': ('Cloud Storage', 'Files: user uploads, media'),
        'secret_manager': ('Secret Manager', 'Secrets: API keys, passwords'),
        # ... etc
    }
    
    results = {}
    for key, (name, description) in services.items():
        current = getattr(current_config, f'enable_{key}', False)
        default = 'Y' if current else 'n'
        
        click.echo(f"\n{click.style(name, bold=True)}")
        click.echo(f"  {description}")
        
        result = click.confirm('Enable?', default=current)
        results[f'enable_{key}'] = result
    
    return results
```

Benefits:
- Click handles input validation and formatting
- Single source of truth (services dict)
- Easy to add service descriptions
- No manual state management

---

## Dependency Comparison

### Phase 1 vs. Current

| Aspect | Bash | Python |
|--------|------|--------|
| **Runtime deps** | gcloud, terraform, curl, bq | (same) + Python 3.8+ |
| **Pip deps** | None | click, pydantic |
| **Lines of code** | 1,356 + 318 + 141 = 1,815 | ~800 (with tests: 1,400) |
| **Test coverage** | ~0% | >80% (goal) |
| **Error handling** | Scattered, implicit | Unified, explicit |
| **Type safety** | None | Pydantic validation |
| **IDE support** | Poor (bash-lsp) | Excellent (Pylance, mypy) |

---

## Known Risks & Mitigation

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Python version mismatch | Medium | Test on Python 3.8, 3.9, 3.10, 3.11, 3.12+ |
| Cloud Shell Python unavailable | Low | Include fallback to bash if python3 not found |
| Subprocess output parsing breaks | Medium | Comprehensive mocking tests, validate against real terraform output |
| Click dependency incompatibility | Low | Pin `click>=8.1.0, <9`, test regularly |
| Migration takes longer than estimated | Medium | Pair programming on Terraform module, prioritize core features |
| Users stick with bash | Low | Make Python version obviously better (faster, clearer errors) |

---

## Success Metrics (Phase 1)

- ✅ Python version deploys infrastructure identically to bash
- ✅ All error paths tested and have helpful messages
- ✅ E2E test passes in test GCP project
- ✅ Code is documented, new contributors can add features
- ✅ Users prefer Python version within 2 weeks

---

## Questions for Alignment

1. **Who** will maintain this going forward? (affects code style, documentation depth)
2. **When** do you want Python version ready? (affects scope prioritization)
3. **Should** we deprecate bash completely or support both long-term?
4. **Do** you want to move `db/migrate.sh` to Python in Phase 1, or Phase 2?
5. **Should** the package be internal/private or published to PyPI?
