"""Interactive CLI prompts."""

from typing import Optional

import click

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


def get_services(config: ZilchConfig) -> ZilchConfig:
    """Interactive service menu.

    Args:
        config: Current config

    Returns:
        Updated config with service choices
    """
    section("Services Configuration")
    click.echo("Answer yes/no for each service (descriptions below)")
    click.echo()

    # Service descriptions
    descriptions = {
        "firestore": ("Firestore", "NoSQL: document storage, real-time sync"),
        "cloud_storage": (
            "Cloud Storage",
            "Files: user uploads, media, large files",
        ),
        "secret_manager": ("Secret Manager", "Secrets: API keys, passwords, config"),
        "firebase_auth": ("Firebase Auth", "User login, social auth"),
        "vertex_ai": ("Vertex AI", "ML: predictions, model training"),
        "pubsub": ("Pub/Sub", "Event streaming: async messaging"),
        "cloud_tasks": ("Cloud Tasks", "Task queue: distributed work"),
        "bigquery": ("BigQuery", "Data warehouse: SQL on big data"),
        "cloud_kms": ("Cloud KMS", "Key management: encryption"),
        "vision_ai": ("Vision AI", "Image: OCR, object detection"),
        "speech_to_text": ("Speech-to-Text", "Audio: recognition, transcription"),
        "translation": ("Translation", "Languages: multi-language text"),
        "scheduler": ("Cloud Scheduler", "Cron jobs: periodic tasks"),
        "monitoring": ("Cloud Monitoring", "Alerts, budgets, logs"),
        "mysql": ("MySQL Database", "Relational: SQL, complex queries"),
    }

    click.echo(click.style("Data & Storage", bold=True))
    config.enable_firestore = prompt_toggle("  Firestore", config.enable_firestore)
    config.enable_cloud_storage = prompt_toggle(
        "  Cloud Storage", config.enable_cloud_storage
    )
    config.enable_secret_manager = prompt_toggle(
        "  Secret Manager", config.enable_secret_manager
    )

    click.echo()
    click.echo(click.style("Authentication & AI", bold=True))
    config.enable_firebase_auth = prompt_toggle(
        "  Firebase Auth", config.enable_firebase_auth
    )
    config.enable_vertex_ai = prompt_toggle("  Vertex AI", config.enable_vertex_ai)

    click.echo()
    click.echo(click.style("Build & Messaging", bold=True))
    # Cloud Build is always available (skip toggling)
    config.enable_pubsub = prompt_toggle("  Pub/Sub", config.enable_pubsub)
    config.enable_cloud_tasks = prompt_toggle(
        "  Cloud Tasks", config.enable_cloud_tasks
    )

    click.echo()
    click.echo(click.style("Data & Analytics", bold=True))
    config.enable_bigquery = prompt_toggle("  BigQuery", config.enable_bigquery)

    click.echo()
    click.echo(click.style("Security & Encryption", bold=True))
    config.enable_cloud_kms = prompt_toggle("  Cloud KMS", config.enable_cloud_kms)

    click.echo()
    click.echo(click.style("AI Services", bold=True))
    config.enable_vision_ai = prompt_toggle("  Vision AI", config.enable_vision_ai)
    config.enable_speech_to_text = prompt_toggle(
        "  Speech-to-Text", config.enable_speech_to_text
    )
    config.enable_translation = prompt_toggle(
        "  Translation", config.enable_translation
    )

    click.echo()
    click.echo(click.style("Operations", bold=True))
    config.enable_scheduler = prompt_toggle(
        "  Cloud Scheduler", config.enable_scheduler
    )
    config.enable_monitoring = prompt_toggle(
        "  Cloud Monitoring", config.enable_monitoring
    )
    config.enable_mysql = prompt_toggle("  MySQL Database", config.enable_mysql)

    # Show summary
    click.echo()
    section("Selected Services")
    enabled = []
    for key, (name, _) in descriptions.items():
        key_with_underscores = key.replace("-", "_")
        if getattr(config, f"enable_{key_with_underscores}", False):
            enabled.append(name)

    for service in enabled:
        click.echo(f"  ✓ {service}")

    click.echo()
    return config


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
