"""Output formatting utilities."""

import click


def success(msg: str) -> None:
    """Print a success message."""
    click.echo(f"{click.style('✓', fg='green')} {msg}")


def error(msg: str) -> None:
    """Print an error message."""
    click.echo(f"{click.style('✗', fg='red')} {msg}", err=True)


def warning(msg: str) -> None:
    """Print a warning message."""
    click.echo(f"{click.style('⚠', fg='yellow')} {msg}")


def info(msg: str) -> None:
    """Print an info message."""
    click.echo(f"{click.style('→', fg='blue')} {msg}")


def bold(msg: str) -> str:
    """Return bold text."""
    return click.style(msg, bold=True)


def cyan(msg: str) -> str:
    """Return cyan text."""
    return click.style(msg, fg='cyan')


def yellow(msg: str) -> str:
    """Return yellow text."""
    return click.style(msg, fg='yellow')


def section(title: str) -> None:
    """Print a section header with divider."""
    click.echo()
    click.echo(bold(f"━━━ {title} ━━━"))


def show_progress(msg: str) -> None:
    """Print a progress indicator (doesn't add newline)."""
    click.echo(f"{info(msg)}", nl=False)


def progress_done() -> None:
    """Complete a progress indicator line."""
    click.echo(f" {click.style('✓', fg='green')}")


def print_deployment_summary(config: dict, outputs: dict, billing_info: dict = None) -> None:
    """Print deployment completion summary."""
    click.echo()
    click.echo(bold(click.style("Deployment Complete", fg='green')))
    click.echo()

    if 'cloud_run_url' in outputs:
        click.echo(f"  Endpoint:  {cyan(outputs['cloud_run_url'])}")
    if 'service_account_email' in outputs:
        click.echo(f"  Identity:  {cyan(outputs['service_account_email'])}")

    click.echo(f"  Region:    {cyan(config.get('gcp_region', 'us-central1'))}")

    # Show billing info
    budget = config.get('billing_budget_limit_usd')
    if budget or billing_info:
        budget_float = float(budget) if budget else None
        account_info = ""
        if billing_info and billing_info.get('account_name'):
            account_info = f" ({billing_info['account_name']})"

        if billing_info and billing_info.get('amount') is not None:
            # Show actual spend vs budget
            amount = billing_info['amount']
            if budget_float:
                percentage = (amount / budget_float * 100) if budget_float > 0 else 0
                click.echo(f"  Spend:     {yellow(f'${amount:.2f} USD')} / {cyan(f'${budget_float:.2f} USD')} ({percentage:.1f}%){account_info}")
            else:
                click.echo(f"  Spend:     {yellow(f'${amount:.2f} USD')} (current month){account_info}")
        elif budget_float:
            # Show budget only
            click.echo(f"  Budget:    {cyan(f'${budget_float:.2f} USD/month')}{account_info}")
    click.echo()

    click.echo(bold("Configured Services:"))
    services = []
    if config.get('enable_firestore'):
        services.append(("ZILCH_FIRESTORE_DATABASE", "(default)"))
    if config.get('enable_secret_manager'):
        services.append(("ZILCH_SECRET_PREFIX", f"{config.get('app_name')}-"))
    if config.get('enable_cloud_storage') and 'storage_bucket' in outputs:
        services.append(("ZILCH_STORAGE_BUCKET", outputs['storage_bucket']))
    if config.get('enable_vertex_ai'):
        services.append(("ZILCH_VERTEX_AI_ENABLED", "true"))
    if config.get('enable_firebase_auth'):
        services.append(("ZILCH_FIREBASE_ENABLED", "true"))
    if config.get('enable_pubsub'):
        services.append(("ZILCH_PUBSUB_TOPIC", f"{config.get('app_name')}-events"))
        services.append(("ZILCH_PUBSUB_SUBSCRIPTION", f"{config.get('app_name')}-events-subscription"))
    if config.get('enable_cloud_tasks'):
        region = config.get('gcp_region', 'us-central1')
        project = config.get('gcp_project_id')
        app = config.get('app_name')
        services.append(("ZILCH_CLOUD_TASKS_QUEUE", f"projects/{project}/locations/{region}/queues/{app}-jobs"))
    if config.get('enable_bigquery'):
        dataset = config.get('app_name', '').replace('-', '_') + '_analytics'
        services.append(("ZILCH_BIGQUERY_DATASET", dataset))
    if config.get('enable_cloud_kms') and 'kms_key_id' in outputs:
        services.append(("ZILCH_KMS_KEY_ID", outputs['kms_key_id']))
    if config.get('enable_vision_ai'):
        services.append(("ZILCH_VISION_AI_ENABLED", "true"))
    if config.get('enable_speech_to_text'):
        services.append(("ZILCH_SPEECH_TO_TEXT_ENABLED", "true"))
    if config.get('enable_translation'):
        services.append(("ZILCH_TRANSLATION_ENABLED", "true"))
    if config.get('enable_scheduler'):
        schedule = config.get('scheduler_schedule', '0 0 * * *')
        tz = config.get('scheduler_timezone', 'UTC')
        services.append(("ZILCH_SCHEDULER_ENABLED", f"{schedule} ({tz})"))
    if config.get('enable_monitoring'):
        budget = config.get('billing_budget_limit_usd', '10')
        services.append(("ZILCH_MONITORING_ENABLED", f"{budget} USD/month alert"))
    if config.get('enable_mysql'):
        services.append(("ZILCH_MYSQL_DATABASE", config.get('mysql_database_name', 'zilch_app')))

    for env_var, value in services:
        click.echo(f"  ↳ {env_var} : {value}")

    click.echo()


def get_outcome_indicator(outcome: str) -> str:
    """Get emoji/text indicator for cleanup outcome.

    Args:
        outcome: One of "deleted", "already_gone", "permission_denied", "timeout", "error"

    Returns:
        Indicator string with emoji
    """
    indicators = {
        "deleted": "✓",
        "already_gone": "ℹ️",
        "permission_denied": "🔐",
        "timeout": "⏱️",
        "error": "🚫",
    }
    return indicators.get(outcome, "?")
