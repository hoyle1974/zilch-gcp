"""Interactive CLI prompts."""

from typing import Dict, List, Optional

import click
from InquirerPy import inquirer
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


SERVICE_METADATA = {
    "firestore": {
        "description": "NoSQL document database with real-time sync",
        "docs": "https://cloud.google.com/firestore/docs",
        "cost": "~$0.06 per 100k reads, $0.18 per 100k writes",
    },
    "cloud_storage": {
        "description": "Object storage for files and media",
        "docs": "https://cloud.google.com/storage/docs",
        "cost": "~$0.020 per GB stored, $0.005 per 1k ops",
    },
    "secret_manager": {
        "description": "Secure storage for API keys and passwords",
        "docs": "https://cloud.google.com/secret-manager/docs",
        "cost": "$0.06 per secret per month, $0.06 per 1k ops",
    },
    "firebase_auth": {
        "description": "User authentication and login",
        "docs": "https://firebase.google.com/docs/auth",
        "cost": "Free tier: 50k MAU, pay per additional MAU",
    },
    "vertex_ai": {
        "description": "Machine learning predictions and model training",
        "docs": "https://cloud.google.com/vertex-ai/docs",
        "cost": "Pricing varies by model, ~$0.02-$0.10 per prediction",
    },
    "pubsub": {
        "description": "Event streaming and async messaging",
        "docs": "https://cloud.google.com/pubsub/docs",
        "cost": "~$0.05 per GB ingested, $0.40 per million ops",
    },
    "cloud_tasks": {
        "description": "Task queue for distributed work",
        "docs": "https://cloud.google.com/tasks/docs",
        "cost": "~$0.10 per million tasks",
    },
    "bigquery": {
        "description": "Data warehouse for large-scale SQL analytics",
        "docs": "https://cloud.google.com/bigquery/docs",
        "cost": "~$6.25 per TB queried, storage ~$0.02 per GB/month",
    },
    "cloud_kms": {
        "description": "Key management for encryption",
        "docs": "https://cloud.google.com/kms/docs",
        "cost": "$0.06 per key version per month, $0.03-$0.15 per 1k ops",
    },
    "vision_ai": {
        "description": "Image recognition, OCR, and object detection",
        "docs": "https://cloud.google.com/vision/docs",
        "cost": "~$0.50-$6.00 per 1k images depending on feature",
    },
    "speech_to_text": {
        "description": "Convert audio to text",
        "docs": "https://cloud.google.com/speech-to-text/docs",
        "cost": "~$0.024-$0.048 per minute of audio",
    },
    "translation": {
        "description": "Translate text between languages",
        "docs": "https://cloud.google.com/translate/docs",
        "cost": "~$15 per 1 million characters",
    },
    "scheduler": {
        "description": "Cron jobs for periodic tasks",
        "docs": "https://cloud.google.com/scheduler/docs",
        "cost": "First 3 jobs free, $0.10 per job per month",
    },
    "monitoring": {
        "description": "Logs, metrics, alerts, and budgets",
        "docs": "https://cloud.google.com/monitoring/docs",
        "cost": "~$0.2580 per 1M log entries ingested",
    },
    "cloud_build": {
        "description": "CI/CD build and deployment automation",
        "docs": "https://cloud.google.com/build/docs",
        "cost": "120 free minutes/day, then $0.003 per minute",
    },
    "mysql": {
        "description": "Managed relational SQL database",
        "docs": "https://cloud.google.com/sql/docs",
        "cost": "~$8-$50/month depending on machine type",
    },
}


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




def get_services_interactive(config: ZilchConfig) -> ZilchConfig:
    """Interactive service selection menu.

    Args:
        config: Current config

    Returns:
        Updated config with service choices
    """
    section("Services Configuration")

    services = _build_service_list(config)

    # Build checkbox choices with descriptions
    choices = []
    for service in services:
        meta = SERVICE_METADATA.get(service["key"], {})
        label = f"{service['name']} — {meta.get('description', '')}"
        choices.append({
            "name": label,
            "value": service["key"],
            "enabled": service["enabled"],
        })

    click.echo()
    selected_keys = inquirer.checkbox(
        message="Select services (toggle with Space, navigate with arrows, confirm with Enter):",
        choices=choices,
        border=True,
        instruction="Use arrow keys to navigate, space to toggle, enter to confirm",
    ).execute()

    # Update services based on selection
    selected_set = set(selected_keys)
    for service in services:
        service["enabled"] = service["key"] in selected_set

    # Apply selections to config
    _apply_services_to_config(services, config)

    # Show summary
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
