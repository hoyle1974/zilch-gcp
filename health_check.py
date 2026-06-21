"""Post-deployment health checks."""

import time
from typing import Optional

import requests

from output import info, success, warning


class HealthCheckError(Exception):
    """Health check error."""

    pass


def get_oidc_token(service_url: str) -> Optional[str]:
    """Generate OIDC token for Cloud Run service.

    Args:
        service_url: Full Cloud Run endpoint URL

    Returns:
        Bearer token string, or None if token generation fails
    """
    try:
        from google.auth import default as google_auth_default
        from google.auth.transport.requests import Request

        # Get default credentials
        credentials, _ = google_auth_default()

        # For service accounts, generate identity token
        if hasattr(credentials, 'service_account_email'):
            request = Request()
            credentials.refresh(request)

            # Generate identity token with service URL as audience
            from google.oauth2.service_account import Credentials as SACredentials
            if isinstance(credentials, SACredentials):
                token_request = Request()
                credentials.refresh(token_request)

        # Use the identity token endpoint for user credentials
        id_token_request_url = "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity"

        try:
            response = requests.get(
                id_token_request_url,
                headers={"Metadata-Flavor": "Google"},
                params={"audience": service_url},
                timeout=5
            )
            if response.status_code == 200:
                return response.text
        except Exception:
            pass

        return None
    except Exception as e:
        warning(f"Failed to generate OIDC token: {str(e)}")
        return None


def check_cloud_run_health(
    url: str,
    expected_status: int = 200,
    endpoint: str = "/health-check",
    allow_unauthenticated: bool = True,
    retries: int = 3,
    timeout: int = 10
) -> bool:
    """Check if Cloud Run endpoint is responding with expected status.

    Args:
        url: Cloud Run service base URL
        expected_status: Expected HTTP status code (default: 200)
        endpoint: Health check endpoint path (default: "/health-check")
        allow_unauthenticated: Whether service allows unauthenticated requests
        retries: Number of retries
        timeout: Request timeout in seconds

    Returns:
        True if endpoint returns expected status, False otherwise
    """
    # Construct full health check URL
    if url.endswith('/'):
        url = url[:-1]

    health_url = f"{url}{endpoint}"

    info(f"Testing endpoint {health_url} (expecting HTTP {expected_status})")

    for attempt in range(retries):
        try:
            headers = {}

            # If service requires authentication, fetch OIDC token
            if not allow_unauthenticated:
                token = get_oidc_token(url)
                if token:
                    headers["Authorization"] = f"Bearer {token}"
                else:
                    warning("Failed to generate OIDC token for authenticated service")
                    if attempt < retries - 1:
                        info(f"Retrying ({attempt + 1}/{retries})...")
                        time.sleep(5)
                        continue
                    else:
                        return False

            response = requests.get(health_url, timeout=timeout, headers=headers)

            # Check for exact status match
            if response.status_code == expected_status:
                success(f"App is responding (HTTP {response.status_code})")
                return True

            # If status doesn't match, retry
            warning(
                f"HTTP {response.status_code} (expected {expected_status}), "
                f"retrying ({attempt + 1}/{retries})..."
            )
            if attempt < retries - 1:
                time.sleep(5)

        except requests.exceptions.Timeout:
            if attempt < retries - 1:
                warning(
                    f"Connection timed out, retrying ({attempt + 1}/{retries})..."
                )
                time.sleep(5)
            else:
                warning("Health check timed out after retries")
                return False
        except requests.exceptions.RequestException as e:
            if attempt < retries - 1:
                warning(
                    f"Connection failed ({str(e)[:30]}...), retrying "
                    f"({attempt + 1}/{retries})..."
                )
                time.sleep(5)
            else:
                warning("Health check failed after retries")
                return False

    return False
