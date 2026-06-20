#!/usr/bin/env python3
"""Zilch GCP infrastructure deployment tool."""

import os
import subprocess
import sys
from pathlib import Path

import click

import cli
import gcp
from config import ZilchConfig
from health_check import check_cloud_run_health
from output import bold, cyan, error, info, section, success, warning
from terraform import ParallelImporter, TerraformError, TerraformExecutor


@click.group()
def main():
    """Zilch infrastructure deployment tool."""
    pass


@main.command()
@click.option("--auto", is_flag=True, help="Use config defaults, skip prompts")
def deploy(auto: bool) -> None:
    """Deploy infrastructure.

    Deploys Zilch infrastructure to GCP including Cloud Run, databases,
    and optional services like Firestore, Secret Manager, etc.
    """
    try:
        section("Zilch GCP Infrastructure Deployment")
        if auto:
            click.echo(cyan("(auto mode - using config defaults)"))

        section("Prerequisites")

        # Check tools
        gcp.check_required_tools()

        # Check auth
        current_user = gcp.validate_gcloud_auth()

        # Load or create config
        if Path(".zilch.config").exists():
            info("Loading .zilch.config")
            try:
                config = ZilchConfig.load_from_file(".zilch.config")
                success("Config loaded")
            except Exception as e:
                error(f"Failed to load config: {e}")
                sys.exit(1)
        else:
            if Path(".zilch.config.template").exists():
                info("Creating .zilch.config from template")
                import shutil

                shutil.copy(".zilch.config.template", ".zilch.config")
                success("Template copied")
                click.echo(
                    cyan("→ Edit .zilch.config and uncomment settings, then re-run")
                )
                sys.exit(0)
            else:
                error("No .zilch.config or template found")
                sys.exit(1)

        # Interactive prompts (unless auto mode)
        if not auto:
            config.gcp_project_id = cli.get_project_id(config)
            config.app_name = cli.get_app_name(config)
            config.gcp_region = cli.get_region(config)

        # Validate config
        try:
            # Validate project
            gcp.validate_project(config.gcp_project_id)
            gcp.validate_iam_permissions(config.gcp_project_id, current_user)
        except gcp.GCPError as e:
            error(str(e))
            sys.exit(1)

        # Interactive service menu (unless auto mode)
        if not auto:
            config = cli.get_services(config)

        # Firestore permissions check
        if config.enable_firestore:
            if not gcp.check_firestore_permissions(config.gcp_project_id, current_user):
                if not auto:
                    if click.confirm("Try to grant Firestore Admin role?", default=True):
                        if not gcp.setup_firestore_permissions(
                            config.gcp_project_id, current_user
                        ):
                            warning("Could not grant Firestore Admin role, continuing anyway...")
                else:
                    error("Firestore Admin role required")
                    sys.exit(1)

        # Additional service config
        if config.enable_scheduler and not auto:
            config = cli.get_scheduler_config(config)

        if config.enable_monitoring and not auto:
            config = cli.get_monitoring_config(config)

        # GitHub info for Cloud Build
        if config.enable_cloud_build and (not config.github_owner or not config.github_repo):
            if not auto:
                section("GitHub Repository")
                config.github_owner = click.prompt("Username/org")
                config.github_repo = click.prompt("Repository name")
            elif not config.github_owner or not config.github_repo:
                error("GitHub info required for Cloud Build")
                sys.exit(1)

        # Access control
        if not auto:
            section("Access & Monitoring")
            config.allow_unauthenticated_access = cli.prompt_toggle(
                "Unauthenticated access", config.allow_unauthenticated_access
            )
            config.enable_monitoring = cli.prompt_toggle(
                "Cloud Monitoring", config.enable_monitoring
            )

        # Monitoring setup (ADC quota project)
        if config.enable_monitoring:
            _setup_monitoring(config, auto)

        # Save config
        section("Saving Configuration")
        config.save_to_file(".zilch.config")
        success("Config saved")

        # Setup GCP
        _setup_gcp(config)

        # Terraform
        _run_terraform(config)

        # Health checks
        _run_health_checks(config)

        # Print summary
        _print_summary(config)

        success(bold("Deployment complete!"))

    except KeyboardInterrupt:
        warning("Deployment cancelled")
        sys.exit(1)
    except Exception as e:
        error(f"Deployment failed: {e}")
        sys.exit(1)


