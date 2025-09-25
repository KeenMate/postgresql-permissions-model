#!/usr/bin/env python3
"""
Debee - PostgreSQL Migration Orchestrator (Python Version)
Pure orchestration script - all database logic lives in external SQL files
"""

import os
import sys
import argparse
import subprocess
import re
from pathlib import Path
from typing import List, Dict, Optional, Tuple
from enum import Enum

# Color output support
class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    NC = '\033[0m'  # No Color

    @classmethod
    def disable(cls):
        cls.RED = ''
        cls.GREEN = ''
        cls.YELLOW = ''
        cls.NC = ''

# Check if output supports colors
if not sys.stdout.isatty():
    Colors.disable()

class Operation(Enum):
    RECREATE_DATABASE = "recreateDatabase"
    RESTORE_DATABASE = "restoreDatabase"
    UPDATE_DATABASE = "updateDatabase"
    PRE_UPDATE_SCRIPTS = "preUpdateScripts"
    POST_UPDATE_SCRIPTS = "postUpdateScripts"
    PREPARE_VERSION_TABLE = "prepareVersionTable"
    FULL_SERVICE = "fullService"

class DebeeOrchestrator:
    """PostgreSQL migration orchestrator"""

    def __init__(self, environment: Optional[str] = None):
        self.environment = environment
        self.env_vars: Dict[str, str] = {}
        self.update_start_number = -1
        self.update_end_number = -1

    def print_error(self, message: str) -> None:
        """Print error message in red"""
        print(f"{Colors.RED}Error: {message}{Colors.NC}", file=sys.stderr)

    def print_warning(self, message: str) -> None:
        """Print warning message in yellow"""
        print(f"{Colors.YELLOW}Warning: {message}{Colors.NC}")

    def print_success(self, message: str) -> None:
        """Print success message in green"""
        print(f"{Colors.GREEN}{message}{Colors.NC}")

    def print_info(self, message: str) -> None:
        """Print info message"""
        print(message)

    def set_env_var(self, key: str, value: str) -> None:
        """Set environment variable"""
        os.environ[key] = value
        self.env_vars[key] = value

    def prepare_environment(self, env_file_path: str) -> bool:
        """Load environment variables from .env file"""
        if not Path(env_file_path).exists():
            self.print_error(f"File not found: {env_file_path}")
            return False

        self.print_info(f"Loading environment from {env_file_path}")

        try:
            with open(env_file_path, 'r', encoding='utf-8') as f:
                for line_num, line in enumerate(f, 1):
                    line = line.strip()

                    # Skip empty lines and comments
                    if not line or line.startswith('#'):
                        continue

                    # Check if line contains =
                    if '=' not in line:
                        self.print_warning(f"Skipping invalid line {line_num}: {line}")
                        continue

                    # Split key and value
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip()

                    # Remove quotes if present
                    if (value.startswith('"') and value.endswith('"')) or \
                       (value.startswith("'") and value.endswith("'")):
                        value = value[1:-1]

                    # Set environment variable
                    self.set_env_var(key, value)

            self.print_success(f"Environment variables set successfully from {env_file_path}")
            return True

        except Exception as e:
            self.print_error(f"Failed to read environment file: {e}")
            return False

    def set_current_database(self, database_name: str) -> None:
        """Set current database for PostgreSQL operations"""
        self.set_env_var("PGDATABASE", database_name)

    def get_files_by_numeric_prefix(self, start_number: int, end_number: int) -> List[Path]:
        """Get migration files within numeric range"""
        # Use environment variables if parameters are -1
        if start_number == -1 and self.env_vars.get("DBUPDATESTARTNUMBER"):
            try:
                start_number = int(self.env_vars["DBUPDATESTARTNUMBER"])
            except ValueError:
                pass

        if end_number == -1 and self.env_vars.get("DBUPDATEENDNUMBER"):
            try:
                end_number = int(self.env_vars["DBUPDATEENDNUMBER"])
            except ValueError:
                pass

        self.print_warning(f"Scripts from: {start_number} to: {end_number} will be run.")

        # Validate range
        if start_number > end_number and end_number != -1:
            self.print_error(f"StartNumber ({start_number}) cannot be greater than EndNumber ({end_number}).")
            return []

        # Find matching files
        matching_files = []
        pattern = re.compile(r'^(\d{3})_.*')

        for file_path in Path('.').glob('[0-9][0-9][0-9]_*'):
            if not file_path.is_file():
                continue

            match = pattern.match(file_path.name)
            if match:
                prefix = int(match.group(1))

                # Check if within range
                if (prefix >= start_number or start_number == -1) and \
                   (prefix <= end_number or end_number == -1):
                    self.print_info(f"File: {file_path.name} is within the update range.")
                    matching_files.append(file_path)

        self.print_info(f"Number of matching files: {len(matching_files)}")
        return sorted(matching_files)

    def run_psql(self, sql_file: str) -> bool:
        """Execute SQL file using psql"""
        psql_cmd = self.env_vars.get("DBPSQLFILE", "psql")

        try:
            result = subprocess.run(
                [psql_cmd, "-q", "-b", "-n", "--csv", "-f", sql_file],
                capture_output=True,
                text=True,
                env=os.environ
            )

            if result.returncode != 0:
                self.print_error(f"psql failed with exit code {result.returncode}")
                if result.stderr:
                    self.print_error(result.stderr)
                return False

            return True

        except FileNotFoundError:
            self.print_error(f"psql command not found: {psql_cmd}")
            return False
        except Exception as e:
            self.print_error(f"Failed to execute SQL file: {e}")
            return False

    def recreate_database(self) -> bool:
        """Recreate database from script"""
        connect_db = self.env_vars.get("DBCONNECTDB")
        if not connect_db:
            self.print_error("DBCONNECTDB not defined in environment")
            return False

        self.set_current_database(connect_db)

        recreate_script = self.env_vars.get("DBRECREATESCRIPT")
        if not recreate_script or not Path(recreate_script).exists():
            self.print_error(f"Recreation script not found: {recreate_script}")
            return False

        pghost = self.env_vars.get("PGHOST", "localhost")
        pgdb = self.env_vars.get("PGDATABASE", "")
        self.print_info(f"Recreating database on host: {pghost}, connected to: {pgdb}")

        return self.run_psql(recreate_script)

    def restore_database(self, backup_filepath: Optional[str] = None,
                        backup_type: Optional[str] = None) -> bool:
        """Restore database from backup"""
        self.print_info("Calculating backup type and path")

        if not backup_filepath:
            backup_filepath = self.env_vars.get("DBBACKUPFILE")

        if not backup_filepath:
            self.print_warning("No restore file defined, skipping")
            return True

        if not backup_type:
            backup_type = self.env_vars.get("DBBACKUPTYPE", "custom")

        job_count = 1
        if self.env_vars.get("DBRESTOREJOBCOUNT"):
            try:
                job_count = int(self.env_vars["DBRESTOREJOBCOUNT"])
            except ValueError:
                pass

        self.print_warning(f"Restoring database with {job_count} jobs")

        dest_db = self.env_vars.get("DBDESTDB")
        if not dest_db:
            self.print_error("DBDESTDB not defined in environment")
            return False

        pg_restore = self.env_vars.get("DBPGRESTOREFILE", "pg_restore")
        psql_cmd = self.env_vars.get("DBPSQLFILE", "psql")

        try:
            if backup_type == "file":
                self.print_info(f"Restoring from file: {backup_filepath}")
                self.set_current_database(dest_db)
                return self.run_psql(backup_filepath)

            elif backup_type in ["dir", "custom"]:
                format_flag = "-F d" if backup_type == "dir" else "-F c"
                self.print_info(f"Restoring from {backup_type}: {backup_filepath}")
                self.set_current_database(dest_db)

                create_on_restore = self.env_vars.get("DBCREATEONRESTORE", "false").lower() == "true"

                if create_on_restore:
                    connect_db = self.env_vars.get("DBCONNECTDB", "postgres")
                    cmd = [pg_restore, "-v", format_flag, "-C", "-d", connect_db, backup_filepath]
                else:
                    cmd = [pg_restore, "-v", format_flag, "-d", dest_db, backup_filepath]

                if job_count > 1:
                    cmd.extend(["-j", str(job_count)])

                result = subprocess.run(cmd, capture_output=True, text=True, env=os.environ)

                if result.returncode != 0:
                    self.print_error(f"pg_restore failed with exit code {result.returncode}")
                    if result.stderr:
                        self.print_error(result.stderr)
                    return False

                return True

            else:
                self.print_error(f"Unknown backup type: {backup_type}")
                return False

        except FileNotFoundError as e:
            self.print_error(f"Command not found: {e}")
            return False
        except Exception as e:
            self.print_error(f"Failed to restore database: {e}")
            return False

    def update_database_with_files(self, files: List[Path]) -> bool:
        """Update database with SQL files"""
        self.print_info("Updating database...")

        dest_db = self.env_vars.get("DBDESTDB")
        if not dest_db:
            self.print_error("DBDESTDB not defined in environment")
            return False

        self.set_current_database(dest_db)

        for file_path in files:
            if file_path.exists() and file_path.stat().st_size > 0:
                self.print_info(f".. with file: {file_path.name}")
                if not self.run_psql(str(file_path)):
                    return False

        return True

    def update_database(self) -> bool:
        """Apply numbered migration files"""
        files = self.get_files_by_numeric_prefix(self.update_start_number, self.update_end_number)
        self.print_info(f"Number of returned files: {len(files)}")

        if files:
            return self.update_database_with_files(files)

        return True

    def run_pre_update_scripts(self) -> bool:
        """Run pre-update scripts"""
        scripts_str = self.env_vars.get("DBPREUPDATESCRIPTS", "")

        if not scripts_str:
            self.print_info("No pre-update scripts, skipping the step")
            return True

        scripts_to_run = []
        for script in scripts_str.split(';'):
            script = script.strip()
            if not script:
                continue

            script_path = Path(script)
            if script_path.exists():
                scripts_to_run.append(script_path)
                self.print_info(f"Pre-update script file: {script} to be run.")
            else:
                self.print_warning(f"File does not exist: {script}")

        if scripts_to_run:
            return self.update_database_with_files(scripts_to_run)

        return True

    def run_post_update_scripts(self) -> bool:
        """Run post-update scripts"""
        scripts_str = self.env_vars.get("DBPOSTUPDATESCRIPTS", "")

        if not scripts_str:
            self.print_info("No post-update scripts, skipping the step")
            return True

        scripts_to_run = []
        for script in scripts_str.split(';'):
            script = script.strip()
            if not script:
                self.print_warning("Post-update script path empty, skipping")
                continue

            script_path = Path(script)
            if script_path.exists():
                scripts_to_run.append(script_path)
                self.print_info(f"Post-update script file: {script} to be run.")
            else:
                self.print_warning(f"File does not exist: {script}")

        if scripts_to_run:
            return self.update_database_with_files(scripts_to_run)

        return True

    def prepare_version_table(self) -> bool:
        """Prepare version table by extracting database objects and generating markdown"""
        self.print_info("Preparing version table - extracting database objects and generating markdown")

        # Check if extract-db-objects.py exists
        extract_script = Path("extract-db-objects.py")
        if not extract_script.exists():
            self.print_error("extract-db-objects.py not found in current directory")
            return False

        # Determine Python command
        python_cmd = None
        for cmd in ["python3", "python"]:
            try:
                result = subprocess.run([cmd, "--version"], capture_output=True, text=True)
                if result.returncode == 0:
                    python_cmd = cmd
                    break
            except FileNotFoundError:
                continue

        if not python_cmd:
            self.print_error("Python not found. Please install Python 3.6+")
            return False

        try:
            # Run extract-db-objects.py to generate JSON
            self.print_info("Extracting database objects to db-objects.json...")
            result = subprocess.run(
                [python_cmd, str(extract_script), "--format", "json", "--output", "db-objects.json"],
                capture_output=True,
                text=True,
                cwd=Path.cwd(),
                env=os.environ
            )

            if result.returncode != 0:
                self.print_error(f"Failed to run extract-db-objects.py: {result.stderr}")
                return False

            self.print_success("Successfully generated db-objects.json")

            # Check if JSON file was created
            json_file = Path("db-objects.json")
            if not json_file.exists():
                self.print_error("db-objects.json was not created")
                return False

            # Generate markdown table from JSON
            self.print_info("Generating db-objects.md from JSON...")
            result = subprocess.run(
                [python_cmd, str(extract_script), "--format", "markdown", "--output", "db-objects.md"],
                capture_output=True,
                text=True,
                cwd=Path.cwd(),
                env=os.environ
            )

            if result.returncode != 0:
                self.print_error(f"Failed to generate markdown: {result.stderr}")
                return False

            self.print_success("Successfully generated db-objects.md")

            self.print_success("Version table preparation completed successfully")
            self.print_info("Generated files: db-objects.json, db-objects.md")
            return True

        except Exception as e:
            self.print_error(f"Failed to prepare version table: {e}")
            return False

    def execute_operation(self, operation: Operation) -> bool:
        """Execute a single operation"""
        self.print_info(f"Processing: {operation.value}")

        if operation == Operation.RECREATE_DATABASE:
            self.print_info("Performing recreate operation...")
            return self.recreate_database()

        elif operation == Operation.RESTORE_DATABASE:
            self.print_info("Performing restore operation...")
            return self.restore_database()

        elif operation == Operation.UPDATE_DATABASE:
            self.print_info("Performing update operation...")
            return self.update_database()

        elif operation == Operation.PRE_UPDATE_SCRIPTS:
            self.print_info("Performing pre-update operation...")
            return self.run_pre_update_scripts()

        elif operation == Operation.POST_UPDATE_SCRIPTS:
            self.print_info("Performing post-update operation...")
            return self.run_post_update_scripts()

        elif operation == Operation.PREPARE_VERSION_TABLE:
            self.print_info("Performing prepare version table operation...")
            return self.prepare_version_table()

        elif operation == Operation.FULL_SERVICE:
            self.print_info("Performing full service operation...")
            operations = [
                self.recreate_database(),
                self.restore_database(),
                self.run_pre_update_scripts(),
                self.update_database(),
                self.run_post_update_scripts()
            ]
            return all(operations)

        else:
            self.print_error(f"Invalid operation: {operation.value}")
            return False

    def run(self, operations: List[Operation],
            start_number: int = -1,
            end_number: int = -1) -> bool:
        """Run orchestration with specified operations"""
        self.update_start_number = start_number
        self.update_end_number = end_number

        # Load environment files
        if self.environment:
            env_file = f"debee.{self.environment}.env"
            local_env_file = f".debee.{self.environment}.env"
        else:
            env_file = "debee.env"
            local_env_file = ".debee.env"

        # Check if main environment file exists
        if not Path(env_file).exists():
            self.print_error(f"Could not find {env_file}")
            return False

        # Load main environment file
        if not self.prepare_environment(env_file):
            return False

        # Load local environment file if it exists
        if Path(local_env_file).exists():
            self.prepare_environment(local_env_file)

        # Set default tool paths if not defined
        if "DBPSQLFILE" not in self.env_vars:
            self.set_env_var("DBPSQLFILE", "psql")
        if "DBPGRESTOREFILE" not in self.env_vars:
            self.set_env_var("DBPGRESTOREFILE", "pg_restore")

        # Execute operations
        for operation in operations:
            if not self.execute_operation(operation):
                self.print_error(f"Operation failed: {operation.value}")
                return False

        self.print_success("All operations completed successfully!")
        return True


