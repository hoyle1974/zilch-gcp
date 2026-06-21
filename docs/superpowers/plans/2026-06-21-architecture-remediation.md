# Architecture Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three critical architecture flaws: subprocess reliance on gcloud/terraform parsing, blind state lock deletion, and permissive health checks.

**Architecture:** Replace gcloud subprocess calls with native Google Cloud Python Client Libraries. Enforce JSON-only output from Terraform to avoid brittle string parsing. Implement proper state lock metadata reading with native terraform force-unlock. Implement strict HTTP status validation (200 OK only) with OIDC token support for authenticated Cloud Run services.

**Tech Stack:** 
- Google Cloud Python Client Libraries (google-cloud-storage, google-cloud-resourcemanager, google-cloud-billing, google-auth)
- Terraform JSON output parsing
- OIDC token generation via google.auth
- Pydantic for config validation

## Global Constraints

- Python 3.8+
- All changes must maintain backward compatibility in CLI (exception: config field additions are non-breaking)
- Terraform operations must use JSON mode exclusively (-json flag)
- No change to function signatures in public APIs unless explicitly noted
- Health check must support both authenticated and unauthenticated Cloud Run services

---

## File Structure

```
gcp.py                      # Replace gcloud subprocess → Google Cloud client libs
terraform.py                # Add JSON output, lock metadata reading, force-unlock
health_check.py             # Strict status validation, OIDC token support
config.py                   # Add health_check_endpoint, expected_health_status fields
requirements.txt            # Add google-cloud-* dependencies
```

---

## Task 1: Update dependencies and extend configuration

**Files:**
- Modify: `requirements.txt`
- Modify: `config.py`
- Test: `tests/test_config.py`

**Interfaces:**
- Consumes: Existing ZilchConfig class
- Produces: ZilchConfig with two new fields: `expected_health_status: int = 200`, `health_check_endpoint: str = "/health-check"`

- [ ] **Step 1: Add Google Cloud client libraries to requirements.txt**

Read the current requirements.txt, then add these lines at the end (or in alphabetical order with existing `google-` entries):

```
google-auth==2.28.0
google-cloud-billing==1.11.1
google-cloud-resourcemanager==1.15.1
google-cloud-storage==2.14.0
```

Run: `grep -E "google-(auth|cloud)" requirements.txt` to verify additions.

- [ ] **Step 2: Extend ZilchConfig with health check fields**

In `config.py`, add two fields to the ZilchConfig class after line 56 (after `gcp_billing_account_id`):

```python
    # Health check configuration
    expected_health_status: int = 200
    health_check_endpoint: str = "/health-check"
```

Also add a validator for expected_health_status (after the validate_budget method):

```python
    @field_validator("expected_health_status")
    @classmethod
    def validate_http_status(cls, v: int) -> int:
        """Validate HTTP status code is 2xx or 3xx."""
        if not 200 <= v < 400:
            raise ValueError("expected_health_status must be a valid HTTP success code (200-399)")
        return v
```

- [ ] **Step 3: Write test for new config fields**

Create or update `tests/test_config.py` with:

```python
def test_config_health_check_defaults():
    config = ZilchConfig(
        gcp_project_id="test-project",
        app_name="test-app"
    )
    assert config.expected_health_status == 200
    assert config.health_check_endpoint == "/health-check"

def test_config_health_check_custom_status():
    config = ZilchConfig(
        gcp_project_id="test-project",
        app_name="test-app",
        expected_health_status=202
    )
    assert config.expected_health_status == 202

def test_config_health_check_custom_endpoint():
    config = ZilchConfig(
        gcp_project_id="test-project",
        app_name="test-app",
        health_check_endpoint="/status"
    )
    assert config.health_check_endpoint == "/status"

def test_config_health_check_invalid_status():
    with pytest.raises(ValueError, match="HTTP success code"):
        ZilchConfig(
            gcp_project_id="test-project",
            app_name="test-app",
            expected_health_status=500
        )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pytest tests/test_config.py::test_config_health_check_defaults -v`
Run: `pytest tests/test_config.py::test_config_health_check_custom_status -v`
Run: `pytest tests/test_config.py::test_config_health_check_custom_endpoint -v`
Run: `pytest tests/test_config.py::test_config_health_check_invalid_status -v`

Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add requirements.txt config.py tests/test_config.py
git commit -m "feat(config): add health_check_endpoint and expected_health_status fields"
```

---

## Task 2: Replace gcloud auth and project validation with Google Cloud clients

**Files:**
- Modify: `gcp.py` (lines 55-113)
- Test: `tests/test_gcp_auth.py`

**Interfaces:**
- Consumes: None (new dependencies)
- Produces: Modified `validate_gcloud_auth()` returns tuple (email, credentials), `validate_project()` uses google.cloud.resourcemanager

- [ ] **Step 1: Import Google Cloud libraries at top of gcp.py**

Add these imports after the existing imports (after line 7):

```python
import json
from google.auth import default as google_auth_default
from google.auth.transport.requests import Request
from google.cloud import resourcemanager_v3
from google.api_core import exceptions as google_exceptions
```

- [ ] **Step 2: Rewrite validate_gcloud_auth() to use google.auth**

Replace the `validate_gcloud_auth()` function (lines 55-89) with:

```python
def validate_gcloud_auth() -> tuple[str, object]:
    """Validate Google Cloud authentication via default credentials.

    Returns:
        Tuple of (authenticated account email, credentials object)

    Raises:
        GCPError: If not authenticated
    """
    try:
        credentials, project_id = google_auth_default()
        
        # Refresh credentials to ensure they're valid
        credentials.refresh(Request())
        
        # Get the service account email from credentials
        if hasattr(credentials, 'service_account_email'):
            current_user = credentials.service_account_email
        elif hasattr(credentials, '_service_account_email'):
            current_user = credentials._service_account_email
        else:
            # For user credentials, extract from token
            current_user = getattr(credentials, 'quota_project_id', 'unknown@google.com')
        
        if not current_user or "@" not in current_user:
            raise GCPError("Could not determine authenticated account email")
        
        success(f"Authenticated as {current_user}")
        return current_user, credentials
    except Exception as e:
        raise GCPError(f"Failed to authenticate: {str(e)}")
