import pytest
from unittest.mock import patch, MagicMock
from health_check import check_cloud_run_health, get_oidc_token, HealthCheckError


def test_health_check_200_success():
    with patch('health_check.requests.get') as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_get.return_value = mock_response

        result = check_cloud_run_health(
            "https://my-service.run.app",
            expected_status=200,
            endpoint="/health-check"
        )
        assert result is True


def test_health_check_wrong_status():
    with patch('health_check.requests.get') as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 404
        mock_get.return_value = mock_response

        result = check_cloud_run_health(
            "https://my-service.run.app",
            expected_status=200,
            endpoint="/health-check",
            retries=1
        )
        assert result is False


def test_health_check_with_oidc_token():
    with patch('health_check.requests.get') as mock_get:
        with patch('health_check.get_oidc_token') as mock_token:
            mock_token.return_value = "token123"

            mock_response = MagicMock()
            mock_response.status_code = 200
            mock_get.return_value = mock_response

            result = check_cloud_run_health(
                "https://my-service.run.app",
                expected_status=200,
                endpoint="/health-check",
                allow_unauthenticated=False
            )
            assert result is True
            # Verify Authorization header was set
            call_kwargs = mock_get.call_args[1]
            assert call_kwargs["headers"]["Authorization"] == "Bearer token123"


def test_health_check_custom_endpoint():
    with patch('health_check.requests.get') as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_get.return_value = mock_response

        check_cloud_run_health(
            "https://my-service.run.app",
            expected_status=200,
            endpoint="/status"
        )

        # Verify custom endpoint was used
        called_url = mock_get.call_args[0][0]
        assert "/status" in called_url


def test_health_check_custom_status():
    with patch('health_check.requests.get') as mock_get:
        mock_response = MagicMock()
        mock_response.status_code = 202
        mock_get.return_value = mock_response

        result = check_cloud_run_health(
            "https://my-service.run.app",
            expected_status=202,
            endpoint="/health-check"
        )
        assert result is True


def test_health_check_retry_on_timeout():
    with patch('health_check.requests.get') as mock_get:
        import requests

        # Fail twice, succeed on third try
        mock_response = MagicMock()
        mock_response.status_code = 200

        mock_get.side_effect = [
            requests.exceptions.Timeout(),
            requests.exceptions.Timeout(),
            mock_response
        ]

        with patch('health_check.time.sleep'):  # Skip actual sleep
            result = check_cloud_run_health(
                "https://my-service.run.app",
                expected_status=200,
                retries=3
            )
            assert result is True
