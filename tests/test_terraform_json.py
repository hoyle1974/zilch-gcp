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
