import pytest
import json
from unittest.mock import patch, MagicMock

from terraform import TerraformExecutor


def test_terraform_force_unlock():
    """Test force-unlock method on TerraformExecutor."""
    executor = TerraformExecutor(working_dir=".")

    with patch('terraform.subprocess.run') as mock_run:
        mock_run.return_value = MagicMock(
            returncode=0,
            stdout="Terraform state unlocked",
            stderr=""
        )

        result = executor.force_unlock("lock-id-123")
        assert result is True
        assert "force-unlock" in mock_run.call_args[0][0]


def test_terraform_force_unlock_failure():
    """Test force-unlock when subprocess fails."""
    executor = TerraformExecutor(working_dir=".")

    with patch('terraform.subprocess.run') as mock_run:
        mock_run.return_value = MagicMock(
            returncode=1,
            stdout="",
            stderr="Lock not found"
        )

        result = executor.force_unlock("lock-id-123")
        assert result is False


def test_terraform_force_unlock_exception():
    """Test force-unlock when exception occurs."""
    executor = TerraformExecutor(working_dir=".")

    with patch('terraform.subprocess.run') as mock_run:
        mock_run.side_effect = Exception("Command failed")

        result = executor.force_unlock("lock-id-123")
        assert result is False


@patch('gcp.storage.Client')
def test_read_lock_metadata(mock_client_class):
    """Test reading lock metadata from GCS."""
    import gcp

    lock_json = {
        "ID": "abc123",
        "Operation": "OperationTypeApply",
        "Who": "user@example.com",
        "Created": "2026-06-21T10:30:00Z"
    }

    mock_client = MagicMock()
    mock_client_class.return_value = mock_client

    mock_bucket = MagicMock()
    mock_blob = MagicMock()
    mock_blob.exists.return_value = True
    mock_blob.download_as_text.return_value = json.dumps(lock_json)

    mock_bucket.blob.return_value = mock_blob
    mock_client.bucket.return_value = mock_bucket

    metadata = gcp.read_terraform_lock_metadata("test-bucket", "test-app")
    assert metadata["id"] == "abc123"
    assert metadata["who"] == "user@example.com"
    assert metadata["operation"] == "OperationTypeApply"


@patch('gcp.storage.Client')
def test_read_lock_metadata_not_found(mock_client_class):
    """Test reading lock metadata when lock doesn't exist."""
    import gcp

    mock_client = MagicMock()
    mock_client_class.return_value = mock_client

    mock_bucket = MagicMock()
    mock_blob = MagicMock()
    mock_blob.exists.return_value = False

    mock_bucket.blob.return_value = mock_blob
    mock_client.bucket.return_value = mock_bucket

    metadata = gcp.read_terraform_lock_metadata("test-bucket", "test-app")
    assert metadata is None


@patch('gcp.read_terraform_lock_metadata')
def test_remove_terraform_lock_uses_force_unlock(mock_read):
    """Test remove_terraform_lock uses force-unlock when executor available."""
    import gcp

    mock_executor = MagicMock()
    mock_executor.force_unlock.return_value = True

    mock_read.return_value = {
        "id": "abc123",
        "operation": "apply",
        "who": "ci@example.com",
        "created": "2026-06-21T10:30:00Z"
    }

    result = gcp.remove_terraform_lock("test-bucket", "test-app", mock_executor)
    assert result is True
    mock_executor.force_unlock.assert_called_once_with("abc123")


def test_remove_terraform_lock_fallback_no_executor():
    """Test remove_terraform_lock uses gcloud fallback when executor is None."""
    import gcp

    with patch('gcp.read_terraform_lock_metadata') as mock_read:
        with patch('gcp.subprocess.run') as mock_run:
            mock_read.return_value = {
                "id": "abc123",
                "operation": "apply",
                "who": "user@example.com",
                "created": "2026-06-21T10:30:00Z"
            }
            mock_run.return_value = MagicMock(returncode=0)

            result = gcp.remove_terraform_lock("test-bucket", "test-app", tf_executor=None)
            assert result is True
            # Verify gcloud rm was called as fallback
            assert "storage" in mock_run.call_args[0][0][1]
