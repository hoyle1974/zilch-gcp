"""Interactive CLI prompts."""

import os
import sys
from typing import Dict, List, Optional

import click
from rich.console import Console

from config import ZilchConfig
from output import info, section


def get_project_id(config: ZilchConfig) -> str:
    """Prompt for GCP project ID.

    Args:
        config: Current config

    Returns:
        Project ID
    """
    section("Configuration")
    default = config.gcp_project_id or ""

    if default:
        prompt = f"GCP Project ID [{default}]"
        user_input = click.prompt(prompt, default=default, show_default=False)
    else:
        prompt = "GCP Project ID"
        user_input = click.prompt(prompt)

    return user_input or default


def get_app_name(config: ZilchConfig) -> str:
    """Prompt for app name.

    Args:
        config: Current config

    Returns:
        App name
    """
    default = config.app_name or "zilch-app"
    prompt = f"App Name [{default}]"
    user_input = click.prompt(prompt, default=default, show_default=False)
    return user_input or default


def get_region(config: ZilchConfig) -> str:
    """Prompt for GCP region.

    Args:
        config: Current config

    Returns:
        Region name
    """
    section("Region")

    regions = {
        "1": ("us-central1", "Iowa"),
        "2": ("us-east1", "South Carolina"),
        "3": ("us-west1", "Oregon"),
    }

    # Show options with current selection marked
    current_key = None
    for key, (region, location) in regions.items():
        if region == config.gcp_region:
            current_key = key
            marker = " ← current"
        else:
            marker = ""
        click.echo(f"  [{key}] {region:<12} ({location}){marker}")

    default_choice = current_key or "1"
    choice = click.prompt(
        f"Select [1-3, default: {default_choice}]",
        default=default_choice,
        show_default=False,
    )

    region_map = {
        "1": "us-central1",
        "2": "us-east1",
        "3": "us-west1",
    }

    return region_map.get(choice, "us-central1")


def prompt_toggle(feature_name: str, current_value: bool) -> bool:
    """Prompt for yes/no toggle.

    Args:
        feature_name: Feature name to display
        current_value: Current value

    Returns:
        Boolean result
    """
    default = "y" if current_value else "n"
    status = click.style("[enabled]", fg="green") if current_value else click.style("[disabled]", fg="cyan")
    result = click.confirm(f"{feature_name}? {status}", default=current_value, show_default=False)
    return result


def _build_service_list(config: ZilchConfig) -> List[Dict[str, str | bool]]:
    """Build list of services with current config state.

    Args:
        config: Current config

    Returns:
        List of dicts with keys: key, name, enabled
    """
    services = [
        {"key": "firestore", "name": "Firestore", "enabled": config.enable_firestore},
        {"key": "cloud_storage", "name": "Cloud Storage", "enabled": config.enable_cloud_storage},
        {"key": "secret_manager", "name": "Secret Manager", "enabled": config.enable_secret_manager},
        {"key": "firebase_auth", "name": "Firebase Auth", "enabled": config.enable_firebase_auth},
        {"key": "vertex_ai", "name": "Vertex AI", "enabled": config.enable_vertex_ai},
        {"key": "pubsub", "name": "Pub/Sub", "enabled": config.enable_pubsub},
        {"key": "cloud_tasks", "name": "Cloud Tasks", "enabled": config.enable_cloud_tasks},
        {"key": "bigquery", "name": "BigQuery", "enabled": config.enable_bigquery},
        {"key": "cloud_kms", "name": "Cloud KMS", "enabled": config.enable_cloud_kms},
        {"key": "vision_ai", "name": "Vision AI", "enabled": config.enable_vision_ai},
        {"key": "speech_to_text", "name": "Speech-to-Text", "enabled": config.enable_speech_to_text},
        {"key": "translation", "name": "Translation", "enabled": config.enable_translation},
        {"key": "scheduler", "name": "Cloud Scheduler", "enabled": config.enable_scheduler},
        {"key": "monitoring", "name": "Cloud Monitoring", "enabled": config.enable_monitoring},
        {"key": "cloud_build", "name": "Cloud Build", "enabled": config.enable_cloud_build},
        {"key": "mysql", "name": "MySQL Database", "enabled": config.enable_mysql},
    ]
    return services


def _apply_services_to_config(services: List[Dict[str, str | bool]], config: ZilchConfig) -> None:
    """Apply service selections back to config object.

    Args:
        services: List of service dicts with enabled state
        config: Config object to update (modified in-place)
    """
    for service in services:
        key = service["key"]
        enabled = service["enabled"]
        attr_name = f"enable_{key}"
        setattr(config, attr_name, enabled)