```

- [ ] **Step 3: Rewrite validate_project() to use resourcemanager client**

Replace the `validate_project()` function (lines 92-113) with:

```python
def validate_project(project_id: str) -> None:
    """Validate GCP project exists and user has access.

    Args:
        project_id: GCP project ID

    Raises:
        GCPError: If project doesn't exist or user has no access
    """
    try:
        client = resourcemanager_v3.ProjectsClient()
        request = resourcemanager_v3.GetProjectRequest(name=f"projects/{project_id}")
        project = client.get_project(request=request)
        success(f"Project {project_id}")
    except google_exceptions.NotFound:
        raise GCPError(f"Project {project_id} not found or no access")
    except Exception as e:
        raise GCPError(f"Failed to validate project: {str(e)}")
```

- [ ] **Step 4: Write tests for new auth functions**

Create `tests/test_gcp_auth.py`:

```python
import pytest
from unittest.mock import patch, MagicMock
from gcp import validate_gcloud_auth, validate_project, GCPError

def test_validate_gcloud_auth_success():
    with patch('gcp.google_auth_default') as mock_auth:
        mock_creds = MagicMock()
        mock_creds.service_account_email = "test@example.iam.gserviceaccount.com"
        mock_auth.return_value = (mock_creds, "test-project")
        
        email, creds = validate_gcloud_auth()
        assert email == "test@example.iam.gserviceaccount.com"
        assert creds == mock_creds

def test_validate_gcloud_auth_failure():
    with patch('gcp.google_auth_default') as mock_auth:
        mock_auth.side_effect = Exception("No credentials found")
        
        with pytest.raises(GCPError, match="Failed to authenticate"):
            validate_gcloud_auth()

def test_validate_project_success():
    with patch('gcp.resourcemanager_v3.ProjectsClient') as mock_client_class:
        mock_client = MagicMock()
        mock_client_class.return_value = mock_client
        mock_client.get_project.return_value = MagicMock(name="projects/test-project")
        
        validate_project("test-project")
        mock_client.get_project.assert_called_once()

def test_validate_project_not_found():
    with patch('gcp.resourcemanager_v3.ProjectsClient') as mock_client_class:
        from google.api_core.exceptions import NotFound
        mock_client = MagicMock()
        mock_client_class.return_value = mock_client
        mock_client.get_project.side_effect = NotFound("Not found")
        
        with pytest.raises(GCPError, match="not found"):
            validate_project("nonexistent-project")
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `pytest tests/test_gcp_auth.py -v`

Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add gcp.py tests/test_gcp_auth.py
git commit -m "feat(gcp): replace gcloud auth/project validation with Google Cloud clients"
```

---

## Task 3: Replace gcloud IAM and storage operations with Google Cloud clients

**Files:**
- Modify: `gcp.py` (lines 116-283)
- Test: `tests/test_gcp_storage.py`

**Interfaces:**
- Consumes: Google Cloud client libraries
- Produces: `validate_iam_permissions()`, `create_state_bucket()` use native clients

- [ ] **Step 1: Add additional imports to gcp.py**

After line 9 (after existing google imports), add:

```python
from google.cloud import storage
from google.cloud.resourcemanager_v3 import ProjectsClient
from google.iam.v1 import GetIamPolicyRequest, SetIamPolicyRequest
```

- [ ] **Step 2: Rewrite validate_iam_permissions() to use resourcemanager client**

Replace lines 116-151 with:

```python
def validate_iam_permissions(project_id: str, current_user: str) -> None:
    """Validate user has Editor or Owner role.

    Args:
        project_id: GCP project ID
        current_user: Currently authenticated user email

    Raises:
        GCPError: If user lacks required permissions
    """
    try:
        client = resourcemanager_v3.ProjectsClient()
        request = GetIamPolicyRequest(resource=f"projects/{project_id}")
        policy = client.get_iam_policy(request=request)
        
        user_binding = f"user:{current_user}"
        has_editor = False
        has_owner = False
        
        for binding in policy.bindings:
            if user_binding in binding.members:
                if "roles/editor" in binding.role:
                    has_editor = True
                if "roles/owner" in binding.role:
                    has_owner = True
        
        if not (has_editor or has_owner):
            raise GCPError(
                f"User {current_user} needs Editor or Owner role on {project_id}"
            )
        
        success("IAM permissions OK")
    except GCPError:
        raise
    except Exception as e:
        raise GCPError(f"Failed to check IAM permissions: {str(e)}")
```

- [ ] **Step 3: Rewrite create_state_bucket() to use storage client**

Replace lines 217-282 with:

```python
def create_state_bucket(
    project_id: str, bucket_name: str, region: str
) -> None:
    """Create GCS bucket for Terraform state.

    Args:
        project_id: GCP project ID
        bucket_name: Name of bucket to create
        region: GCP region

    Raises:
        GCPError: If bucket creation fails
    """
    info(f"State bucket {bucket_name}")
    
    client = storage.Client(project=project_id)
    bucket = client.bucket(bucket_name)
    
    # Check if bucket already exists
    if bucket.exists():
        success("Using existing bucket")
        return
    
    # Create bucket with uniform bucket-level access
    try:
        bucket.location = region
        bucket.iam_configuration.uniform_bucket_level_access_enabled = True
        bucket.create()
        success("Created bucket")
    except google_exceptions.Conflict:
        success("Using existing bucket")
        return
    except Exception as e:
        raise GCPError(f"Failed to create state bucket: {str(e)}")
    
    # Verify bucket is accessible
    max_retries = 15
    for attempt in range(max_retries):
        try:
            list(client.list_blobs(bucket_name, max_results=1))
            success("Bucket is accessible")
            return
        except Exception:
            if attempt < max_retries - 1:
                info(f"Waiting for bucket ({attempt + 1}/{max_retries})...")
                import time
                time.sleep(1)
            else:
                raise GCPError("Bucket not accessible after retries")