@main.command()
@click.option("--force", is_flag=True, help="Skip safety confirmations")
def teardown(force: bool) -> None:
    """Destroy infrastructure.

    Safely destroys all Terraform-managed resources and cleans up
    the remote state bucket.
    """
    try:
        section("Zilch Infrastructure Teardown")
        click.echo(click.style("⚠️  WARNING: This action is IRREVERSIBLE", fg="red"))
        click.echo()

        # Load config
        if not Path(".zilch.config").exists():
            error("Config file not found: .zilch.config")
            sys.exit(1)

        try:
            config = ZilchConfig.load_from_file(".zilch.config")
        except Exception as e:
            error(f"Failed to load config: {e}")
            sys.exit(1)

        success(f"Loaded config for {cyan(config.app_name)}")

        # Confirm
        if not force:
            if not click.confirm("Destroy all infrastructure?", default=False):
                warning("Teardown cancelled")
                sys.exit(0)

        # GCP setup
        gcp.check_required_tools()
        gcp.validate_gcloud_auth()
        gcp.validate_project(config.gcp_project_id)
        gcp.set_project_context(config.gcp_project_id)

        # Run Terraform destroy
        section("Terraform")
        try:
            tf = TerraformExecutor()
            tf.destroy(config.to_terraform_vars(), force=True)
            success("Resources destroyed")
        except TerraformError as e:
            error(f"Terraform destroy failed: {e}")
            sys.exit(1)

        # Clean up state bucket
        state_bucket = f"{config.gcp_project_id}-zilch-tfstate"
        section("Cleanup")
        info(f"Removing state bucket {cyan(state_bucket)}")

        try:
            subprocess.run(
                ["gcloud", "storage", "buckets", "delete", f"gs://{state_bucket}", "--quiet"],
                capture_output=True,
                timeout=60,
                check=True,
            )
            success("State bucket removed")
        except Exception as e:
            warning(f"Could not remove state bucket (may have retained data): {e}")

        success(bold("Teardown complete!"))

    except KeyboardInterrupt:
        warning("Teardown cancelled")
        sys.exit(1)
    except Exception as e:
        error(f"Teardown failed: {e}")
        sys.exit(1)


@main.command()
def status() -> None:
    """Show deployment status.

    Displays current deployment status and Terraform outputs.
    """
    try:
        # Load config
        if not Path(".zilch.config").exists():
            error("Config file not found: .zilch.config")
            sys.exit(1)

        config = ZilchConfig.load_from_file(".zilch.config")

        section("Deployment Status")
        click.echo(f"Project:  {cyan(config.gcp_project_id)}")
        click.echo(f"App:      {cyan(config.app_name)}")
        click.echo(f"Region:   {cyan(config.gcp_region)}")
        click.echo()

        # Get Terraform outputs
        try:
            tf = TerraformExecutor()

            section("Outputs")
            url = tf.get_output("cloud_run_url")
            if url:
                click.echo(f"Cloud Run URL: {cyan(url)}")

            service_account = tf.get_output("service_account_email")
            if service_account:
                click.echo(f"Service Account: {cyan(service_account)}")

            storage_bucket = tf.get_output("storage_bucket")
            if storage_bucket:
                click.echo(f"Storage Bucket: {cyan(storage_bucket)}")

        except Exception as e:
            warning(f"Could not retrieve outputs: {e}")

    except Exception as e:
        error(f"Failed to get status: {e}")
        sys.exit(1)


def _setup_monitoring(config: ZilchConfig, auto: bool) -> None:
    """Setup monitoring and billing configuration."""
    section("ADC Quota Project Setup")
    info("Billing API requires Application Default Credentials quota project")

    try:
        import subprocess

        result = subprocess.run(
            ["gcloud", "auth", "application-default", "set-quota-project", config.gcp_project_id],
            capture_output=True,
            timeout=10,
            check=False,
        )

        if result.returncode == 0:
            success("ADC quota project configured")
        else:
            if auto:
                error("Failed to set quota project")
                sys.exit(1)
            else:
                warning("Failed to set quota project (you may not have permissions)")
    except Exception as e:
        warning(f"Could not set quota project: {e}")


