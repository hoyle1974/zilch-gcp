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