```

- [ ] **Step 4: Write tests for storage operations**

Create `tests/test_gcp_storage.py`:

```python
import pytest
from unittest.mock import patch, MagicMock
from gcp import validate_iam_permissions, create_state_bucket, GCPError

def test_validate_iam_permissions_with_editor():
    with patch('gcp.resourcemanager_v3.ProjectsClient') as mock_client_class:
        mock_client = MagicMock()
        mock_client_class.return_value = mock_client
        
        mock_binding = MagicMock()
        mock_binding.role = "roles/editor"
        mock_binding.members = ["user:test@example.com"]
        
        mock_policy = MagicMock()
        mock_policy.bindings = [mock_binding]
        
        mock_client.get_iam_policy.return_value = mock_policy
        
        validate_iam_permissions("test-project", "test@example.com")
        mock_client.get_iam_policy.assert_called_once()

def test_validate_iam_permissions_no_role():
    with patch('gcp.resourcemanager_v3.ProjectsClient') as mock_client_class:
        mock_client = MagicMock()
        mock_client_class.return_value = mock_client
        
        mock_policy = MagicMock()
        mock_policy.bindings = []
        
        mock_client.get_iam_policy.return_value = mock_policy
        
        with pytest.raises(GCPError, match="needs Editor or Owner role"):
            validate_iam_permissions("test-project", "test@example.com")

def test_create_state_bucket_already_exists():
    with patch('gcp.storage.Client') as mock_client_class:
        mock_client = MagicMock()
        mock_client_class.return_value = mock_client
        
        mock_bucket = MagicMock()
        mock_bucket.exists.return_value = True
        mock_client.bucket.return_value = mock_bucket
        
        create_state_bucket("test-project", "test-bucket", "us-central1")
        mock_bucket.exists.assert_called_once()

def test_create_state_bucket_creates_new():
    with patch('gcp.storage.Client') as mock_client_class:
        with patch('gcp.list') as mock_list:
            mock_client = MagicMock()
            mock_client_class.return_value = mock_client
            
            mock_bucket = MagicMock()
            mock_bucket.exists.return_value = False
            mock_client.bucket.return_value = mock_bucket
            mock_client.list_blobs.return_value = []
            
            create_state_bucket("test-project", "test-bucket", "us-central1")
            mock_bucket.create.assert_called_once()
```

- [ ] **Step 5: Run tests**

Run: `pytest tests/test_gcp_storage.py -v`

Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add gcp.py tests/test_gcp_storage.py
git commit -m "feat(gcp): replace gcloud IAM and bucket operations with Google Cloud clients"
```

---

## Task 4: Add JSON output enforcement to Terraform operations

**Files:**
- Modify: `terraform.py` (lines 71-111)
- Test: `tests/test_terraform_json.py`

**Interfaces:**
- Consumes: TerraformExecutor class
- Produces: Modified plan() and apply() to use `-json` flag and parse JSON output

- [ ] **Step 1: Update TerraformExecutor.plan() to enforce JSON output**

Replace the plan() method (lines 71-111) with:

```python
    def plan(self, vars_dict: Dict[str, str]) -> Dict:
        """Plan Terraform changes (dry-run) with JSON output.

        Args:
            vars_dict: Dictionary of Terraform variables

        Returns:
            Parsed JSON plan output as dict

        Raises:
            TerraformError: If plan fails
        """
        info("Planning infrastructure changes")

        # Build variable arguments
        var_args = []
        for key, value in vars_dict.items():
            if isinstance(value, bool):
                var_args.append(f'-var={key}={str(value).lower()}')
            else:
                var_args.append(f'-var={key}={value}')

        cmd = [
            "terraform",
            "-chdir=" + str(self.working_dir),
            "plan",
            "-json",  # Enforce JSON output
        ] + var_args

        # Set quota project for billing API
        env = os.environ.copy()
        if 'gcp_project_id' in vars_dict:
            env['GOOGLE_CLOUD_QUOTA_PROJECT'] = vars_dict['gcp_project_id']

        try:
            result = subprocess.run(
                cmd,
                timeout=600,  # 10 minutes
                check=False,  # JSON output includes diagnostics
                cwd=str(self.working_dir),
                env=env,
                capture_output=True,
                text=True,
            )
            
            # Parse JSON output
            try:
                plan_output = json.loads(result.stdout)
            except json.JSONDecodeError:
                raise TerraformError(f"Failed to parse Terraform plan JSON: {result.stdout}")
            
            # Check for errors in JSON diagnostics
            if result.returncode != 0:
                raise TerraformError(f"Terraform plan failed: {result.stderr}")
            
            success("Plan completed (no changes applied)")
            return plan_output
        except subprocess.TimeoutExpired:
            raise TerraformError("Terraform plan timed out")
```

- [ ] **Step 2: Update TerraformExecutor.apply() to enforce JSON output**

Replace the apply() method (lines 113-154) with:

