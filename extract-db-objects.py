#!/usr/bin/env python3
"""
Extract database objects (tables, indexes, functions, procedures) from SQL migration files.
Tracks all updates and determines the latest version of each object.

Also scans ad-hoc scripts from directory specified by DBADHOCDIRECTORY environment variable.
Ad-hoc files are marked with (AD-HOC) prefix in output for easy identification.
"""

import os
import re
import json
import csv
import argparse
from pathlib import Path
from typing import Dict, List, Tuple, Any

def get_sql_files() -> List[Path]:
    """Get all SQL files in order based on numbering."""
    sql_files = []

    # Get migration files from current directory
    for file_path in Path('.').glob('*.sql'):
        name = file_path.name
        if re.match(r'^\d{3}_', name) or re.match(r'^9\d_', name) or name == '999-examples.sql':
            sql_files.append(file_path)

    # Get ad-hoc files from environment-specified directory
    adhoc_dir = os.environ.get('DBADHOCDIRECTORY', '')
    if adhoc_dir and Path(adhoc_dir).exists():
        print(f"Scanning ad-hoc directory: {adhoc_dir}")
        for file_path in Path(adhoc_dir).glob('**/*.sql'):
            if file_path.is_file():
                sql_files.append(file_path)

    # Sort by type and number
    def sort_key(path):
        name = path.name
        # Migration files get priority based on number
        if match := re.match(r'^(\d{3})_', name):
            return (0, int(match.group(1)))
        elif match := re.match(r'^9(\d)_', name):
            return (0, 90 + int(match.group(1)))
        elif name == '999-examples.sql':
            return (0, 999)
        # Ad-hoc files come after migration files, sorted alphabetically
        else:
            return (1, str(path))

    return sorted(sql_files, key=sort_key)

def parse_sql_objects(content: str, filename: str) -> List[Dict[str, Any]]:
    """Parse SQL content to extract database objects."""
    objects = []
    lines = content.split('\n')

    # Updated patterns with better capture groups
    patterns = {
        'function': [
            r'^\s*(CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION)\s+([a-zA-Z_][a-zA-Z0-9_.]*)\s*\(',
            r'^\s*(DROP\s+FUNCTION)(?:\s+IF\s+EXISTS)?\s+([a-zA-Z_][a-zA-Z0-9_.]*)'
        ],
        'procedure': [
            r'^\s*(CREATE\s+(?:OR\s+REPLACE\s+)?PROCEDURE)\s+([a-zA-Z_][a-zA-Z0-9_.]*)\s*\(',
            r'^\s*(DROP\s+PROCEDURE)(?:\s+IF\s+EXISTS)?\s+([a-zA-Z_][a-zA-Z0-9_.]*)'
        ],
        'table': [
            r'^\s*(CREATE\s+(?:UNLOGGED\s+|TEMPORARY\s+|TEMP\s+)?TABLE)(?:\s+IF\s+NOT\s+EXISTS)?\s+([a-zA-Z_][a-zA-Z0-9_.]*)',
            r'^\s*(ALTER\s+TABLE)\s+([a-zA-Z_][a-zA-Z0-9_.]*)',
            r'^\s*(DROP\s+TABLE)(?:\s+IF\s+EXISTS)?\s+([a-zA-Z_][a-zA-Z0-9_.]*)'
        ],
        'index': [
            r'^\s*(CREATE\s+(?:UNIQUE\s+)?INDEX)(?:\s+CONCURRENTLY)?(?:\s+IF\s+NOT\s+EXISTS)?\s+([a-zA-Z_][a-zA-Z0-9_.]*)\s+ON',
            r'^\s*(DROP\s+INDEX)(?:\s+CONCURRENTLY)?(?:\s+IF\s+EXISTS)?\s+([a-zA-Z_][a-zA-Z0-9_.]*)',
            r'^\s*(ALTER\s+INDEX)\s+([a-zA-Z_][a-zA-Z0-9_.]*)'
        ],
        'view': [
            r'^\s*(CREATE\s+(?:OR\s+REPLACE\s+)?VIEW)\s+([a-zA-Z_][a-zA-Z0-9_.]*)',
            r'^\s*(DROP\s+VIEW)(?:\s+IF\s+EXISTS)?\s+([a-zA-Z_][a-zA-Z0-9_.]*)'
        ],
        'trigger': [
            r'^\s*(CREATE\s+(?:OR\s+REPLACE\s+)?TRIGGER)\s+([a-zA-Z_][a-zA-Z0-9_.]*)',
            r'^\s*(DROP\s+TRIGGER)(?:\s+IF\s+EXISTS)?\s+([a-zA-Z_][a-zA-Z0-9_.]*)'
        ],
        'schema': [
            r'^\s*(CREATE\s+SCHEMA)(?:\s+IF\s+NOT\s+EXISTS)?\s+([a-zA-Z_][a-zA-Z0-9_.]*)',
            r'^\s*(DROP\s+SCHEMA)(?:\s+IF\s+EXISTS)?\s+([a-zA-Z_][a-zA-Z0-9_.]*)'
        ]
    }

    for line_num, line in enumerate(lines, 1):
        line = line.strip()

        # Skip comments and empty lines
        if not line or line.startswith('--') or line.startswith('/*'):
            continue

        for object_type, type_patterns in patterns.items():
            for pattern in type_patterns:
                match = re.match(pattern, line, re.IGNORECASE)
                if match:
                    operation_text = match.group(1).strip().upper()
                    object_name = match.group(2).strip()

                    # Parse operation type
                    if 'CREATE' in operation_text:
                        if 'REPLACE' in operation_text:
                            operation = 'CREATE_OR_REPLACE'
                        else:
                            operation = 'CREATE'
                    elif 'ALTER' in operation_text:
                        operation = 'ALTER'
                    else:
                        operation = 'DROP'

                    # Parse schema and name
                    if '.' in object_name:
                        schema, name = object_name.split('.', 1)
                    else:
                        schema = 'public'
                        name = object_name

                    objects.append({
                        'schema': schema,
                        'object_name': name,
                        'object_type': object_type,
                        'operation': operation,
                        'file': filename,
                        'line': line_num,
                        'full_line': line
                    })
                    break

    return objects

