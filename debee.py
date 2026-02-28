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
import json
import tempfile
from pathlib import Path
from typing import List, Dict, Optional, Tuple
from dataclasses import dataclass, field
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
    EXEC_SQL = "execSql"
    RUN_TESTS = "runTests"
    FULL_SERVICE = "fullService"

@dataclass
class TestManifest:
    """Manifest for a test suite directory"""
    name: str = ""
    description: str = ""
    always_cleanup: bool = True
    isolation: str = "none"
    setup: List[str] = field(default_factory=list)

@dataclass
class TestResult:
    """Result of running a single test SQL file or suite"""
    name: str = ""
    passed: bool = True
    pass_count: int = 0
    fail_count: int = 0
    error: bool = False
    is_suite: bool = False


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
        """Prepare version table by extracting database objects and generating specified formats"""
        self.print_info("Preparing version table - extracting database objects")

        # Get configuration values
        formats_str = self.env_vars.get("DBVERSIONTABLEFORMATS", "json;md")
        output_folder = self.env_vars.get("DBVERSIONTABLEOUTPUTFOLDER", ".")
        base_filename = self.env_vars.get("DBVERSIONTABLEFILENAME", "db-objects")

        # Remove comments from formats string (anything after #)
        if '#' in formats_str:
            formats_str = formats_str.split('#')[0].strip()

        # Parse formats
        formats = [fmt.strip().lower() for fmt in formats_str.split(';') if fmt.strip()]

        if not formats:
            self.print_warning("No version table formats specified, using default: json, md")
            formats = ["json", "md"]

        # Validate formats
        valid_formats = {"json", "md", "markdown", "csv", "html"}
        invalid_formats = [fmt for fmt in formats if fmt not in valid_formats]
        if invalid_formats:
            self.print_error(f"Invalid formats: {', '.join(invalid_formats)}. Valid formats: json, md, csv, html")
            return False

        # Normalize markdown format
        formats = ["markdown" if fmt == "md" else fmt for fmt in formats]

        self.print_info(f"Version table configuration:")
        self.print_info(f"  Formats: {', '.join(formats)}")
        self.print_info(f"  Output folder: {output_folder}")
        self.print_info(f"  Base filename: {base_filename}")

        # Check if extract-db-objects.py exists
        extract_script = Path("extract-db-objects.py")
        if not extract_script.exists():
            self.print_error("extract-db-objects.py not found in current directory")
            return False

        # Create output folder if it doesn't exist
        output_path = Path(output_folder)
        if not output_path.exists():
            try:
                output_path.mkdir(parents=True, exist_ok=True)
                self.print_info(f"Created output folder: {output_folder}")
            except Exception as e:
                self.print_error(f"Failed to create output folder: {e}")
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

        generated_files = []

        try:
            # Generate each requested format
            for fmt in formats:
                # Determine extension
                if fmt == "markdown":
                    extension = "md"
                else:
                    extension = fmt

                output_file = output_path / f"{base_filename}.{extension}"

                self.print_info(f"Generating {fmt.upper()} format: {output_file}")

                result = subprocess.run(
                    [python_cmd, str(extract_script), "--format", fmt, "--output", str(output_file)],
                    capture_output=True,
                    text=True,
                    cwd=Path.cwd(),
                    env=os.environ
                )

                if result.returncode != 0:
                    self.print_error(f"Failed to generate {fmt}: {result.stderr}")
                    return False

                if output_file.exists():
                    self.print_success(f"Successfully generated {output_file}")
                    generated_files.append(str(output_file))
                else:
                    self.print_error(f"{output_file} was not created")
                    return False

            if generated_files:
                self.print_success("Version table preparation completed successfully")
                self.print_info(f"Generated files: {', '.join(generated_files)}")
            else:
                self.print_warning("No files were generated")

            return True

        except Exception as e:
            self.print_error(f"Failed to prepare version table: {e}")
            return False

    def exec_sql(self, sql_file: Optional[str] = None, sql_command: Optional[str] = None) -> bool:
        """Execute ad-hoc SQL against the configured database"""
        dest_db = self.env_vars.get("DBDESTDB")
        if not dest_db:
            self.print_error("DBDESTDB not defined in environment")
            return False

        self.set_current_database(dest_db)
        psql_cmd = self.env_vars.get("DBPSQLFILE", "psql")

        try:
            if sql_file:
                self.print_info(f"Executing SQL file: {sql_file}")
                result = subprocess.run(
                    [psql_cmd, "-f", sql_file],
                    env=os.environ
                )
            elif sql_command:
                self.print_info("Executing SQL command")
                result = subprocess.run(
                    [psql_cmd, "-c", sql_command],
                    env=os.environ
                )
            else:
                self.print_info(f"Opening interactive psql session against {dest_db} ...")
                result = subprocess.run(
                    [psql_cmd],
                    env=os.environ
                )

            return result.returncode == 0

        except FileNotFoundError:
            self.print_error(f"psql command not found: {psql_cmd}")
            return False
        except Exception as e:
            self.print_error(f"Failed to execute SQL: {e}")
            return False

    def _read_test_manifest(self, suite_dir: Path) -> TestManifest:
        """Read test.json manifest from suite directory, returning defaults if absent"""
        manifest = TestManifest()
        # Default name: humanize folder name (strip test_ prefix, replace underscores)
        folder_name = suite_dir.name
        if folder_name.startswith("test_"):
            folder_name = folder_name[5:]
        manifest.name = folder_name.replace("_", " ").title()

        manifest_file = suite_dir / "test.json"
        if manifest_file.is_file():
            try:
                with open(manifest_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                if "name" in data:
                    manifest.name = data["name"]
                if "description" in data:
                    manifest.description = data["description"]
                if "always_cleanup" in data:
                    manifest.always_cleanup = bool(data["always_cleanup"])
                if "isolation" in data:
                    valid_isolations = ("none", "transaction", "database")
                    if data["isolation"] in valid_isolations:
                        manifest.isolation = data["isolation"]
                    else:
                        self.print_warning(f"Unknown isolation mode '{data['isolation']}', using 'none'")
                if "setup" in data:
                    if isinstance(data["setup"], list):
                        manifest.setup = data["setup"]
                    else:
                        self.print_warning("'setup' in test.json must be a list, ignoring")
            except (json.JSONDecodeError, OSError) as e:
                self.print_warning(f"Failed to read {manifest_file}: {e}")

        return manifest

    def _invoke_test_sql_file(self, file_path: Path, verbose: bool = False) -> TestResult:
        """Run a single SQL test file via psql, return structured result"""
        psql_cmd = self.env_vars.get("DBPSQLFILE", "psql")
        result = TestResult(name=file_path.name)

        try:
            proc = subprocess.run(
                [psql_cmd, "-f", str(file_path)],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                env=os.environ
            )
            output = proc.stdout or ""
        except FileNotFoundError:
            self.print_error(f"psql command not found: {psql_cmd}")
            result.passed = False
            result.error = True
            return result

        # psql nonzero exit code = automatic FAIL
        if proc.returncode != 0:
            result.error = True
            result.passed = False

        # Count PASS/FAIL occurrences
        result.pass_count = output.count("PASS")
        result.fail_count = output.count("FAIL")

        if result.fail_count > 0 or result.error:
            result.passed = False

        # Colorize and print output
        if verbose:
            for line in output.splitlines():
                if "PASS" in line:
                    print(f"  {Colors.GREEN}{line}{Colors.NC}")
                elif "FAIL" in line:
                    print(f"  {Colors.RED}{line}{Colors.NC}")
                else:
                    print(f"  {line}")
        elif not result.passed:
            # Silent mode: only print FAIL lines and error context
            for line in output.splitlines():
                if "FAIL" in line:
                    print(f"  {Colors.RED}{line}{Colors.NC}")
                elif "ERROR" in line or "error" in line:
                    print(f"  {Colors.RED}{line}{Colors.NC}")

        return result

    def _invoke_suite_transaction(self, suite_dir: Path, manifest: TestManifest,
                                     main_files: List[Path], cleanup_files: List[Path],
                                     verbose: bool = False) -> TestResult:
        """Run a suite in transaction isolation mode: all setup + main files in BEGIN/ROLLBACK"""
        suite_result = TestResult(name=manifest.name, is_suite=True)
        tests_dir = Path("tests")
        psql_cmd = self.env_vars.get("DBPSQLFILE", "psql")

        # Build the wrapper SQL file
        lines = ["\\set ON_ERROR_STOP on", "BEGIN;"]

        # Add shared setup files
        for setup_path in manifest.setup:
            resolved = tests_dir / setup_path
            if not resolved.is_file():
                self.print_warning(f"Shared setup file not found: {setup_path}")
                continue
            posix_path = resolved.as_posix()
            lines.append(f"\\echo '>>>DEBEE_FILE: {setup_path}<<<'")
            lines.append(f"\\i '{posix_path}'")

        # Add main files
        for f in main_files:
            posix_path = f.as_posix()
            lines.append(f"\\echo '>>>DEBEE_FILE: {f.name}<<<'")
            lines.append(f"\\i '{posix_path}'")

        lines.append("ROLLBACK;")

        # Write temp file
        tmp_file = None
        try:
            tmp_fd, tmp_path = tempfile.mkstemp(suffix=".sql", dir=str(suite_dir))
            tmp_file = tmp_path
            with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
                f.write("\n".join(lines) + "\n")

            # Run via psql
            try:
                proc = subprocess.run(
                    [psql_cmd, "-f", tmp_path],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    env=os.environ
                )
                output = proc.stdout or ""
            except FileNotFoundError:
                self.print_error(f"psql command not found: {psql_cmd}")
                suite_result.passed = False
                suite_result.error = True
                return suite_result

            if proc.returncode != 0:
                suite_result.error = True

            # Parse output by >>>DEBEE_FILE: ...<<< markers
            current_file = "(preamble)"
            file_outputs: Dict[str, List[str]] = {}

            for line in output.splitlines():
                marker_match = re.match(r'^>>>DEBEE_FILE: (.+)<<<$', line)
                if marker_match:
                    current_file = marker_match.group(1)
                    if current_file not in file_outputs:
                        file_outputs[current_file] = []
                else:
                    if current_file not in file_outputs:
                        file_outputs[current_file] = []
                    file_outputs[current_file].append(line)

            # Print and count per section
            for section_name, section_lines in file_outputs.items():
                section_text = "\n".join(section_lines)
                section_pass = section_text.count("PASS")
                section_fail = section_text.count("FAIL")
                suite_result.pass_count += section_pass
                suite_result.fail_count += section_fail

                if verbose:
                    if section_name != "(preamble)":
                        print()
                        self.print_info(f"  -- {section_name} --")
                    for line in section_lines:
                        if "PASS" in line:
                            print(f"  {Colors.GREEN}{line}{Colors.NC}")
                        elif "FAIL" in line:
                            print(f"  {Colors.RED}{line}{Colors.NC}")
                        else:
                            print(f"  {line}")
                elif section_fail > 0:
                    if section_name != "(preamble)":
                        print()
                        self.print_info(f"  -- {section_name} --")
                    for line in section_lines:
                        if "FAIL" in line:
                            print(f"  {Colors.RED}{line}{Colors.NC}")
                        elif "ERROR" in line or "error" in line:
                            print(f"  {Colors.RED}{line}{Colors.NC}")

        finally:
            if tmp_file and os.path.exists(tmp_file):
                os.remove(tmp_file)

        # Run cleanup files individually after the rollback
        if cleanup_files and (manifest.always_cleanup or not suite_result.error):
            for f in cleanup_files:
                if verbose:
                    print()
                    self.print_info(f"  -- {f.name} (cleanup) --")
                cleanup_result = self._invoke_test_sql_file(f, verbose=verbose)
                if not cleanup_result.passed and not verbose:
                    print()
                    self.print_info(f"  -- {f.name} (cleanup) --")
                if not cleanup_result.passed:
                    self.print_warning(f"Cleanup file {f.name} had issues (non-fatal)")

        suite_result.passed = suite_result.fail_count == 0 and not suite_result.error
        return suite_result

    def _invoke_flat_test(self, test_file: Path) -> TestResult:
        """Run a flat test_*.sql file"""
        verbose = getattr(self, 'test_verbose', False)
        if verbose:
            print()
            self.print_info(f"--- {test_file.name} ---")
        result = self._invoke_test_sql_file(test_file, verbose=verbose)
        if not verbose and not result.passed:
            print()
            print(f"--- {test_file.name} --- {Colors.RED}FAILED{Colors.NC}")
        result.is_suite = False
        return result

    def _invoke_suite_test(self, suite_dir: Path) -> TestResult:
        """Run a folder-based test suite"""
        verbose = getattr(self, 'test_verbose', False)
        manifest = self._read_test_manifest(suite_dir)
        suite_result = TestResult(name=manifest.name, is_suite=True)

        suite_header_printed = False
        if verbose:
            print()
            self.print_info(f"=== Suite: {manifest.name} ===")
            if manifest.description:
                self.print_info(manifest.description)
            suite_header_printed = True

        # Discover SQL files matching NNN_*.sql
        sql_pattern = re.compile(r'^(\d{3})_.*\.sql$')
        all_files = sorted(suite_dir.iterdir())

        main_files = []
        cleanup_files = []

        for f in all_files:
            if not f.is_file():
                continue
            match = sql_pattern.match(f.name)
            if match:
                prefix = int(match.group(1))
                if 900 <= prefix <= 999:
                    cleanup_files.append(f)
                else:
                    main_files.append(f)
            elif f.name != "test.json":
                self.print_warning(f"Skipping non-matching file in suite: {f.name}")

        # Branch on isolation mode
        if manifest.isolation == "transaction":
            suite_result = self._invoke_suite_transaction(suite_dir, manifest, main_files, cleanup_files, verbose=verbose)
            suite_result.name = manifest.name
            suite_result.is_suite = True
        elif manifest.isolation == "database":
            # Recreate + restore database before suite
            self.print_info("  [database isolation] Recreating database...")
            self.recreate_database()
            if self.env_vars.get("DBBACKUPFILE"):
                self.print_info("  [database isolation] Restoring database...")
                self.restore_database()
            dest_db = self.env_vars.get("DBDESTDB")
            if dest_db:
                self.set_current_database(dest_db)

            # Run shared setup files individually
            tests_dir = Path("tests")
            for setup_path in manifest.setup:
                resolved = tests_dir / setup_path
                if resolved.is_file():
                    if verbose:
                        print()
                        self.print_info(f"  -- {setup_path} (shared setup) --")
                    self._invoke_test_sql_file(resolved, verbose=verbose)
                else:
                    self.print_warning(f"Shared setup file not found: {setup_path}")

            # Run main files individually (same as "none")
            main_failed = False
            for f in main_files:
                if verbose:
                    print()
                    self.print_info(f"  -- {f.name} --")
                file_result = self._invoke_test_sql_file(f, verbose=verbose)
                suite_result.pass_count += file_result.pass_count
                suite_result.fail_count += file_result.fail_count
                if not file_result.passed:
                    if not suite_header_printed:
                        print()
                        self.print_info(f"=== Suite: {manifest.name} ===")
                        suite_header_printed = True
                    if not verbose:
                        print()
                        self.print_info(f"  -- {f.name} --")
                    main_failed = True
                    break

            if cleanup_files and (manifest.always_cleanup or not main_failed):
                for f in cleanup_files:
                    if verbose:
                        print()
                        self.print_info(f"  -- {f.name} (cleanup) --")
                    cleanup_result = self._invoke_test_sql_file(f, verbose=verbose)
                    if not cleanup_result.passed and not verbose:
                        print()
                        self.print_info(f"  -- {f.name} (cleanup) --")
                    if not cleanup_result.passed:
                        self.print_warning(f"Cleanup file {f.name} had issues (non-fatal)")

            suite_result.passed = not main_failed and suite_result.fail_count == 0
        else:
            # "none" — current behavior with shared setup
            tests_dir = Path("tests")
            for setup_path in manifest.setup:
                resolved = tests_dir / setup_path
                if resolved.is_file():
                    if verbose:
                        print()
                        self.print_info(f"  -- {setup_path} (shared setup) --")
                    self._invoke_test_sql_file(resolved, verbose=verbose)
                else:
                    self.print_warning(f"Shared setup file not found: {setup_path}")

            # Run main phase (stop on first failure)
            main_failed = False
            for f in main_files:
                if verbose:
                    print()
                    self.print_info(f"  -- {f.name} --")
                file_result = self._invoke_test_sql_file(f, verbose=verbose)
                suite_result.pass_count += file_result.pass_count
                suite_result.fail_count += file_result.fail_count

                if not file_result.passed:
                    if not suite_header_printed:
                        print()
                        self.print_info(f"=== Suite: {manifest.name} ===")
                        suite_header_printed = True
                    if not verbose:
                        print()
                        self.print_info(f"  -- {f.name} --")
                    main_failed = True
                    break

            # Run cleanup phase (always if always_cleanup, log warnings only)
            if cleanup_files and (manifest.always_cleanup or not main_failed):
                for f in cleanup_files:
                    if verbose:
                        print()
                        self.print_info(f"  -- {f.name} (cleanup) --")
                    cleanup_result = self._invoke_test_sql_file(f, verbose=verbose)
                    if not cleanup_result.passed and not verbose:
                        print()
                        self.print_info(f"  -- {f.name} (cleanup) --")
                    if not cleanup_result.passed:
                        self.print_warning(f"Cleanup file {f.name} had issues (non-fatal)")

            suite_result.passed = not main_failed and suite_result.fail_count == 0

        status = "PASSED" if suite_result.passed else "FAILED"
        if suite_result.passed:
            if verbose:
                print()
                self.print_success(f"Suite {manifest.name}: {status}")
        else:
            if not suite_header_printed:
                print()
                self.print_info(f"=== Suite: {manifest.name} ===")
            print()
            self.print_error(f"Suite {manifest.name}: {status}")

        return suite_result

    def run_tests(self, test_filter: str = "all") -> bool:
        """Run SQL test files and test suites from the tests/ directory"""
        tests_dir = Path("tests")

        if not tests_dir.is_dir():
            self.print_warning(f"Tests directory not found: {tests_dir}")
            return False

        dest_db = self.env_vars.get("DBDESTDB")
        if not dest_db:
            self.print_error("DBDESTDB not defined in environment")
            return False

        self.set_current_database(dest_db)

        # Discover test items: flat test_*.sql files + test_*/ directories
        test_items = []
        for item in sorted(tests_dir.iterdir()):
            if item.is_file() and item.name.startswith("test_") and item.name.endswith(".sql"):
                test_items.append(("file", item))
            elif item.is_dir() and item.name.startswith("test_"):
                test_items.append(("suite", item))

        # Apply global ordering from tests/tests.json
        tests_json = tests_dir / "tests.json"
        if tests_json.is_file():
            try:
                with open(tests_json, "r", encoding="utf-8") as f:
                    tests_config = json.load(f)
                order_list = tests_config.get("order", [])
                if order_list:
                    ordered = []
                    remaining = list(test_items)
                    for name in order_list:
                        for item in remaining:
                            if item[1].name == name:
                                ordered.append(item)
                                remaining.remove(item)
                                break
                    test_items = ordered + remaining
            except (json.JSONDecodeError, OSError) as e:
                self.print_warning(f"Failed to read {tests_json}: {e}")

        # Apply filter
        if test_filter != "all":
            test_items = [(t, p) for t, p in test_items if test_filter in p.name]

        if not test_items:
            self.print_warning(f"No test items found matching filter: {test_filter}")
            return False

        file_count = sum(1 for t, _ in test_items if t == "file")
        suite_count = sum(1 for t, _ in test_items if t == "suite")
        verbose = getattr(self, 'test_verbose', False)
        if verbose:
            self.print_info(f"Running {len(test_items)} test item(s) ({file_count} file(s), {suite_count} suite(s))...")

        results: List[TestResult] = []

        for item_type, item_path in test_items:
            if item_type == "file":
                results.append(self._invoke_flat_test(item_path))
            else:
                results.append(self._invoke_suite_test(item_path))

        # Summary
        total_pass = sum(r.pass_count for r in results)
        total_fail = sum(r.fail_count for r in results)
        # Count error-only results (psql crash with no FAIL string) as failures
        error_only = sum(1 for r in results if r.error and r.fail_count == 0)

        suite_passed = sum(1 for r in results if r.is_suite and r.passed)
        suite_failed = sum(1 for r in results if r.is_suite and not r.passed)
        file_passed = sum(1 for r in results if not r.is_suite and r.passed)
        file_failed = sum(1 for r in results if not r.is_suite and not r.passed)

        print()
        self.print_info("=== Test Summary ===")
        self.print_success(f"PASSED: {total_pass}")
        if total_fail > 0 or error_only > 0:
            self.print_error(f"FAILED: {total_fail}" + (f" (+{error_only} error(s))" if error_only else ""))
        else:
            self.print_info(f"FAILED: {total_fail}")
        self.print_info(f"Total:  {total_pass + total_fail}")
        if suite_count > 0:
            self.print_info(f"Suites: {suite_passed} passed, {suite_failed} failed")
        if file_count > 0:
            self.print_info(f"Files:  {file_passed} passed, {file_failed} failed")

        return all(r.passed for r in results)

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

        elif operation == Operation.EXEC_SQL:
            self.print_info("Performing exec SQL operation...")
            return self.exec_sql(self.sql_file, self.sql_command)

        elif operation == Operation.RUN_TESTS:
            self.print_info("Performing run tests operation...")
            return self.run_tests(self.test_filter)

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
            end_number: int = -1,
            sql_file: Optional[str] = None,
            sql_command: Optional[str] = None,
            test_filter: str = "all",
            test_verbose: bool = False) -> bool:
        """Run orchestration with specified operations"""
        self.update_start_number = start_number
        self.update_end_number = end_number
        self.sql_file = sql_file
        self.sql_command = sql_command
        self.test_filter = test_filter
        self.test_verbose = test_verbose

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
    %(prog)s -o execSql --sql "SELECT 1;"
    %(prog)s -o execSql --sql-file script.sql
    %(prog)s -o runTests
    %(prog)s -o runTests --test-filter connection

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
                             'preUpdateScripts, postUpdateScripts, prepareVersionTable, '
                             'execSql, runTests, fullService)')
    parser.add_argument('-s', '--start-number',
                        type=int,
                        default=-1,
                        help='Starting migration file number (default: -1 for all)')
    parser.add_argument('-n', '--end-number',
                        type=int,
                        default=-1,
                        help='Ending migration file number (default: -1 for all)')
    parser.add_argument('--sql-file',
                        help='SQL file to execute (for execSql operation)')
    parser.add_argument('--sql',
                        help='SQL command to execute inline (for execSql operation)')
    parser.add_argument('--test-filter',
                        default='all',
                        help='Filter test files by pattern (for runTests operation, default: all)')
    parser.add_argument('--test-verbose',
                        action='store_true',
                        help='Show all test output including PASS lines (default: silent, only failures shown)')
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
              "preUpdateScripts, postUpdateScripts, prepareVersionTable, execSql, runTests, fullService")
        return 1

    # Create orchestrator and run
    orchestrator = DebeeOrchestrator(environment=args.environment)

    if orchestrator.run(operations, args.start_number, args.end_number,
                        sql_file=args.sql_file, sql_command=args.sql,
                        test_filter=args.test_filter,
                        test_verbose=args.test_verbose):
        return 0
    else:
        return 1


if __name__ == '__main__':
    sys.exit(main())