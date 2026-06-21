"""Tests for config module."""

import pytest
from pathlib import Path
from pydantic import ValidationError

from config import ZilchConfig


def test_config_creation_with_defaults():
    """Test creating config with default values."""
    config = ZilchConfig(
        gcp_project_id="test-project",
        app_name="test-app",
    )

    assert config.gcp_project_id == "test-project"
    assert config.app_name == "test-app"
    assert config.gcp_region == "us-central1"
    assert config.enable_firestore is False


def test_config_app_name_validation():
    """Test app name validation."""
    # Valid names
    config = ZilchConfig(
        gcp_project_id="test-project",
        app_name="my-app-123",
    )
    assert config.app_name == "my-app-123"

    # Invalid: too short
    with pytest.raises(ValidationError, match="Invalid app name"):
        ZilchConfig(
            gcp_project_id="test-project",
            app_name="ab",
        )

    # Invalid: uppercase
    with pytest.raises(ValidationError, match="Invalid app name"):
        ZilchConfig(
            gcp_project_id="test-project",
            app_name="MyApp",
        )

    # Invalid: special characters
    with pytest.raises(ValidationError, match="Invalid app name"):
        ZilchConfig(
            gcp_project_id="test-project",
            app_name="my_app",
        )


def test_config_region_validation():
    """Test region validation."""
    # Valid region
    config = ZilchConfig(
        gcp_project_id="test-project",
        app_name="test-app",
        gcp_region="us-east1",
    )
    assert config.gcp_region == "us-east1"

    # Invalid region
    with pytest.raises(ValidationError, match="Region must be one of"):
        ZilchConfig(
            gcp_project_id="test-project",
            app_name="test-app",
            gcp_region="invalid-region",
        )


def test_config_cron_validation():
    """Test cron expression validation."""
    # Valid cron
    config = ZilchConfig(
        gcp_project_id="test-project",
        app_name="test-app",
        scheduler_schedule="0 0 * * *",
    )
    assert config.scheduler_schedule == "0 0 * * *"

    # Invalid cron (not 5 fields)
    with pytest.raises(ValidationError, match="Cron expression must have 5 fields"):
        ZilchConfig(
            gcp_project_id="test-project",
            app_name="test-app",
            scheduler_schedule="0 0 *",
        )


def test_config_budget_validation():
    """Test budget limit validation."""
    # Valid budget
    config = ZilchConfig(
        gcp_project_id="test-project",
        app_name="test-app",
        billing_budget_limit_usd="100.50",
    )
    assert config.billing_budget_limit_usd == "100.50"

    # Invalid: negative
    with pytest.raises(ValidationError, match="Budget must be positive"):
        ZilchConfig(
            gcp_project_id="test-project",
            app_name="test-app",
            billing_budget_limit_usd="-10",
        )

    # Invalid: not a number
    with pytest.raises(ValidationError, match="Budget must be a number"):
        ZilchConfig(
            gcp_project_id="test-project",
            app_name="test-app",
            billing_budget_limit_usd="invalid",
        )


def test_config_load_from_file(temp_config_file):
    """Test loading config from file."""
    config = ZilchConfig.load_from_file(str(temp_config_file))

    assert config.gcp_project_id == "test-project"
    assert config.app_name == "test-app"
    assert config.gcp_region == "us-central1"


def test_config_save_to_file(tmp_path):
    """Test saving config to file."""
    config = ZilchConfig(
        gcp_project_id="test-project",
        app_name="test-app",
        gcp_region="us-east1",
        enable_firestore=True,
    )

    config_file = tmp_path / ".zilch.config"
    config.save_to_file(str(config_file))

    assert config_file.exists()

    # Load it back
    loaded = ZilchConfig.load_from_file(str(config_file))
    assert loaded.gcp_project_id == "test-project"
    assert loaded.app_name == "test-app"
    assert loaded.gcp_region == "us-east1"
    assert loaded.enable_firestore is True


def test_config_to_terraform_vars():
    """Test converting config to Terraform variables."""
    config = ZilchConfig(
        gcp_project_id="test-project",
        app_name="test-app",
        enable_firestore=True,
        github_owner="owner",
        github_repo="repo",
    )

    vars_dict = config.to_terraform_vars()

    assert vars_dict["gcp_project_id"] == "test-project"
    assert vars_dict["app_name"] == "test-app"
    assert vars_dict["enable_firestore"] is True
    assert vars_dict["github_owner"] == "owner"
    assert vars_dict["github_repo"] == "repo"


def test_config_load_nonexistent_file():
    """Test loading from nonexistent file."""
    with pytest.raises(FileNotFoundError):
        ZilchConfig.load_from_file("/nonexistent/path/.zilch.config")


def test_config_extra_fields_ignored():
    """Test that extra fields in config file are ignored."""
    config = ZilchConfig(
        gcp_project_id="test-project",
        app_name="test-app",
        unknown_field="should be ignored",  # Extra fields
    )

    assert config.gcp_project_id == "test-project"
    assert not hasattr(config, "unknown_field")


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
    with pytest.raises(ValidationError, match="HTTP success code"):
        ZilchConfig(
            gcp_project_id="test-project",
            app_name="test-app",
            expected_health_status=500
        )
