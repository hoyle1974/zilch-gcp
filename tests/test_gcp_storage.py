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
        mock_client = MagicMock()
        mock_client_class.return_value = mock_client

        mock_bucket = MagicMock()
        mock_bucket.exists.return_value = False
        mock_client.bucket.return_value = mock_bucket
        mock_client.list_blobs.return_value = []

        create_state_bucket("test-project", "test-bucket", "us-central1")
        mock_bucket.create.assert_called_once()