def process_files() -> Dict[str, Dict[str, Any]]:
    """Process all SQL files and extract objects."""
    all_objects = {}
    sql_files = get_sql_files()

    print(f"Scanning {len(sql_files)} SQL files...")

    for file_path in sql_files:
        print(f"Processing: {file_path.name}")

        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
        except UnicodeDecodeError:
            try:
                with open(file_path, 'r', encoding='latin1') as f:
                    content = f.read()
            except Exception as e:
                print(f"Error reading {file_path}: {e}")
                continue

        objects = parse_sql_objects(content, file_path.name)

        # Determine if this file is from ad-hoc directory
        adhoc_dir = os.environ.get('DBADHOCDIRECTORY', '')
        is_adhoc = False
        if adhoc_dir:
            # Normalize paths for comparison
            adhoc_path_normalized = Path(adhoc_dir).resolve()
            file_path_resolved = file_path.resolve()
            # Check if file is within the ad-hoc directory
            try:
                file_path_resolved.relative_to(adhoc_path_normalized)
                is_adhoc = True
            except ValueError:
                # file_path is not relative to adhoc_path
                is_adhoc = False

        source_type = 'ad-hoc' if is_adhoc else 'migration'

        for obj in objects:
            key = f"{obj['schema']}.{obj['object_name']}.{obj['object_type']}"

            if key not in all_objects:
                all_objects[key] = {
                    'schema': obj['schema'],
                    'object_name': obj['object_name'],
                    'object_type': obj['object_type'],
                    'all_updates': [],
                    'last_update_file': '',
                    'last_update_line': 0,
                    'last_update_source': ''
                }

            # Add this update with source information
            all_objects[key]['all_updates'].append({
                'file': obj['file'],
                'line': obj['line'],
                'operation': obj['operation'],
                'source': source_type
            })

            # Update latest reference
            all_objects[key]['last_update_file'] = obj['file']
            all_objects[key]['last_update_line'] = obj['line']
            all_objects[key]['last_update_source'] = source_type

    return all_objects

def output_json(objects: Dict[str, Dict[str, Any]], output_file: str = None):
    """Output objects as JSON."""
    results = []

    for key in sorted(objects.keys()):
        obj = objects[key]

        results.append({
            'schema': obj['schema'],
            'object_name': obj['object_name'],
            'object_type': obj['object_type'],
            'last_update_file': obj['last_update_file'],
            'last_update_line': obj['last_update_line'],
            'last_update_source': obj.get('last_update_source', 'migration'),
            'total_updates': len(obj['all_updates']),
            'all_updates': obj['all_updates']  # Now includes 'source' field for each update
        })

    output = json.dumps(results, indent=2)

    if output_file:
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(output)
        print(f"Output saved to: {output_file}")
    else:
        print(output)

def output_csv(objects: Dict[str, Dict[str, Any]], output_file: str = None):
    """Output objects as CSV."""
    results = []

    for key in sorted(objects.keys()):
        obj = objects[key]
        # Include source in each update entry
        all_updates_str = "; ".join([f"{u['file']}:{u['line']}:{u['operation']}({u.get('source', 'migration')})" for u in obj['all_updates']])

        # Use the last update source from the object
        last_source = obj.get('last_update_source', 'migration')
        last_source_display = 'Ad-hoc' if last_source == 'ad-hoc' else 'Migration'

        results.append({
            'Schema': obj['schema'],
            'ObjectName': obj['object_name'],
            'ObjectType': obj['object_type'],
            'LastUpdateFile': obj['last_update_file'],
            'LastUpdateLine': obj['last_update_line'],
            'TotalUpdates': len(obj['all_updates']),
            'LastUpdateSource': last_source_display,
            'AllUpdates': all_updates_str
        })

    if output_file:
        with open(output_file, 'w', newline='', encoding='utf-8') as f:
            if results:
                writer = csv.DictWriter(f, fieldnames=results[0].keys())
                writer.writeheader()
                writer.writerows(results)
        print(f"Output saved to: {output_file}")
    else:
        if results:
            writer = csv.DictWriter(sys.stdout, fieldnames=results[0].keys())
            writer.writeheader()
            writer.writerows(results)

