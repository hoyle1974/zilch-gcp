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
