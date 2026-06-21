"""Terraform orchestration."""

import json
import os
import subprocess
from pathlib import Path
from typing import Dict, List, Optional

import click

from output import error, info, success, warning


class TerraformError(Exception):
    """Terraform operation error."""

    pass


def _parse_terraform_json_output(output: str) -> list:
    """Parse Terraform JSON output (newline-delimited JSON).

    Args:
        output: Raw Terraform JSON output

    Returns:
        List of parsed JSON objects

    Raises:
        TerraformError: If JSON parsing fails
    """
    objects = []
    for line in output.strip().split('\n'):
        if not line:
            continue
        try:
            obj = json.loads(line)
            objects.append(obj)
        except json.JSONDecodeError as e:
            raise TerraformError(f"Failed to parse Terraform JSON line: {line}\nError: {str(e)}")
    return objects


class TerraformExecutor:
    """Execute Terraform commands."""

    def __init__(self, working_dir: str = "."):
        """Initialize Terraform executor.

        Args:
            working_dir: Directory containing Terraform files
        """
        self.working_dir = Path(working_dir)
        if not self.working_dir.exists():
            raise TerraformError(f"Working directory not found: {working_dir}")

    def init(self, bucket: str, prefix: str) -> None:
        """Initialize Terraform.

        Args:
            bucket: GCS bucket for state
            prefix: State file prefix

        Raises:
            TerraformError: If initialization fails
        """
        info("Initializing Terraform")

        cmd = [
            "terraform",
            "-chdir=" + str(self.working_dir),
            "init",
            f"-backend-config=bucket={bucket}",
            f"-backend-config=prefix={prefix}",
            "-reconfigure",
        ]

        max_retries = 3
        for attempt in range(max_retries):
            try:
                subprocess.run(
                    cmd,
                    timeout=120,
                    check=True,
                )
                success("Terraform initialized")
                return
            except subprocess.CalledProcessError as e:
                if attempt < max_retries - 1:
                    warning(
                        f"Init failed, retrying ({attempt + 1}/{max_retries})..."
                    )
                else:
                    raise TerraformError(
                        f"Terraform init failed"
                    )

    def plan(self, vars_dict: Dict[str, str]) -> Dict:
        """Plan Terraform changes (dry-run) with JSON output.

        Args:
            vars_dict: Dictionary of Terraform variables

        Returns:
            Parsed JSON plan output as dict

        Raises:
            TerraformError: If plan fails
        """
        info("Planning infrastructure changes")

        # Build variable arguments
        var_args = []
        for key, value in vars_dict.items():
            if isinstance(value, bool):
                var_args.append(f'-var={key}={str(value).lower()}')
            else:
                var_args.append(f'-var={key}={value}')

        cmd = [
            "terraform",
            "-chdir=" + str(self.working_dir),
            "plan",
            "-json",  # Enforce JSON output
            "-lock=false",  # Disable state locking (GCS backend issue)
        ] + var_args

        # Set quota project for billing API
        env = os.environ.copy()
        if 'gcp_project_id' in vars_dict:
            env['GOOGLE_CLOUD_QUOTA_PROJECT'] = vars_dict['gcp_project_id']

        try:
            result = subprocess.run(
                cmd,
                timeout=600,  # 10 minutes
                check=False,  # JSON output includes diagnostics
                cwd=str(self.working_dir),
                env=env,
                capture_output=True,
                text=True,
            )

            # Check for errors first
            if result.returncode != 0:
                # Print full terraform output to show actual error
                if result.stdout:
                    info("Terraform output:")
                    click.echo(result.stdout)
                if result.stderr:
                    info("Terraform errors:")
                    click.echo(result.stderr)
                raise TerraformError(f"Terraform plan failed with exit code {result.returncode}")

            # Parse newline-delimited JSON output
            plan_output = _parse_terraform_json_output(result.stdout)

            success("Plan completed (no changes applied)")
            return plan_output
        except subprocess.TimeoutExpired:
            raise TerraformError("Terraform plan timed out")

    def apply(self, vars_dict: Dict[str, str]) -> Dict:
        """Apply Terraform configuration with JSON output.

        Args:
            vars_dict: Dictionary of Terraform variables

        Returns:
            Parsed JSON apply output as dict

        Raises:
            TerraformError: If apply fails
        """
        info("Applying infrastructure")

        # Build variable arguments
        var_args = []
        for key, value in vars_dict.items():
            if isinstance(value, bool):
                var_args.append(f'-var={key}={str(value).lower()}')
            else:
                var_args.append(f'-var={key}={value}')

        cmd = [
            "terraform",
            "-chdir=" + str(self.working_dir),
            "apply",
            "-auto-approve",
            "-json",  # Enforce JSON output
            "-lock=false",  # Disable state locking (GCS backend issue)
        ] + var_args

        # Set quota project for billing API
        env = os.environ.copy()
        if 'gcp_project_id' in vars_dict:
            env['GOOGLE_CLOUD_QUOTA_PROJECT'] = vars_dict['gcp_project_id']

        try:
            result = subprocess.run(
                cmd,
                timeout=600,  # 10 minutes
                check=False,  # JSON output includes diagnostics
                cwd=str(self.working_dir),
                env=env,
                capture_output=True,
                text=True,
            )

            # Check for errors first
            if result.returncode != 0:
                # Print full terraform output to show actual error
                if result.stdout:
                    info("Terraform output:")
                    click.echo(result.stdout)
                if result.stderr:
                    info("Terraform errors:")
                    click.echo(result.stderr)
                raise TerraformError(f"Terraform apply failed with exit code {result.returncode}")

            # Parse newline-delimited JSON output
            apply_output = _parse_terraform_json_output(result.stdout)

            success("Infrastructure deployed")
            return apply_output
        except subprocess.TimeoutExpired:
            raise TerraformError("Terraform apply timed out")

    def destroy(self, vars_dict: Dict[str, str], force: bool = False) -> bool:
        """Destroy Terraform infrastructure.

        Args:
            vars_dict: Dictionary of Terraform variables
            force: Skip confirmation

        Returns:
            True if destroy succeeded, False if it had errors (but may have partially succeeded)
        """
        # Build variable arguments
        var_args = []
        for key, value in vars_dict.items():
            if isinstance(value, bool):
                var_args.append(f'-var={key}={str(value).lower()}')
            else:
                var_args.append(f'-var={key}={value}')

        cmd = [
            "terraform",
            "-chdir=" + str(self.working_dir),
            "destroy",
            "-lock=false",  # Disable state locking (GCS backend issue)
        ]

        if force:
            cmd.append("-auto-approve")

        cmd.extend(var_args)

        info("Running terraform destroy...")
        try:
            result = subprocess.run(
                cmd,
                timeout=600,  # 10 minutes
                check=False,  # Don't fail on non-zero exit - allow cleanup to continue
                cwd=str(self.working_dir),
            )
            if result.returncode == 0:
                success("Infrastructure destroyed")
                return True
            else:
                warning("Terraform destroy completed with warnings/errors (continuing cleanup)")
                return False
        except subprocess.TimeoutExpired:
            raise TerraformError("Terraform destroy timed out")

    def list_resources(self) -> List[str]:
        """List Terraform state resources.

        Returns:
            List of resource addresses
        """
        cmd = [
            "terraform",
            "-chdir=" + str(self.working_dir),
            "state",
            "list",
        ]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30,
                check=True,
                cwd=str(self.working_dir),
            )
            return result.stdout.strip().split("\n") if result.stdout.strip() else []
        except subprocess.CalledProcessError:
            return []

    def get_output(self, output_name: str) -> Optional[str]:
        """Get Terraform output value.

        Args:
            output_name: Name of output

        Returns:
            Output value or None if not found
        """
        cmd = [
            "terraform",
            "-chdir=" + str(self.working_dir),
            "output",
            "-raw",
            output_name,
        ]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30,
                check=False,  # Don't fail on warnings
                cwd=str(self.working_dir),
            )
            # Check if output is an error message
            if "Warning:" in result.stdout or "Error:" in result.stdout or result.returncode != 0:
                return None
            output = result.stdout.strip()
            return output if output else None
        except Exception:
            return None

    def import_resource(
        self, resource_type: str, resource_id: str, vars_dict: Dict[str, str]
    ) -> bool:
        """Import existing resource into Terraform state.

        Args:
            resource_type: Terraform resource type (e.g., 'google_service_account.app')
            resource_id: GCP resource ID
            vars_dict: Dictionary of Terraform variables

        Returns:
            True if successful, False otherwise
        """
        # Build variable arguments
        var_args = []
        for key, value in vars_dict.items():
            if isinstance(value, bool):
                var_args.append(f'-var={key}={str(value).lower()}')
            else:
                var_args.append(f'-var={key}={value}')

        cmd = [
            "terraform",
            "-chdir=" + str(self.working_dir),
            "import",
        ] + var_args + [resource_type, resource_id]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=60,
                check=False,
                cwd=str(self.working_dir),
            )

            # Success cases
            if result.returncode == 0:
                return True
            if "already exists" in result.stderr or "already exists" in result.stdout:
                return True
            if "does not exist" in result.stderr:
                return True

            return False
        except Exception:
            return False

    def force_unlock(self, lock_id: str) -> bool:
        """Force-unlock Terraform state using native terraform force-unlock.

        Args:
            lock_id: Lock ID from state lock metadata

        Returns:
            True if successful, False otherwise
        """
        cmd = [
            "terraform",
            "-chdir=" + str(self.working_dir),
            "force-unlock",
            lock_id,
        ]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
                cwd=str(self.working_dir),
            )

            if result.returncode == 0:
                success(f"Terraform state unlocked: {lock_id}")
                return True
            else:
                warning(f"Failed to force-unlock: {result.stderr}")
                return False
        except Exception as e:
            warning(f"Force-unlock exception: {str(e)}")
            return False