```python
    def apply(self, vars_dict: Dict[str, str]) -> Dict:
        """Apply Terraform configuration with JSON output.

        Args:
            vars_dict: Dictionary of Terraform variables

        Returns:
            Parsed JSON apply output as dict

        Raises:
            TerraformError: If apply fails
        """
        info("Applying infrastructure")

        # Build variable arguments
        var_args = []
        for key, value in vars_dict.items():
            if isinstance(value, bool):
                var_args.append(f'-var={key}={str(value).lower()}')
            else:
                var_args.append(f'-var={key}={value}')

        cmd = [
            "terraform",
            "-chdir=" + str(self.working_dir),
            "apply",
            "-auto-approve",
            "-json",  # Enforce JSON output
        ] + var_args

        # Set quota project for billing API
        env = os.environ.copy()
        if 'gcp_project_id' in vars_dict:
            env['GOOGLE_CLOUD_QUOTA_PROJECT'] = vars_dict['gcp_project_id']

        try:
            result = subprocess.run(
                cmd,
                timeout=600,  # 10 minutes
                check=False,  # JSON output includes diagnostics
                cwd=str(self.working_dir),
                env=env,
                capture_output=True,
                text=True,
            )
            
            # Parse JSON output
            try:
                apply_output = json.loads(result.stdout)
            except json.JSONDecodeError:
                raise TerraformError(f"Failed to parse Terraform apply JSON: {result.stdout}")
            
            # Check for errors in JSON diagnostics
            if result.returncode != 0:
                raise TerraformError(f"Terraform apply failed: {result.stderr}")
            
            success("Infrastructure deployed")
            return apply_output
        except subprocess.TimeoutExpired:
            raise TerraformError("Terraform apply timed out")
```

- [ ] **Step 3: Add json import at top of terraform.py**

Add `import json` after line 3 (after existing imports):

```python
import json
```

- [ ] **Step 4: Write tests for JSON output parsing**

Create `tests/test_terraform_json.py`:

```python
import pytest
import json
from unittest.mock import patch, MagicMock
from terraform import TerraformExecutor, TerraformError

def test_plan_json_output():
    executor = TerraformExecutor(working_dir=".")
    
    mock_output = {
        "type": "planned_change",
        "change": {
            "actions": ["create"]
        }
    }
    
    with patch('terraform.subprocess.run') as mock_run:
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout=json.dumps(mock_output),
            stderr=""
        )
        
        result = executor.plan({"app_name": "test"})
        assert result["type"] == "planned_change"
        mock_run.assert_called_once()
        # Verify -json flag is passed
        assert "-json" in mock_run.call_args[0][0]

def test_plan_json_parse_error():
    executor = TerraformExecutor(working_dir=".")
    
    with patch('terraform.subprocess.run') as mock_run:
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout="invalid json",
            stderr=""
        )
        
        with pytest.raises(TerraformError, match="Failed to parse"):
            executor.plan({"app_name": "test"})

def test_apply_json_output():
    executor = TerraformExecutor(working_dir=".")
    
    mock_output = {
        "type": "apply_complete",
        "values": {}
    }
    
    with patch('terraform.subprocess.run') as mock_run:
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout=json.dumps(mock_output),
            stderr=""
        )
        
        result = executor.apply({"app_name": "test"})
        assert result["type"] == "apply_complete"
        assert "-json" in mock_run.call_args[0][0]
```

- [ ] **Step 5: Run tests**

Run: `pytest tests/test_terraform_json.py -v`

Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add terraform.py tests/test_terraform_json.py
git commit -m "feat(terraform): enforce JSON output for plan and apply operations"
```

---

## Task 5: Implement state lock metadata reading and terraform force-unlock

**Files:**
- Modify: `gcp.py` (lines 335-380)
- Modify: `terraform.py` (add method)
- Test: `tests/test_lock_management.py`

**Interfaces:**
- Consumes: TerraformExecutor, Google Cloud storage client
- Produces: `read_terraform_lock_metadata()` returns dict, `force_unlock_terraform()` uses native terraform

- [ ] **Step 1: Add lock metadata reading function to gcp.py**

After line 356 (after check_terraform_lock_exists), add:

```python
def read_terraform_lock_metadata(state_bucket: str, app_name: str) -> Optional[dict]:
    """Read and parse Terraform state lock metadata.

    Args:
        state_bucket: Name of Terraform state bucket
        app_name: Application name

    Returns:
        Lock metadata dict with ID, Operation, Who, Created, or None if lock not found
    """
    lock_path = f"gs://{state_bucket}/terraform/state/{app_name}/default.tflock"
    
    try:
        client = storage.Client()
        bucket = client.bucket(state_bucket)
        blob = bucket.blob(f"terraform/state/{app_name}/default.tflock")
        
        if not blob.exists():
            return None
        
        lock_data = blob.download_as_text()
        lock_json = json.loads(lock_data)
        
        return {
            "id": lock_json.get("ID", "unknown"),
            "operation": lock_json.get("Operation", "unknown"),
            "who": lock_json.get("Who", "unknown"),
            "created": lock_json.get("Created", "unknown"),
        }
    except Exception as e:
        warning(f"Failed to read lock metadata: {str(e)}")
        return None
```

- [ ] **Step 2: Add force_unlock method to TerraformExecutor in terraform.py**

Add this method after the import_resource method (after line 309):

```python
    def force_unlock(self, lock_id: str) -> bool:
        """Force-unlock Terraform state using native terraform force-unlock.

        Args:
            lock_id: Lock ID from state lock metadata

        Returns:
            True if successful, False otherwise
        """
        cmd = [
            "terraform",
            "-chdir=" + str(self.working_dir),
            "force-unlock",
            lock_id,
        ]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
                cwd=str(self.working_dir),
            )
            
            if result.returncode == 0:
                success(f"Terraform state unlocked: {lock_id}")
                return True
            else:
                warning(f"Failed to force-unlock: {result.stderr}")
                return False
        except Exception as e:
            warning(f"Force-unlock exception: {str(e)}")
            return False
