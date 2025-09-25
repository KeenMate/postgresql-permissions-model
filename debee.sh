#!/usr/bin/env bash

# Debee - PostgreSQL Migration Orchestrator (Bash Version)
# Pure orchestration script - all database logic lives in external SQL files

set -e  # Exit on error

# Default values
ENVIRONMENT=""
OPERATIONS=("fullService")
UPDATE_START_NUMBER=-1
UPDATE_END_NUMBER=-1

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_error() {
    echo -e "${RED}Error: $1${NC}" >&2
}

print_warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_info() {
    echo "$1"
}

# Set environment variable
set_env_var() {
    local key=$1
    local value=$2
    export "$key=$value"
}

# Prepare environment from .env file
prepare_environment() {
    local env_file=$1

    if [[ -f "$env_file" ]]; then
        print_info "Loading environment from $env_file"

        # Read file line by line
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip empty lines and comments
            if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
                continue
            fi

            # Check if line contains =
            if [[ "$line" == *"="* ]]; then
                # Extract key and value
                key="${line%%=*}"
                value="${line#*=}"

                # Remove leading/trailing whitespace
                key=$(echo "$key" | xargs)
                value=$(echo "$value" | xargs)

                # Remove quotes if present
                value="${value%\"}"
                value="${value#\"}"
                value="${value%\'}"
                value="${value#\'}"

                # Set environment variable
                set_env_var "$key" "$value"
            else
                print_warning "Skipping invalid line: $line"
            fi
        done < "$env_file"

        print_success "Environment variables set successfully from $env_file"
    else
        print_error "File not found: $env_file"
        return 1
    fi
}

# Set current database
set_current_database() {
    local database_name=$1
    set_env_var "PGDATABASE" "$database_name"
}

# Get files by numeric prefix
get_files_by_numeric_prefix() {
    local start_num=$1
    local end_num=$2

    # Use environment variables if parameters are -1
    if [[ $start_num -eq -1 ]] && [[ -n "$DBUPDATESTARTNUMBER" ]] && [[ $DBUPDATESTARTNUMBER -gt 0 ]]; then
        start_num=$DBUPDATESTARTNUMBER
    fi

    if [[ $end_num -eq -1 ]] && [[ -n "$DBUPDATEENDNUMBER" ]] && [[ $DBUPDATEENDNUMBER -ge 1 ]]; then
        end_num=$DBUPDATEENDNUMBER
    fi

    print_warning "Scripts from: $start_num to: $end_num will be run."

    # Validate range
    if [[ $start_num -gt $end_num ]] && [[ $end_num -ne -1 ]]; then
        print_error "StartNumber ($start_num) cannot be greater than EndNumber ($end_num)."
        return 1
    fi

    # Find matching files
    local matching_files=()

    for file in [0-9][0-9][0-9]_*; do
        if [[ ! -f "$file" ]]; then
            continue
        fi

        # Extract numeric prefix
        prefix="${file:0:3}"
        prefix=$((10#$prefix))  # Convert to decimal (remove leading zeros)

        # Check if within range
        if { [[ $prefix -ge $start_num ]] || [[ $start_num -eq -1 ]]; } && \
           { [[ $prefix -le $end_num ]] || [[ $end_num -eq -1 ]]; }; then
            print_info "File: $file is within the update range."
            matching_files+=("$file")
        fi
    done

    print_info "Number of matching files: ${#matching_files[@]}"

    # Return files (as string, separated by newlines)
    printf '%s\n' "${matching_files[@]}"
}

# Recreate database
recreate_database() {
    set_current_database "$DBCONNECTDB"

    print_info "Recreating database on host: $PGHOST, connected to: $PGDATABASE"

    if [[ -z "$DBRECREATESCRIPT" ]] || [[ ! -f "$DBRECREATESCRIPT" ]]; then
        print_error "Recreation script not found: $DBRECREATESCRIPT"
        return 1
    fi

    $DBPSQLFILE -f "$DBRECREATESCRIPT"
}

# Restore database
restore_database() {
    local backup_filepath="${1:-$DBBACKUPFILE}"
    local backup_type="${2:-$DBBACKUPTYPE}"

    print_info "Calculating backup type and path"

    if [[ -z "$backup_filepath" ]]; then
        print_warning "No restore file defined, skipping"
        return 0
    fi

    local job_count=1
    if [[ -n "$DBRESTOREJOBCOUNT" ]] && [[ $DBRESTOREJOBCOUNT -gt 0 ]]; then
        job_count=$DBRESTOREJOBCOUNT
    fi

    print_warning "Restoring database with $job_count jobs"

    case "$backup_type" in
        "file")
            print_info "Restoring from file: $backup_filepath"
            set_current_database "$DBDESTDB"
            $DBPSQLFILE -f "$backup_filepath"
            ;;
        "dir")
            print_info "Restoring from directory: $backup_filepath"
            set_current_database "$DBDESTDB"

            if [[ "$DBCREATEONRESTORE" == "true" ]]; then
                $DBPGRESTOREFILE -v -F d -C -d "$DBCONNECTDB" "$backup_filepath"
            else
                $DBPGRESTOREFILE -v -F d -d "$DBDESTDB" "$backup_filepath"
            fi
            ;;
        "custom")
            print_info "Restoring from custom archive: $backup_filepath"
            set_current_database "$DBDESTDB"

            if [[ "$DBCREATEONRESTORE" == "true" ]]; then
                $DBPGRESTOREFILE -v -F c -C -d "$DBCONNECTDB" "$backup_filepath"
            else
                $DBPGRESTOREFILE -v -F c -d "$DBDESTDB" "$backup_filepath"
            fi
            ;;
        *)
            print_error "Unknown backup type: $backup_type"
            return 1
            ;;
    esac
}