class StateImporter:
    """Import multiple resources sequentially to avoid Terraform state lock contention."""

    def __init__(self, tf_executor: TerraformExecutor):
        """Initialize importer.

        Args:
            tf_executor: TerraformExecutor instance
        """
        self.tf = tf_executor

    def import_all(
        self, resources: List[tuple], vars_dict: Dict[str, str]
    ) -> Dict[str, bool]:
        """Import multiple resources sequentially with retry on lock failures.

        Sequential execution prevents state lock contention. Terraform uses
        exclusive write locks on remote state — concurrent imports cause
        "Error acquiring the state lock" failures.

        Args:
            resources: List of (resource_type, resource_id, display_name) tuples
            vars_dict: Dictionary of Terraform variables

        Returns:
            Dictionary mapping resource name to success status
        """
        results = {}
        failed = []

        info("Importing resources...")

        for resource_type, resource_id, display_name in resources:
            success_flag = self._import_with_retry(
                resource_type,
                resource_id,
                display_name,
                vars_dict,
            )
            results[display_name] = success_flag
            if success_flag:
                success(f"Imported {display_name}")
            else:
                failed.append(display_name)
                warning(f"Import failed: {display_name}")

        if failed:
            warning(f"Some imports had issues: {', '.join(failed)}, continuing...")

        return results

    def _import_with_retry(
        self,
        resource_type: str,
        resource_id: str,
        display_name: str,
        vars_dict: Dict[str, str],
        max_retries: int = 2,
    ) -> bool:
        """Import resource with retry on failure.

        Args:
            resource_type: Terraform resource type
            resource_id: GCP resource ID
            display_name: Display name for logging
            vars_dict: Dictionary of Terraform variables
            max_retries: Number of retry attempts

        Returns:
            True if resource is now in state
        """
        for attempt in range(max_retries):
            # Check if already in state
            resources = self.tf.list_resources()
            if any(resource_type in r for r in resources):
                return True

            # Try to import
            if self.tf.import_resource(resource_type, resource_id, vars_dict):
                return True

            # Retry on failure (except on last attempt)
            if attempt < max_retries - 1:
                warning(f"Import failed for {display_name}, retrying...")

        return False