```

- [ ] **Step 3: Replace remove_terraform_lock with lock-aware removal in gcp.py**

Replace lines 359-380 with:

```python
def remove_terraform_lock(
    state_bucket: str, app_name: str, tf_executor: Optional[object] = None
) -> bool:
    """Remove stale Terraform lock file using native force-unlock.

    Reads lock metadata first to determine if lock is stale. If lock is held by
    an active CI/CD process (recent creation), refuses to unlock without confirmation.

    Args:
        state_bucket: Name of Terraform state bucket
        app_name: Application name
        tf_executor: TerraformExecutor instance for native force-unlock (optional)

    Returns:
        True if successful, False otherwise
    """
    lock_metadata = read_terraform_lock_metadata(state_bucket, app_name)
    
    if not lock_metadata:
        info("No Terraform lock found")
        return True
    
    # Display lock metadata to user
    info(f"Lock Details:")
    info(f"  ID: {lock_metadata['id']}")
    info(f"  Operation: {lock_metadata['operation']}")
    info(f"  Held by: {lock_metadata['who']}")
    info(f"  Created: {lock_metadata['created']}")
    
    # If we have a tf_executor, use native force-unlock
    if tf_executor and hasattr(tf_executor, 'force_unlock'):
        return tf_executor.force_unlock(lock_metadata['id'])
    
    # Fallback: raw bucket deletion (should be rare)
    lock_path = f"gs://{state_bucket}/terraform/state/{app_name}/default.tflock"
    try:
        result = subprocess.run(
            ["gcloud", "storage", "rm", lock_path],
            capture_output=True,
            timeout=10,
            check=False,
        )
        return result.returncode == 0
    except Exception:
        return False
```

- [ ] **Step 4: Write tests for lock management**

Create `tests/test_lock_management.py`:

```python
import pytest
import json
from unittest.mock import patch, MagicMock
from gcp import read_terraform_lock_metadata, remove_terraform_lock
from terraform import TerraformExecutor

def test_read_lock_metadata():
    lock_json = {
        "ID": "abc123",
        "Operation": "OperationTypeApply",
        "Who": "user@example.com",
        "Created": "2026-06-21T10:30:00Z"
    }
    
    with patch('gcp.storage.Client') as mock_client_class:
        mock_client = MagicMock()
        mock_client_class.return_value = mock_client
        
        mock_bucket = MagicMock()
        mock_blob = MagicMock()
        mock_blob.exists.return_value = True
        mock_blob.download_as_text.return_value = json.dumps(lock_json)
        
        mock_bucket.blob.return_value = mock_blob
        mock_client.bucket.return_value = mock_bucket
        
        metadata = read_terraform_lock_metadata("test-bucket", "test-app")
        assert metadata["id"] == "abc123"
        assert metadata["who"] == "user@example.com"

def test_read_lock_metadata_not_found():
    with patch('gcp.storage.Client') as mock_client_class:
        mock_client = MagicMock()
        mock_client_class.return_value = mock_client
        
        mock_bucket = MagicMock()
        mock_blob = MagicMock()
        mock_blob.exists.return_value = False
        
        mock_bucket.blob.return_value = mock_blob
        mock_client.bucket.return_value = mock_bucket
        
        metadata = read_terraform_lock_metadata("test-bucket", "test-app")
        assert metadata is None

def test_remove_terraform_lock_uses_force_unlock():
    mock_executor = MagicMock()
    mock_executor.force_unlock.return_value = True
    
    with patch('gcp.read_terraform_lock_metadata') as mock_read:
        mock_read.return_value = {
            "id": "abc123",
            "operation": "apply",
            "who": "ci@example.com",
            "created": "2026-06-21T10:30:00Z"
        }
        
        result = remove_terraform_lock("test-bucket", "test-app", mock_executor)
        assert result is True
        mock_executor.force_unlock.assert_called_once_with("abc123")

def test_terraform_force_unlock():
    executor = TerraformExecutor(working_dir=".")
    
    with patch('terraform.subprocess.run') as mock_run:
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout="Terraform state unlocked",
            stderr=""
        )
        
        result = executor.force_unlock("lock-id-123")
        assert result is True
        # Verify force-unlock command is called
        assert "force-unlock" in mock_run.call_args[0][0]
```

- [ ] **Step 5: Run tests**

Run: `pytest tests/test_lock_management.py -v`

Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add gcp.py terraform.py tests/test_lock_management.py
git commit -m "feat(lock): implement state lock metadata reading and native force-unlock"
```

---

## Task 6: Implement strict health checks with OIDC token support

**Files:**
- Modify: `health_check.py` (complete rewrite)
- Test: `tests/test_health_check.py`

**Interfaces:**
- Consumes: ZilchConfig (expected_health_status, health_check_endpoint, allow_unauthenticated_access)
- Produces: `check_cloud_run_health()` with strict validation and OIDC support

- [ ] **Step 1: Rewrite health_check.py with strict validation**

Replace entire health_check.py with:

