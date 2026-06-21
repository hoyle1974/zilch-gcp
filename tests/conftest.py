"""Pytest configuration and fixtures."""

import pytest
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock
import sys

# Mock google.cloud imports before any test imports gcp
sys.modules['google'] = MagicMock()
sys.modules['google.auth'] = MagicMock()
sys.modules['google.auth.transport'] = MagicMock()
sys.modules['google.auth.transport.requests'] = MagicMock()
sys.modules['google.cloud'] = MagicMock()
sys.modules['google.iam'] = MagicMock()
sys.modules['google.iam.v1'] = MagicMock()
sys.modules['google.api_core'] = MagicMock()
sys.modules['google.api_core.exceptions'] = MagicMock()


@pytest.fixture
def temp_config_file(tmp_path):
    """Create a temporary config file."""
    config_file = tmp_path / ".zilch.config"
    config_file.write_text("""
gcp_project_id=test-project
app_name=test-app
gcp_region=us-central1
enable_firestore=false
enable_mysql=false
enable_cloud_build=true
allow_unauthenticated_access=true
""")
    return config_file


@pytest.fixture
def sample_config():
    """Create a sample config dictionary."""
    return {
        "gcp_project_id": "test-project",
        "app_name": "test-app",
        "gcp_region": "us-central1",
        "enable_firestore": False,
        "enable_cloud_storage": False,
        "enable_mysql": False,
        "enable_cloud_build": True,
        "allow_unauthenticated_access": True,
        "github_owner": "test-owner",
        "github_repo": "test-repo",
    }


@pytest.fixture
def mock_gcloud(mocker):
    """Mock gcloud CLI calls."""
    return mocker.patch("subprocess.run")


@pytest.fixture
def mock_terraform(mocker):
    """Mock Terraform CLI calls."""
    return mocker.patch("subprocess.run")