# Update database with files
update_database_with_files() {
    print_info "Updating database..."
    set_current_database "$DBDESTDB"

    # Process files passed as arguments
    for file in "$@"; do
        if [[ -f "$file" ]] && [[ -s "$file" ]]; then
            print_info ".. with file: $file"
            $DBPSQLFILE -q -b -n --csv -f "$file"
        fi
    done
}

# Update database
update_database() {
    # Get files and store in array
    mapfile -t files < <(get_files_by_numeric_prefix "$UPDATE_START_NUMBER" "$UPDATE_END_NUMBER")

    print_info "Number of returned files: ${#files[@]}"

    if [[ ${#files[@]} -gt 0 ]]; then
        # Sort files and update database
        IFS=$'\n' sorted_files=($(sort <<<"${files[*]}"))
        unset IFS

        update_database_with_files "${sorted_files[@]}"
    fi
}

# Run pre-update scripts
run_pre_update_scripts() {
    if [[ -z "$DBPREUPDATESCRIPTS" ]]; then
        print_info "No pre-update scripts, skipping the step"
        return 0
    fi

    # Split scripts by semicolon
    IFS=';' read -ra scripts <<< "$DBPREUPDATESCRIPTS"

    local scripts_to_run=()

    for script in "${scripts[@]}"; do
        # Trim whitespace
        script=$(echo "$script" | xargs)

        if [[ -f "$script" ]]; then
            scripts_to_run+=("$script")
            print_info "Pre-update script file: $script to be run."
        else
            print_warning "File does not exist: $script"
        fi
    done

    if [[ ${#scripts_to_run[@]} -gt 0 ]]; then
        update_database_with_files "${scripts_to_run[@]}"
    fi
}

# Run post-update scripts
run_post_update_scripts() {
    if [[ -z "$DBPOSTUPDATESCRIPTS" ]]; then
        print_info "No post-update scripts, skipping the step"
        return 0
    fi

    # Split scripts by semicolon
    IFS=';' read -ra scripts <<< "$DBPOSTUPDATESCRIPTS"

    local scripts_to_run=()

    for script in "${scripts[@]}"; do
        # Trim whitespace
        script=$(echo "$script" | xargs)

        if [[ -z "$script" ]]; then
            print_warning "Post-update script path empty, skipping"
            continue
        fi

        if [[ -f "$script" ]]; then
            scripts_to_run+=("$script")
            print_info "Post-update script file: $script to be run."
        else
            print_warning "File does not exist: $script"
        fi
    done

    if [[ ${#scripts_to_run[@]} -gt 0 ]]; then
        update_database_with_files "${scripts_to_run[@]}"
    fi
}

# Prepare version table
prepare_version_table() {
    print_info "Preparing version table - extracting database objects and generating markdown"

    # Check if extract-db-objects.py exists
    if [[ ! -f "extract-db-objects.py" ]]; then
        print_error "extract-db-objects.py not found in current directory"
        return 1
    fi

    # Determine Python command
    local python_cmd
    if command -v python3 &> /dev/null; then
        python_cmd="python3"
    elif command -v python &> /dev/null; then
        python_cmd="python"
    else
        print_error "Python not found. Please install Python 3.6+"
        return 1
    fi

    # Run extract-db-objects.py to generate JSON
    print_info "Extracting database objects to db-objects.json..."
    if ! $python_cmd "extract-db-objects.py" --format json --output "db-objects.json"; then
        print_error "Failed to run extract-db-objects.py"
        return 1
    fi
    print_success "Successfully generated db-objects.json"

    # Check if JSON file was created
    if [[ ! -f "db-objects.json" ]]; then
        print_error "db-objects.json was not created"
        return 1
    fi

    # Generate markdown table from JSON
    print_info "Generating db-objects.md from JSON..."
    if ! $python_cmd "extract-db-objects.py" --format markdown --output "db-objects.md"; then
        print_error "Failed to generate markdown"
        return 1
    fi
    print_success "Successfully generated db-objects.md"

    print_success "Version table preparation completed successfully"
    print_info "Generated files: db-objects.json, db-objects.md"
    return 0
}

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

PostgreSQL Migration Orchestrator - Bash Version

Options:
    -e, --environment ENV       Environment name for configuration
    -o, --operations OPS        Comma-separated operations to perform
                               (recreateDatabase, restoreDatabase, updateDatabase,
                                preUpdateScripts, postUpdateScripts, prepareVersionTable, fullService)
                               Default: fullService
    -s, --start-number NUM     Starting migration file number (default: -1 for all)
    -n, --end-number NUM       Ending migration file number (default: -1 for all)
    -h, --help                 Show this help message

Examples:
    $0 -e prod -o fullService
    $0 -e dev -o restoreDatabase,updateDatabase
    $0 -o updateDatabase -s 10 -n 20

Environment files:
    debee.ENV.env              Environment-specific configuration
    .debee.ENV.env             Local overrides (git-ignored)
    debee.env                  Default configuration (when no environment specified)
    .debee.env                 Local default overrides

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -o|--operations)
            IFS=',' read -ra OPERATIONS <<< "$2"
            shift 2
            ;;
        -s|--start-number)
            UPDATE_START_NUMBER="$2"
            shift 2
            ;;
        -n|--end-number)
            UPDATE_END_NUMBER="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution

# Define environment file paths
if [[ -n "$ENVIRONMENT" ]]; then
    ENV_FILE="debee.$ENVIRONMENT.env"
    LOCAL_ENV_FILE=".debee.$ENVIRONMENT.env"
else
    ENV_FILE="debee.env"
    LOCAL_ENV_FILE=".debee.env"
fi

# Check if environment file exists
if [[ ! -f "$ENV_FILE" ]]; then
    print_error "Could not find $ENV_FILE"
    exit 1
fi

# Load environment files
prepare_environment "$ENV_FILE"

# Load local environment file if it exists
if [[ -f "$LOCAL_ENV_FILE" ]]; then
    prepare_environment "$LOCAL_ENV_FILE"
fi

# Set default tool paths if not defined
: ${DBPSQLFILE:=psql}
: ${DBPGRESTOREFILE:=pg_restore}

# Process operations
for operation in "${OPERATIONS[@]}"; do
    print_info "Processing: $operation"

    case "$operation" in
        "recreateDatabase")
            print_info "Performing recreate operation..."
            recreate_database
            ;;
        "restoreDatabase")
            print_info "Performing restore operation..."
            restore_database
            ;;
        "updateDatabase")
            print_info "Performing update operation..."
            update_database
            ;;
        "preUpdateScripts")
            print_info "Performing pre-update operation..."
            run_pre_update_scripts
            ;;
        "postUpdateScripts")
            print_info "Performing post-update operation..."
            run_post_update_scripts
            ;;
        "prepareVersionTable")
            print_info "Performing prepare version table operation..."
            prepare_version_table
            ;;
        "fullService")
            print_info "Performing full service operation..."
            recreate_database
            restore_database
            run_pre_update_scripts
            update_database
            run_post_update_scripts
            ;;
        *)
            print_error "Invalid operation specified: $operation"
            print_info "Valid operations: recreateDatabase, restoreDatabase, updateDatabase, preUpdateScripts, postUpdateScripts, prepareVersionTable, fullService"
            exit 1
            ;;
    esac
done

print_success "All operations completed successfully!"