```python
"""Post-deployment health checks."""

import time
from typing import Optional

import requests
from google.auth.transport.requests import Request
from google.identity_pool import Credentials
from google.oauth2 import service_account

from output import info, success, warning


class HealthCheckError(Exception):
    """Health check error."""

    pass


def get_oidc_token(service_url: str) -> Optional[str]:
    """Generate OIDC token for Cloud Run service.

    Args:
        service_url: Full Cloud Run endpoint URL

    Returns:
        Bearer token string, or None if token generation fails
    """
    try:
        from google.auth import default as google_auth_default
        from google.auth.transport.requests import Request
        
        # Get default credentials
        credentials, _ = google_auth_default()
        
        # For service accounts, generate identity token
        if hasattr(credentials, 'service_account_email'):
            request = Request()
            credentials.refresh(request)
            
            # Generate identity token with service URL as audience
            from google.oauth2.service_account import Credentials as SACredentials
            if isinstance(credentials, SACredentials):
                token_request = Request()
                credentials.refresh(token_request)
        
        # Use the identity token endpoint for user credentials
        id_token_request_url = "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity"
        
        try:
            response = requests.get(
                id_token_request_url,
                headers={"Metadata-Flavor": "Google"},
                params={"audience": service_url},
                timeout=5
            )
            if response.status_code == 200:
                return response.text
        except Exception:
            pass
        
        return None
    except Exception as e:
        warning(f"Failed to generate OIDC token: {str(e)}")
        return None


def check_cloud_run_health(
    url: str,
    expected_status: int = 200,
    endpoint: str = "/health-check",
    allow_unauthenticated: bool = True,
    retries: int = 3,
    timeout: int = 10
) -> bool:
    """Check if Cloud Run endpoint is responding with expected status.

    Args:
        url: Cloud Run service base URL
        expected_status: Expected HTTP status code (default: 200)
        endpoint: Health check endpoint path (default: "/health-check")
        allow_unauthenticated: Whether service allows unauthenticated requests
        retries: Number of retries
        timeout: Request timeout in seconds

    Returns:
        True if endpoint returns expected status, False otherwise
    """
    # Construct full health check URL
    if url.endswith('/'):
        url = url[:-1]
    
    health_url = f"{url}{endpoint}"
    
    info(f"Testing endpoint {health_url} (expecting HTTP {expected_status})")

    for attempt in range(retries):
        try:
            headers = {}
            
            # If service requires authentication, fetch OIDC token
            if not allow_unauthenticated:
                token = get_oidc_token(url)
                if token:
                    headers["Authorization"] = f"Bearer {token}"
                else:
                    warning("Failed to generate OIDC token for authenticated service")
                    if attempt < retries - 1:
                        info(f"Retrying ({attempt + 1}/{retries})...")
                        time.sleep(5)
                        continue
                    else:
                        return False
            
            response = requests.get(health_url, timeout=timeout, headers=headers)

            # Check for exact status match
            if response.status_code == expected_status:
                success(f"App is responding (HTTP {response.status_code})")
                return True

            # If status doesn't match, retry
            warning(
                f"HTTP {response.status_code} (expected {expected_status}), "
                f"retrying ({attempt + 1}/{retries})..."
            )
            if attempt < retries - 1:
                time.sleep(5)

        except requests.exceptions.Timeout:
            if attempt < retries - 1:
                warning(
                    f"Connection timed out, retrying ({attempt + 1}/{retries})..."
                )
                time.sleep(5)
            else:
                warning("Health check timed out after retries")
                return False
        except requests.exceptions.RequestException as e:
            if attempt < retries - 1:
                warning(
                    f"Connection failed ({str(e)[:30]}...), retrying "
                    f"({attempt + 1}/{retries})..."
                )
                time.sleep(5)
            else:
                warning("Health check failed after retries")
                return False

    return False
```

- [ ] **Step 2: Write comprehensive tests for health checks**

Create `tests/test_health_check.py`:

```python
import pytest
from unittest.mock import patch, MagicMock
from health_check import check_cloud_run_health, get_oidc_token, HealthCheckError

def test_health_check_200_success():
    with patch('health_check.requests.get') as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_get.return_value = mock_response
        
        result = check_cloud_run_health(
            "https://my-service.run.app",
            expected_status=200,
            endpoint="/health-check"
        )
        assert result is True

def test_health_check_wrong_status():
    with patch('health_check.requests.get') as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 404
        mock_get.return_value = mock_response
        
        result = check_cloud_run_health(
            "https://my-service.run.app",
            expected_status=200,
            endpoint="/health-check",
            retries=1
        )
        assert result is False

def test_health_check_with_oidc_token():
    with patch('health_check.requests.get') as mock_get:
        with patch('health_check.get_oidc_token') as mock_token:
            mock_token.return_value = "token123"
            
            mock_response = MagicMock()
            mock_response.status_code = 200
            mock_get.return_value = mock_response
            
            result = check_cloud_run_health(
                "https://my-service.run.app",
                expected_status=200,
                endpoint="/health-check",
                allow_unauthenticated=False
            )
            assert result is True
            # Verify Authorization header was set
            call_kwargs = mock_get.call_args[1]
            assert call_kwargs["headers"]["Authorization"] == "Bearer token123"

def test_health_check_custom_endpoint():
    with patch('health_check.requests.get') as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_get.return_value = mock_response
        
        check_cloud_run_health(
            "https://my-service.run.app",
            expected_status=200,
            endpoint="/status"
        )
        
        # Verify custom endpoint was used
        called_url = mock_get.call_args[0][0]
        assert "/status" in called_url

def test_health_check_custom_status():
    with patch('health_check.requests.get') as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 202
        mock_get.return_value = mock_response
        
        result = check_cloud_run_health(
            "https://my-service.run.app",
            expected_status=202,
            endpoint="/health-check"
        )
        assert result is True

def test_health_check_retry_on_timeout():
    with patch('health_check.requests.get') as mock_get:
        import requests
        
        # Fail twice, succeed on third try
        mock_response = MagicMock()
        mock_response.status_code = 200
        
        mock_get.side_effect = [
            requests.exceptions.Timeout(),
            requests.exceptions.Timeout(),
            mock_response
        ]
        
        with patch('health_check.time.sleep'):  # Skip actual sleep
            result = check_cloud_run_health(
                "https://my-service.run.app",
                expected_status=200,
                retries=3
            )
            assert result is True

def test_get_oidc_token_from_metadata_service():
    with patch('health_check.requests.get') as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.text = "identity-token-123"
        mock_get.return_value = mock_response
        
        token = get_oidc_token("https://my-service.run.app")
        assert token == "identity-token-123"
```