def _render_menu(console: Console, services: List[Dict[str, str | bool]], current_index: int) -> None:
    """Render the service menu.

    Args:
        console: Rich console for output
        services: List of service dicts
        current_index: Index of currently selected service
    """
    console.clear()
    section("Services Configuration")
    click.echo("Use arrow keys to navigate, space to toggle, enter to confirm")
    click.echo()

    for i, service in enumerate(services):
        checkbox = "[x]" if service["enabled"] else "[ ]"
        name = service["name"]
        cursor = "→ " if i == current_index else "  "
        line = f"{cursor}{checkbox} {name}"

        if i == current_index:
            styled_line = click.style(line, fg="cyan", bold=True)
            click.echo(styled_line)
        else:
            click.echo(line)


def _get_key() -> str:
    """Read a single key from stdin.

    Returns:
        Key string: 'up', 'down', 'space', 'enter', or the raw character
    """
    if os.name == 'nt':  # Windows
        import msvcrt
        key = msvcrt.getch()
        if key == b'\x03':  # Ctrl+C
            raise KeyboardInterrupt()
        if key == b'\xe0':  # Arrow key prefix on Windows
            next_key = msvcrt.getch()
            if next_key == b'H':
                return 'up'
            elif next_key == b'P':
                return 'down'
        elif key == b' ':
            return 'space'
        elif key == b'\r':
            return 'enter'
    else:  # Unix/Linux/Mac
        import tty
        import termios
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        try:
            tty.setraw(fd)
            ch = sys.stdin.read(1)
            if ch == '\x03':  # Ctrl+C
                raise KeyboardInterrupt()
            if ch == '\x1b':  # Escape sequence
                sys.stdin.read(1)  # Skip '['
                ch = sys.stdin.read(1)
                if ch == 'A':
                    return 'up'
                elif ch == 'B':
                    return 'down'
            elif ch == ' ':
                return 'space'
            elif ch == '\r':
                return 'enter'
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

    return 'unknown'


def get_services_interactive(config: ZilchConfig) -> ZilchConfig:
    """Interactive service selection menu.

    Args:
        config: Current config

    Returns:
        Updated config with service choices
    """
    section("Services Configuration")

    services = _build_service_list(config)
    current_index = 0
    console = Console()

    while True:
        _render_menu(console, services, current_index)

        key = _get_key()

        if key == 'down':
            current_index = (current_index + 1) % len(services)
        elif key == 'up':
            current_index = (current_index - 1) % len(services)
        elif key == 'space':
            services[current_index]["enabled"] = not services[current_index]["enabled"]
        elif key == 'enter':
            break

    # Apply selections to config
    _apply_services_to_config(services, config)

    # Show summary
    console.clear()
    section("Selected Services")
    enabled = [s["name"] for s in services if s["enabled"]]
    if enabled:
        for service in enabled:
            click.echo(f"  ✓ {service}")
    else:
        click.echo("  (no services selected)")
    click.echo()

    return config


def get_monitoring_config(config: ZilchConfig) -> ZilchConfig:
    """Prompt for monitoring/budget configuration.

    Args:
        config: Current config

    Returns:
        Updated config with monitoring settings
    """
    section("Budget Configuration")

    budget = click.prompt(
        f"Monthly limit (USD) [{config.billing_budget_limit_usd}]",
        default=config.billing_budget_limit_usd,
        show_default=False,
    )
    config.billing_budget_limit_usd = budget or config.billing_budget_limit_usd

    return config


def get_scheduler_config(config: ZilchConfig) -> ZilchConfig:
    """Prompt for scheduler configuration.

    Args:
        config: Current config

    Returns:
        Updated config with scheduler settings
    """
    section("Scheduler Settings")

    schedule = click.prompt(
        f"Cron expression [{config.scheduler_schedule}]",
        default=config.scheduler_schedule,
        show_default=False,
    )
    config.scheduler_schedule = schedule or config.scheduler_schedule

    endpoint = click.prompt(
        f"Endpoint path [{config.scheduler_endpoint}]",
        default=config.scheduler_endpoint,
        show_default=False,
    )
    config.scheduler_endpoint = endpoint or config.scheduler_endpoint

    return config


def confirm_action(action: str) -> bool:
    """Confirm user action.

    Args:
        action: Action description

    Returns:
        True if confirmed, False otherwise
    """
    return click.confirm(action, default=True)