def parse_operations(operations_str: str) -> List[Operation]:
    """Parse comma-separated operations string"""
    operations = []
    operation_map = {op.value: op for op in Operation}

    for op_str in operations_str.split(','):
        op_str = op_str.strip()
        if op_str in operation_map:
            operations.append(operation_map[op_str])
        else:
            raise ValueError(f"Invalid operation: {op_str}")

    return operations


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='PostgreSQL Migration Orchestrator - Python Version',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    %(prog)s -e prod -o fullService
    %(prog)s -e dev -o restoreDatabase,updateDatabase
    %(prog)s -o updateDatabase -s 10 -n 20

Environment files:
    debee.ENV.env              Environment-specific configuration
    .debee.ENV.env             Local overrides (git-ignored)
    debee.env                  Default configuration (when no environment specified)
    .debee.env                 Local default overrides
        """
    )

    parser.add_argument('-e', '--environment',
                        help='Environment name for configuration')
    parser.add_argument('-o', '--operations',
                        default='fullService',
                        help='Comma-separated operations to perform '
                             '(recreateDatabase, restoreDatabase, updateDatabase, '
                             'preUpdateScripts, postUpdateScripts, prepareVersionTable, fullService)')
    parser.add_argument('-s', '--start-number',
                        type=int,
                        default=-1,
                        help='Starting migration file number (default: -1 for all)')
    parser.add_argument('-n', '--end-number',
                        type=int,
                        default=-1,
                        help='Ending migration file number (default: -1 for all)')
    parser.add_argument('--no-color',
                        action='store_true',
                        help='Disable colored output')

    args = parser.parse_args()

    # Disable colors if requested
    if args.no_color:
        Colors.disable()

    # Parse operations
    try:
        operations = parse_operations(args.operations)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        print("Valid operations: recreateDatabase, restoreDatabase, updateDatabase, "
              "preUpdateScripts, postUpdateScripts, prepareVersionTable, fullService")
        return 1

    # Create orchestrator and run
    orchestrator = DebeeOrchestrator(environment=args.environment)

    if orchestrator.run(operations, args.start_number, args.end_number):
        return 0
    else:
        return 1


if __name__ == '__main__':
    sys.exit(main())