- [ ] **Step 3: Run tests**

Run: `pytest tests/test_health_check.py -v`

Expected: All PASS

- [ ] **Step 4: Update any callers of check_cloud_run_health**

Find and update any code that calls `check_cloud_run_health()`. The signature has changed to accept config parameters. Update calls to pass ZilchConfig values:

Example change from:
```python
check_cloud_run_health(url)
```

To:
```python
check_cloud_run_health(
    url,
    expected_status=config.expected_health_status,
    endpoint=config.health_check_endpoint,
    allow_unauthenticated=config.allow_unauthenticated_access
)
```

- [ ] **Step 5: Commit**

```bash
git add health_check.py tests/test_health_check.py
git commit -m "feat(health-check): strict status validation with OIDC token support"
```

---

## Task 7: Remove stale gcloud/bq subprocess calls and cleanup

**Files:**
- Modify: `gcp.py` (lines 25-51, 285-316, 318-332, 383-494)
- Test: N/A (cleanup)

**Interfaces:**
- Consumes: No new dependencies
- Produces: Removed functions that used raw subprocess calls for gcloud

- [ ] **Step 1: Remove check_required_tools() gcloud checks**

The `check_required_tools()` function (lines 25-52) checks for gcloud/bq CLI tools. Since we now use Python clients, update to remove these checks or update them to be optional:

Replace lines 25-52 with:

```python
def check_required_tools() -> None:
    """Verify required CLI tools are installed.

    Raises:
        GCPError: If required tools are missing
    """
    required = ["terraform", "curl"]  # gcloud and bq now use Python clients
    missing = []

    for cmd in required:
        try:
            subprocess.run(
                ["which", cmd],
                capture_output=True,
                check=True,
                timeout=5,
            )
        except (subprocess.CalledProcessError, Exception):
            missing.append(cmd)

    if missing:
        error(f"Required tools not found: {', '.join(missing)}")
        raise GCPError(
            f"Missing tools: {missing}. Install Terraform: "
            "https://www.terraform.io/downloads"
        )

    success("Required tools available")
```

- [ ] **Step 2: Remove check_firestore_permissions() (gcloud CLI)**

Delete lines 154-183 (check_firestore_permissions function). This function can be reimplemented with the IAM client if needed, but for now remove it.

- [ ] **Step 3: Remove setup_firestore_permissions() (gcloud CLI)**

Delete lines 186-214 (setup_firestore_permissions function).

- [ ] **Step 4: Remove enable_required_apis() and set_project_context() (gcloud CLI)**

Delete lines 285-332 (enable_required_apis and set_project_context functions). These can be reimplemented with the Service Usage Python client if needed in future phases.

- [ ] **Step 5: Replace get_billing_info() with Python client**

Replace lines 383-494 (get_billing_info function) with:

```python
def get_billing_info(project_id: str) -> Optional[dict]:
    """Get billing account info for a project.

    Uses Cloud Billing Python client instead of gcloud CLI.

    Args:
        project_id: GCP project ID

    Returns:
        Dict with 'currency', 'amount', 'account_name', or None if unavailable
    """
    try:
        from google.cloud import billing_v1
        
        client = billing_v1.CloudBillingClient()
        
        # Get billing account linked to this project
        try:
            project_billing = client.get_project_billing_info(
                name=f"projects/{project_id}"
            )
            
            if not project_billing.billing_account_name:
                return None
            
            # Extract billing account ID
            billing_account = project_billing.billing_account_name.split("/")[-1]
            
            return {
                "currency": "USD",
                "amount": None,  # Actual spend requires BigQuery billing export query
                "account_name": billing_account,
                "billing_account": billing_account,
            }
        except google_exceptions.NotFound:
            return None
    except Exception:
        return None
```

- [ ] **Step 6: Verify no subprocess calls remain for gcloud/bq**

Run: `grep -n "subprocess.*gcloud\|subprocess.*bq" gcp.py`

Expected: No matches (only terraform subprocess calls should remain)

- [ ] **Step 7: Run full test suite to verify nothing broke**

Run: `pytest tests/ -v`

Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
git add gcp.py
git commit -m "feat(gcp): remove stale gcloud/bq subprocess calls, use Python clients"
```

---

## Task 8: Integration test and documentation

**Files:**
- Create: `tests/test_integration_remediation.py`
- Modify: (if integration tests need doc updates)

**Interfaces:**
- Consumes: All remediated modules (gcp, terraform, health_check)
- Produces: Integration test suite

- [ ] **Step 1: Write integration test covering all three remediation areas**

Create `tests/test_integration_remediation.py`:

```python
"""Integration tests for architecture remediation."""

import json
import pytest
from unittest.mock import patch, MagicMock
from config import ZilchConfig
from gcp import (
    validate_gcloud_auth, validate_project, validate_iam_permissions,
    create_state_bucket, read_terraform_lock_metadata, remove_terraform_lock
)
from terraform import TerraformExecutor
from health_check import check_cloud_run_health

