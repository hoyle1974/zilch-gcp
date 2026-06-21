"""GCP validation and operations."""

import json
import os
import subprocess
import time
from typing import Optional

from google.auth import default as google_auth_default
from google.auth.transport.requests import Request
from google.cloud import resourcemanager_v3
from google.cloud import storage
from google.iam.v1 import iam_policy_pb2
from google.api_core import exceptions as google_exceptions

from output import error, info, success, warning


class GCPError(Exception):
    """GCP operation error."""

    pass


def is_cloud_shell() -> bool:
    """Check if running in Google Cloud Shell.

    Returns:
        True if running in Cloud Shell, False otherwise
    """
    return "CLOUD_SHELL" in os.environ


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
        request = iam_policy_pb2.GetIamPolicyRequest(resource=f"projects/{project_id}")
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
                time.sleep(1)
            else:
                raise GCPError("Bucket not accessible after retries")


def check_terraform_lock_exists(state_bucket: str, app_name: str) -> bool:
    """Check if Terraform state lock file exists.

    Args:
        state_bucket: Name of Terraform state bucket
        app_name: Application name

    Returns:
        True if lock exists, False otherwise
    """
    try:
        client = storage.Client()
        bucket = client.bucket(state_bucket)
        blob = bucket.blob(f"terraform/state/{app_name}/default.tflock")
        return blob.exists()
    except Exception:
        return False


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


def remove_terraform_lock(
    state_bucket: str, app_name: str, tf_executor: Optional[object] = None
) -> bool:
    """Remove stale Terraform lock file using native force-unlock.

    Reads lock metadata first to determine if lock is stale.

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
    try:
        client = storage.Client()
        bucket = client.bucket(state_bucket)
        blob = bucket.blob(f"terraform/state/{app_name}/default.tflock")
        blob.delete()
        return True
    except Exception:
        return False


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