def _setup_gcp(config: ZilchConfig) -> None:
    """Setup GCP resources."""
    section("GCP Setup")

    gcp.set_project_context(config.gcp_project_id)
    gcp.enable_required_apis(config.gcp_project_id, config.enable_mysql)

    # Create state bucket
    state_bucket = f"{config.gcp_project_id}-zilch-tfstate"
    try:
        gcp.create_state_bucket(config.gcp_project_id, state_bucket, config.gcp_region)
    except gcp.GCPError as e:
        error(str(e))
        sys.exit(1)

    # Check for stale Terraform lock
    if gcp.check_terraform_lock_exists(state_bucket, config.app_name):
        warning("Found existing Terraform state lock")
        if click.confirm("Remove stale lock and continue?", default=True):
            if not gcp.remove_terraform_lock(state_bucket, config.app_name):
                error("Failed to remove lock")
                sys.exit(1)
            success("Lock removed")
        else:
            error("Cannot proceed with lock present")
            sys.exit(1)


def _run_terraform(config: ZilchConfig) -> None:
    """Run Terraform deployment."""
    section("Terraform")

    state_bucket = f"{config.gcp_project_id}-zilch-tfstate"
    state_prefix = f"terraform/state/{config.app_name}"

    try:
        tf = TerraformExecutor()
        tf.init(state_bucket, state_prefix)

        # State reconciliation (import existing resources)
        _reconcile_state(tf, config)

        # Apply
        tf.apply(config.to_terraform_vars())

    except TerraformError as e:
        error(str(e))
        sys.exit(1)


def _reconcile_state(tf: TerraformExecutor, config: ZilchConfig) -> None:
    """Reconcile Terraform state with existing resources."""
    section("State Reconciliation")

    resources = [
        (
            "google_service_account.app",
            f"{config.app_name}@{config.gcp_project_id}.iam.gserviceaccount.com",
            "Service account (app)",
        ),
        (
            "google_service_account.cloud_build",
            f"{config.app_name}-builder@{config.gcp_project_id}.iam.gserviceaccount.com",
            "Service account (Cloud Build)",
        ),
        (
            "google_artifact_registry_repository.app_images[0]",
            f"projects/{config.gcp_project_id}/locations/{config.gcp_region}/repositories/{config.app_name}-images",
            "Artifact Registry repository",
        ),
        (
            "google_cloud_run_v2_service.app",
            f"{config.gcp_region}/{config.app_name}",
            "Cloud Run service",
        ),
    ]

    if config.enable_bigquery:
        dataset = config.app_name.replace("-", "_") + "_analytics"
        resources.append(
            (
                "google_bigquery_dataset.app_analytics[0]",
                dataset,
                "BigQuery dataset",
            )
        )

    if config.enable_firestore:
        resources.append(
            (
                "google_firestore_database.default[0]",
                "(default)",
                "Firestore database",
            )
        )

    if config.enable_cloud_build:
        resources.append(
            (
                "google_storage_bucket.cloud_build_logs[0]",
                f"{config.gcp_project_id}_cloudbuild",
                "Cloud Build logs bucket",
            )
        )

    importer = ParallelImporter(tf)
    importer.import_all(resources, config.to_terraform_vars())


def _run_health_checks(config: ZilchConfig) -> None:
    """Run post-deployment health checks."""
    section("Post-Deployment Checks")

    try:
        tf = TerraformExecutor()
        url = tf.get_output("cloud_run_url")

        if url:
            check_cloud_run_health(url)
        else:
            warning("Could not retrieve Cloud Run URL")
    except Exception as e:
        warning(f"Health check failed: {e}")


def _print_summary(config: ZilchConfig) -> None:
    """Print deployment summary."""
    try:
        tf = TerraformExecutor()
        outputs = {}

        url = tf.get_output("cloud_run_url")
        if url:
            outputs["cloud_run_url"] = url

        service_account = tf.get_output("service_account_email")
        if service_account:
            outputs["service_account_email"] = service_account

        storage_bucket = tf.get_output("storage_bucket")
        if storage_bucket:
            outputs["storage_bucket"] = storage_bucket

        kms_key = tf.get_output("kms_key_id")
        if kms_key:
            outputs["kms_key_id"] = kms_key

        from output import print_deployment_summary

        print_deployment_summary(config.to_dict(), outputs)
    except Exception as e:
        warning(f"Could not print summary: {e}")


if __name__ == "__main__":
    main()