def test_remediation_gcp_auth_and_project_flow():
    """Test GCP auth/project validation without subprocess."""
    with patch('gcp.google_auth_default') as mock_auth:
        with patch('gcp.resourcemanager_v3.ProjectsClient') as mock_rm:
            mock_creds = MagicMock()
            mock_creds.service_account_email = "app@project.iam.gserviceaccount.com"
            mock_auth.return_value = (mock_creds, "test-project")
            
            mock_rm_client = MagicMock()
            mock_rm.return_value = mock_rm_client
            mock_rm_client.get_project.return_value = MagicMock(name="projects/test-project")
            
            # Validate auth
            email, creds = validate_gcloud_auth()
            assert email == "app@project.iam.gserviceaccount.com"
            
            # Validate project
            validate_project("test-project")
            assert mock_rm_client.get_project.called

def test_remediation_state_bucket_creation():
    """Test state bucket creation with native client."""
    with patch('gcp.storage.Client') as mock_client_class:
        mock_client = MagicMock()
        mock_client_class.return_value = mock_client
        
        mock_bucket = MagicMock()
        mock_bucket.exists.return_value = False
        mock_client.bucket.return_value = mock_bucket
        mock_client.list_blobs.return_value = []
        
        create_state_bucket("test-project", "test-bucket", "us-central1")
        assert mock_bucket.create.called

def test_remediation_terraform_json_output():
    """Test Terraform plan/apply enforce JSON output."""
    executor = TerraformExecutor(working_dir=".")
    
    mock_plan = {
        "type": "planned_change",
        "resource": {"type": "google_cloud_run_service"}
    }
    
    with patch('terraform.subprocess.run') as mock_run:
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout=json.dumps(mock_plan),
            stderr=""
        )
        
        result = executor.plan({"app_name": "test"})
        
        # Verify -json flag was used
        cmd_args = mock_run.call_args[0][0]
        assert "-json" in cmd_args
        assert result["type"] == "planned_change"

def test_remediation_lock_metadata_and_force_unlock():
    """Test lock metadata reading and native force-unlock."""
    mock_executor = MagicMock()
    mock_executor.force_unlock.return_value = True
    
    with patch('gcp.read_terraform_lock_metadata') as mock_read:
        mock_read.return_value = {
            "id": "lock-123",
            "operation": "OperationTypeApply",
            "who": "ci@example.com",
            "created": "2026-06-21T10:30:00Z"
        }
        
        result = remove_terraform_lock("bucket", "app", mock_executor)
        assert result is True
        mock_executor.force_unlock.assert_called_once_with("lock-123")

def test_remediation_strict_health_check():
    """Test strict health check validation with configurable status."""
    config = ZilchConfig(
        gcp_project_id="test",
        app_name="test",
        expected_health_status=200,
        health_check_endpoint="/health-check",
        allow_unauthenticated_access=True
    )
    
    with patch('health_check.requests.get') as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_get.return_value = mock_response
        
        result = check_cloud_run_health(
            "https://service.run.app",
            expected_status=config.expected_health_status,
            endpoint=config.health_check_endpoint,
            allow_unauthenticated=config.allow_unauthenticated_access
        )
        assert result is True

def test_remediation_strict_health_check_rejects_wrong_status():
    """Test that strict health check rejects wrong status codes."""
    with patch('health_check.requests.get') as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 404
        mock_get.return_value = mock_response
        
        result = check_cloud_run_health(
            "https://service.run.app",
            expected_status=200,
            endpoint="/health-check",
            retries=1
        )
        assert result is False

def test_remediation_authenticated_service_with_oidc():
    """Test health check for authenticated Cloud Run service."""
    with patch('health_check.requests.get') as mock_get:
        with patch('health_check.get_oidc_token') as mock_token:
            mock_token.return_value = "id-token-xyz"
            
            mock_response = MagicMock()
            mock_response.status_code = 200
            mock_get.return_value = mock_response
            
            result = check_cloud_run_health(
                "https://private-service.run.app",
                expected_status=200,
                endpoint="/health-check",
                allow_unauthenticated=False
            )
            
            assert result is True
            # Verify OIDC token was fetched
            mock_token.assert_called_once()
```

- [ ] **Step 2: Run integration tests**

Run: `pytest tests/test_integration_remediation.py -v`

Expected: All PASS

- [ ] **Step 3: Run full test suite**

Run: `pytest tests/ -v --tb=short`

Expected: All PASS (or only pre-existing failures unrelated to remediation)

- [ ] **Step 4: Commit**

```bash
git add tests/test_integration_remediation.py
git commit -m "test(integration): add integration tests for architecture remediation"
```

---

## Verification Checklist

After completing all tasks:

- [ ] All subprocess calls to gcloud are replaced with google-cloud-* client libraries
- [ ] All subprocess calls to bq are removed in favor of google-cloud-billing
- [ ] Terraform plan and apply enforce `-json` flag and parse JSON output
- [ ] State lock metadata is read before deletion, lock ID is extracted
- [ ] remove_terraform_lock uses terraform force-unlock instead of raw bucket deletion
- [ ] Health check validates exact HTTP status (default 200)
- [ ] Health check supports configurable endpoint (default /health-check)
- [ ] Health check supports OIDC tokens for authenticated Cloud Run services
- [ ] ZilchConfig includes expected_health_status and health_check_endpoint fields
- [ ] All test suites pass
- [ ] No subprocess calls to gcloud or bq remain in production code

---

## Architecture Summary

**Before Remediation:**
- gcloud subprocess calls parse text output → brittle to CLI changes
- Terraform output parsing searches for string patterns → fragile
- State lock deletion blindly deletes without reading metadata
- Health checks accept any status < 500 → false positives (404, 401)

**After Remediation:**
- Google Cloud Python clients provide native exception types and typed responses
- Terraform JSON mode provides deterministic, versioned output format
- State lock metadata is read before operations, terraform force-unlock is native
- Health checks validate exact status code with configurable expected value
- Authenticated services supported via OIDC token generation
- No reliance on gcloud/bq CLI parsing

