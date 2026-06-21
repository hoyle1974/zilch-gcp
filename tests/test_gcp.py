"""Tests for GCP module."""

import subprocess

import pytest
from unittest.mock import MagicMock, patch

import gcp


def test_check_required_tools_success(mocker):
    """Test checking required tools when all are present."""
    mocker.patch(
        "subprocess.run",
        return_value=MagicMock(returncode=0),
    )

    # Should not raise
    gcp.check_required_tools()


def test_check_required_tools_missing(mocker):
    """Test checking required tools when some are missing."""
    mocker.patch(
        "subprocess.run",
        side_effect=Exception("command not found"),
    )

    with pytest.raises(gcp.GCPError):
        gcp.check_required_tools()


def test_validate_gcloud_auth_success(mocker):
    """Test validating gcloud authentication."""
    mock_creds = MagicMock()
    mock_creds.service_account_email = "user@example.com"
    mocker.patch("gcp.google_auth_default", return_value=(mock_creds, "test-project"))

    email, creds = gcp.validate_gcloud_auth()
    assert email == "user@example.com"
    assert creds == mock_creds


def test_validate_gcloud_auth_failure(mocker):
    """Test gcloud authentication failure."""
    mocker.patch("gcp.google_auth_default", side_effect=Exception("No credentials"))

    with pytest.raises(gcp.GCPError, match="Failed to authenticate"):
        gcp.validate_gcloud_auth()


def test_validate_project_success(mocker):
    """Test validating GCP project."""
    mock_client = MagicMock()
    mocker.patch("gcp.resourcemanager_v3.ProjectsClient", return_value=mock_client)
    mock_client.get_project.return_value = MagicMock(name="projects/test-project")

    # Should not raise
    gcp.validate_project("test-project")


def test_validate_project_not_found(mocker):
    """Test validating nonexistent GCP project."""
    from google.api_core.exceptions import NotFound
    mock_client = MagicMock()
    mocker.patch("gcp.resourcemanager_v3.ProjectsClient", return_value=mock_client)
    mock_client.get_project.side_effect = NotFound("not found")

    with pytest.raises(gcp.GCPError):
        gcp.validate_project("nonexistent-project")


def test_check_firestore_permissions_has_permission(mocker):
    """Test checking Firestore permissions when user has them."""
    mock_run = mocker.patch("subprocess.run")
    mock_run.return_value = MagicMock(
        stdout="user:test@example.com\n",
        returncode=0,
    )

    result = gcp.check_firestore_permissions("project", "test@example.com")
    assert result is True


def test_check_firestore_permissions_no_permission(mocker):
    """Test checking Firestore permissions when user doesn't have them."""
    mock_run = mocker.patch("subprocess.run")
    mock_run.return_value = MagicMock(
        stdout="",
        returncode=0,
    )

    result = gcp.check_firestore_permissions("project", "test@example.com")
    assert result is False


def test_setup_firestore_permissions_success(mocker):
    """Test setting up Firestore permissions."""
    mocker.patch(
        "subprocess.run",
        return_value=MagicMock(returncode=0),
    )

    result = gcp.setup_firestore_permissions("project", "test@example.com")
    assert result is True


def test_setup_firestore_permissions_failure(mocker):
    """Test failing to setup Firestore permissions."""
    mock_run = mocker.patch("subprocess.run")
    mock_run.side_effect = subprocess.CalledProcessError(1, "gcloud")

    result = gcp.setup_firestore_permissions("project", "test@example.com")
    assert result is False


def test_create_state_bucket_already_exists(mocker):
    """Test creating state bucket when it already exists."""
    mock_run = mocker.patch("subprocess.run")

    # First call: bucket describe succeeds
    mock_run.return_value = MagicMock(returncode=0)

    # Should not raise
    gcp.create_state_bucket("project", "bucket-name", "us-central1")


def test_check_terraform_lock_exists(mocker):
    """Test checking if Terraform lock exists."""
    mock_run = mocker.patch("subprocess.run")
    mock_run.return_value = MagicMock(returncode=0)

    result = gcp.check_terraform_lock_exists("bucket", "app")
    assert result is True


def test_check_terraform_lock_not_exists(mocker):
    """Test checking when Terraform lock doesn't exist."""
    mock_run = mocker.patch("subprocess.run")
    mock_run.return_value = MagicMock(returncode=1)

    result = gcp.check_terraform_lock_exists("bucket", "app")
    assert result is False


def test_remove_terraform_lock_success(mocker):
    """Test removing Terraform lock."""
    mocker.patch(
        "subprocess.run",
        return_value=MagicMock(returncode=0),
    )

    result = gcp.remove_terraform_lock("bucket", "app")
    assert result is True


def test_remove_terraform_lock_failure(mocker):
    """Test failing to remove Terraform lock."""
    mock_run = mocker.patch("subprocess.run")
    mock_run.return_value = MagicMock(returncode=1)

    result = gcp.remove_terraform_lock("bucket", "app")
    assert result is False
