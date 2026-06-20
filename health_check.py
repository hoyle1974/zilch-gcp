"""Post-deployment health checks."""

import time

import requests

from output import info, success, warning


class HealthCheckError(Exception):
    """Health check error."""

    pass


def check_cloud_run_health(url: str, retries: int = 3, timeout: int = 10) -> bool:
    """Check if Cloud Run endpoint is responding.

    Args:
        url: Cloud Run endpoint URL
        retries: Number of retries
        timeout: Request timeout in seconds

    Returns:
        True if endpoint is healthy, False otherwise
    """
    info(f"Testing endpoint {url}")

    for attempt in range(retries):
        try:
            response = requests.get(url, timeout=timeout)

            # Accept 2xx (success), 401 (auth required), 404 (not found)
            # These indicate container is running; reject 5xx (errors)
            if response.status_code < 500:
                success("App is responding")
                return True

            warning(
                f"HTTP {response.status_code}, retrying ({attempt + 1}/{retries})..."
            )
        except requests.exceptions.RequestException as e:
            if attempt < retries - 1:
                warning(
                    f"Connection failed ({str(e)[:30]}...), retrying "
                    f"({attempt + 1}/{retries})..."
                )
                time.sleep(5)
            else:
                warning("Health check timed out")
                return False

    return False
