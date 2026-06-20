"""Terraform orchestration."""

import os
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Dict, List, Optional

from output import error, info, success, warning


class TerraformError(Exception):
    """Terraform operation error."""

    pass


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
                    capture_output=True,
                    text=True,
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
                        f"Terraform init failed: {e.stderr}"
                    )

    def apply(self, vars_dict: Dict[str, str]) -> None:
        """Apply Terraform configuration.

        Args:
            vars_dict: Dictionary of Terraform variables

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
        ] + var_args

        # Set quota project for billing API
        env = os.environ.copy()
        if 'gcp_project_id' in vars_dict:
            env['GOOGLE_CLOUD_QUOTA_PROJECT'] = vars_dict['gcp_project_id']

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=600,  # 10 minutes
                check=True,
                cwd=str(self.working_dir),
                env=env,
            )
            success("Infrastructure deployed")
        except subprocess.CalledProcessError as e:
            raise TerraformError(f"Terraform apply failed: {e.stderr}")

    def destroy(self, vars_dict: Dict[str, str], force: bool = False) -> None:
        """Destroy Terraform infrastructure.

        Args:
            vars_dict: Dictionary of Terraform variables
            force: Skip confirmation

        Raises:
            TerraformError: If destroy fails
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
        ]

        if force:
            cmd.append("-auto-approve")

        cmd.extend(var_args)

        try:
            subprocess.run(
                cmd,
                timeout=600,  # 10 minutes
                check=True,
                cwd=str(self.working_dir),
            )
            success("Infrastructure destroyed")
        except subprocess.CalledProcessError as e:
            raise TerraformError(f"Terraform destroy failed: {e.stderr}")

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
        # Refresh state first to ensure outputs are available
        refresh_cmd = [
            "terraform",
            "-chdir=" + str(self.working_dir),
            "refresh",
        ]
        try:
            subprocess.run(
                refresh_cmd,
                capture_output=True,
                text=True,
                timeout=60,
                check=False,  # Don't fail if refresh has warnings
            )
        except Exception:
            pass  # Continue even if refresh fails

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
                check=True,
                cwd=str(self.working_dir),
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError:
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


class ParallelImporter:
    """Import multiple resources in parallel."""

    def __init__(self, tf_executor: TerraformExecutor):
        """Initialize importer.

        Args:
            tf_executor: TerraformExecutor instance
        """
        self.tf = tf_executor

    def import_all(
        self, resources: List[tuple], vars_dict: Dict[str, str]
    ) -> Dict[str, bool]:
        """Import multiple resources in parallel.

        Args:
            resources: List of (resource_type, resource_id, display_name) tuples
            vars_dict: Dictionary of Terraform variables

        Returns:
            Dictionary mapping resource name to success status
        """
        results = {}
        failed = []

        info("Checking resources in parallel...")

        with ThreadPoolExecutor(max_workers=5) as executor:
            futures = {
                executor.submit(
                    self._import_with_check,
                    resource_type,
                    resource_id,
                    display_name,
                    vars_dict,
                ): display_name
                for resource_type, resource_id, display_name in resources
            }

            for future in as_completed(futures):
                display_name = futures[future]
                try:
                    success_flag = future.result()
                    results[display_name] = success_flag
                    if success_flag:
                        success(f"Imported {display_name}")
                    else:
                        failed.append(display_name)
                        warning(f"Import failed: {display_name}")
                except Exception as e:
                    failed.append(display_name)
                    warning(f"Import error: {display_name}: {e}")

        if failed:
            warning(f"Some imports had issues: {', '.join(failed)}, continuing...")

        return results

    def _import_with_check(
        self,
        resource_type: str,
        resource_id: str,
        display_name: str,
        vars_dict: Dict[str, str],
    ) -> bool:
        """Check if resource exists in state, then import if needed.

        Args:
            resource_type: Terraform resource type
            resource_id: GCP resource ID
            display_name: Display name for logging
            vars_dict: Dictionary of Terraform variables

        Returns:
            True if resource is now in state
        """
        # Check if already in state
        resources = self.tf.list_resources()
        if any(resource_type in r for r in resources):
            return True

        # Try to import
        return self.tf.import_resource(resource_type, resource_id, vars_dict)
