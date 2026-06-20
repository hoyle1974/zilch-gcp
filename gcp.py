"""GCP validation and operations."""

import os
import subprocess
from typing import Optional

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
    required = ["gcloud", "terraform", "curl", "bq"]
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
            f"Missing tools: {missing}. Install gcloud SDK: "
            "https://cloud.google.com/sdk/docs/install"
        )

    success("Required tools available")


def validate_gcloud_auth() -> str:
    """Validate gcloud authentication.

    Returns:
        Currently authenticated account email

    Raises:
        GCPError: If not authenticated
    """
    try:
        result = subprocess.run(
            [
                "gcloud",
                "auth",
                "list",
                "--filter=status:ACTIVE",
                "--format=value(account)",
            ],
            capture_output=True,
            text=True,
            timeout=10,
            check=True,
        )

        accounts = result.stdout.strip().split("\n")
        current_user = accounts[0] if accounts and accounts[0] else None

        if not current_user or "@" not in current_user:
            raise GCPError("No active gcloud authentication found")

        success(f"Authenticated as {current_user}")
        return current_user

    except subprocess.CalledProcessError as e:
        raise GCPError(f"Failed to check authentication: {e.stderr}")


def validate_project(project_id: str) -> None:
    """Validate GCP project exists and user has access.

    Args:
        project_id: GCP project ID

    Raises:
        GCPError: If project doesn't exist or user has no access
    """
    try:
        subprocess.run(
            ["gcloud", "projects", "describe", project_id],
            capture_output=True,
            timeout=10,
            check=True,
        )
        success(f"Project {project_id}")
    except (subprocess.CalledProcessError, Exception):
        raise GCPError(
            f"Project {project_id} not found or no access. "
            "Verify the project ID and your credentials."
        )


def validate_iam_permissions(project_id: str, current_user: str) -> None:
    """Validate user has Editor or Owner role.

    Args:
        project_id: GCP project ID
        current_user: Currently authenticated user email

    Raises:
        GCPError: If user lacks required permissions
    """
    try:
        result = subprocess.run(
            [
                "gcloud",
                "projects",
                "get-iam-policy",
                project_id,
                "--flatten=bindings[].members",
                "--filter=bindings.members:user:" + current_user
                + " AND (bindings.role:roles/editor OR bindings.role:roles/owner)",
                "--format=value(bindings.role)",
            ],
            capture_output=True,
            text=True,
            timeout=10,
            check=True,
        )

        if not result.stdout.strip():
            raise GCPError(
                f"User {current_user} needs Editor or Owner role on {project_id}"
            )

        success("IAM permissions OK")
    except subprocess.CalledProcessError as e:
        raise GCPError(f"Failed to check IAM permissions: {e.stderr}")


def check_firestore_permissions(project_id: str, current_user: str) -> bool:
    """Check if user has Firestore Admin role.

    Args:
        project_id: GCP project ID
        current_user: Currently authenticated user email

    Returns:
        True if user has permission, False otherwise
    """
    try:
        result = subprocess.run(
            [
                "gcloud",
                "projects",
                "get-iam-policy",
                project_id,
                "--flatten=bindings[].members",
                "--filter=bindings.role:roles/datastore.admin",
                "--format=value(bindings.members)",
            ],
            capture_output=True,
            text=True,
            timeout=10,
            check=True,
        )

        return f"user:{current_user}" in result.stdout
    except subprocess.CalledProcessError:
        return False


def setup_firestore_permissions(project_id: str, current_user: str) -> bool:
    """Attempt to grant user Firestore Admin role.

    Args:
        project_id: GCP project ID
        current_user: Currently authenticated user email

    Returns:
        True if successful, False otherwise
    """
    try:
        subprocess.run(
            [
                "gcloud",
                "projects",
                "add-iam-policy-binding",
                project_id,
                f"--member=user:{current_user}",
                "--role=roles/datastore.admin",
                "--quiet",
            ],
            capture_output=True,
            timeout=10,
            check=True,
        )
        success("Firestore Admin role granted")
        return True
    except (subprocess.CalledProcessError, Exception):
        return False


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

    # Check if bucket already exists
    try:
        subprocess.run(
            ["gcloud", "storage", "buckets", "describe", f"gs://{bucket_name}"],
            capture_output=True,
            timeout=10,
            check=True,
        )
        success("Using existing bucket")
        return
    except subprocess.CalledProcessError:
        pass

    # Try to create bucket
    try:
        subprocess.run(
            [
                "gcloud",
                "storage",
                "buckets",
                "create",
                f"gs://{bucket_name}",
                f"--project={project_id}",
                f"--location={region}",
                "--uniform-bucket-level-access",
            ],
            capture_output=True,
            timeout=30,
            check=True,
        )
        success("Created bucket")
    except subprocess.CalledProcessError as e:
        raise GCPError(f"Failed to create state bucket: {e.stderr}")

    # Verify bucket is ready
    max_retries = 15
    for attempt in range(max_retries):
        try:
            subprocess.run(
                ["gcloud", "storage", "ls", f"gs://{bucket_name}/"],
                capture_output=True,
                timeout=10,
                check=True,
            )
            success("Bucket is accessible")
            return
        except subprocess.CalledProcessError:
            if attempt < max_retries - 1:
                info(f"Waiting for bucket ({attempt + 1}/{max_retries})...")
            else:
                raise GCPError("Bucket not accessible after retries")


def enable_required_apis(project_id: str, enable_mysql: bool = False) -> None:
    """Enable required GCP APIs.

    Args:
        project_id: GCP project ID
        enable_mysql: Whether to enable Compute Engine API for MySQL
    """
    info("Enabling required APIs")

    apis = ["cloudresourcemanager.googleapis.com"]
    if enable_mysql:
        apis.append("compute.googleapis.com")

    for api in apis:
        try:
            subprocess.run(
                [
                    "gcloud",
                    "services",
                    "enable",
                    api,
                    f"--project={project_id}",
                    "--quiet",
                ],
                capture_output=True,
                timeout=30,
                check=True,
            )
            success(f"API enabled: {api.split('.')[0]}")
        except subprocess.CalledProcessError as e:
            warning(f"Failed to enable {api}: {e.stderr}")


def set_project_context(project_id: str) -> None:
    """Set gcloud default project.

    Args:
        project_id: GCP project ID
    """
    try:
        subprocess.run(
            ["gcloud", "config", "set", "project", project_id, "--quiet"],
            capture_output=True,
            timeout=10,
            check=True,
        )
    except subprocess.CalledProcessError:
        warning("Could not set gcloud project context")


def check_terraform_lock_exists(state_bucket: str, app_name: str) -> bool:
    """Check if Terraform state lock file exists.

    Args:
        state_bucket: Name of Terraform state bucket
        app_name: Application name

    Returns:
        True if lock exists, False otherwise
    """
    lock_path = f"gs://{state_bucket}/terraform/state/{app_name}/default.tflock"

    try:
        result = subprocess.run(
            ["gcloud", "storage", "ls", lock_path],
            capture_output=True,
            timeout=10,
            check=False,
        )
        return result.returncode == 0
    except Exception:
        return False


def remove_terraform_lock(state_bucket: str, app_name: str) -> bool:
    """Remove stale Terraform lock file.

    Args:
        state_bucket: Name of Terraform state bucket
        app_name: Application name

    Returns:
        True if successful, False otherwise
    """
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