def escape_markdown(text: str) -> str:
    """Escape special markdown characters in text."""
    # Escape underscores to prevent italic formatting
    return text.replace('_', '\\_')

def output_markdown(objects: Dict[str, Dict[str, Any]], output_file: str = None):
    """Output objects as Markdown."""
    lines = [
        "# Database Objects Tracking\n",
        "| Schema | Object Name | Type | Last File | Line | Updates | Migration Updates | Ad-hoc Updates |",
        "|--------|-------------|------|-----------|------|---------|------------------|----------------|"
    ]

    for key in sorted(objects.keys()):
        obj = objects[key]

        # Separate migration and ad-hoc updates
        migration_updates = []
        adhoc_updates = []

        for u in obj['all_updates']:
            update_str = f"{escape_markdown(u['file'])}:{u['line']}"
            source = u.get('source', 'migration')
            if source == 'ad-hoc':
                adhoc_updates.append(update_str)
            else:
                migration_updates.append(update_str)

        # Reverse order so latest updates appear at the bottom (chronological order)
        migration_updates.reverse()
        adhoc_updates.reverse()

        migration_updates_str = "<br>".join(migration_updates) if migration_updates else "-"
        adhoc_updates_str = "<br>".join(adhoc_updates) if adhoc_updates else "-"

        # Escape markdown characters in object names and file paths
        schema_escaped = escape_markdown(obj['schema'])
        object_name_escaped = escape_markdown(obj['object_name'])
        last_file_escaped = escape_markdown(obj['last_update_file'])

        lines.append(
            f"| {schema_escaped} | {object_name_escaped} | {obj['object_type']} | "
            f"{last_file_escaped} | {obj['last_update_line']} | "
            f"{len(obj['all_updates'])} | {migration_updates_str} | {adhoc_updates_str} |"
        )

    # Add summary
    total_objects = len(objects)
    by_type = {}
    by_schema = {}
    adhoc_updates = 0
    migration_updates = 0

    for obj in objects.values():
        obj_type = obj['object_type']
        schema = obj['schema']

        by_type[obj_type] = by_type.get(obj_type, 0) + 1
        by_schema[schema] = by_schema.get(schema, 0) + 1

        # Count ad-hoc vs migration updates using the source field
        for update in obj['all_updates']:
            if update.get('source') == 'ad-hoc':
                adhoc_updates += 1
            else:
                migration_updates += 1

    summary_lines = [
        "\n## Summary",
        f"- **Total Objects**: {total_objects}",
        f"- **By Type**: {', '.join([f'{k}: {v}' for k, v in sorted(by_type.items())])}",
        f"- **By Schema**: {', '.join([f'{k}: {v}' for k, v in sorted(by_schema.items())])}"
    ]

    # Add update type summary if there are ad-hoc scripts
    if adhoc_updates > 0:
        summary_lines.append(f"- **Updates**: {migration_updates} migration, {adhoc_updates} ad-hoc")

    lines.extend(summary_lines)

    output = '\n'.join(lines)

    if output_file:
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(output)
        print(f"Output saved to: {output_file}")
    else:
        print(output)

def main():
    parser = argparse.ArgumentParser(description='Extract database objects from SQL migration files')
    parser.add_argument('--format', choices=['json', 'csv', 'markdown'], default='json',
                      help='Output format (default: json)')
    parser.add_argument('--output', help='Output file (default: stdout)')

    args = parser.parse_args()

    # Show configuration
    adhoc_dir = os.environ.get('DBADHOCDIRECTORY', '')
    if adhoc_dir:
        if Path(adhoc_dir).exists():
            print(f"Ad-hoc directory: {adhoc_dir} (found)")
        else:
            print(f"Ad-hoc directory: {adhoc_dir} (not found - will be skipped)")
    else:
        print("Ad-hoc directory: not configured (set DBADHOCDIRECTORY to include ad-hoc scripts)")

    objects = process_files()

    print(f"\nFound {len(objects)} database objects")

    # Show summary by type
    by_type = {}
    for obj in objects.values():
        obj_type = obj['object_type']
        by_type[obj_type] = by_type.get(obj_type, 0) + 1

    print("\nObjects by type:")
    for obj_type, count in sorted(by_type.items()):
        print(f"  {obj_type}: {count}")

    # Generate output
    if args.format == 'json':
        output_json(objects, args.output)
    elif args.format == 'csv':
        output_csv(objects, args.output)
    elif args.format == 'markdown':
        output_markdown(objects, args.output)

if __name__ == '__main__':
    main()