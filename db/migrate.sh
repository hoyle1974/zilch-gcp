#!/bin/bash
set -euo pipefail

# Zilch MySQL Migration Runner
# Usage: ./migrate.sh [up|down|status|--dry-run]

MIGRATIONS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/migrations" && pwd)"
METADATA_FILE="$MIGRATIONS_DIR/.migration_metadata.json"

# Get MySQL connection parameters
MYSQL_HOST="${ZILCH_MYSQL_HOST:=127.0.0.1}"
MYSQL_PORT="${ZILCH_MYSQL_PORT:=3306}"
MYSQL_DATABASE="${ZILCH_MYSQL_DATABASE:=zilch_app}"
MYSQL_USER="${ZILCH_MYSQL_USER:=zilch_user}"
MYSQL_PASSWORD="${ZILCH_MYSQL_PASSWORD:=}"

# Options
DRY_RUN=false
DIRECTION="up"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        up|down|status)
            DIRECTION="$1"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "ERROR: $*" >&2
    exit 1
}

# Initialize metadata file if not exists
if [ ! -f "$METADATA_FILE" ]; then
    echo '{"applied": [], "pending": []}' > "$METADATA_FILE"
fi

# MySQL query helper
run_sql() {
    local query="$1"

    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN] $query"
    else
        mysql \
            -h "$MYSQL_HOST" \
            -P "$MYSQL_PORT" \
            -u "$MYSQL_USER" \
            ${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} \
            "$MYSQL_DATABASE" \
            -e "$query"
    fi
}

# Run SQL file
run_sql_file() {
    local file="$1"

    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Would execute: $file"
        cat "$file" | head -5
        echo "..."
    else
        log "Executing: $(basename "$file")"
        mysql \
            -h "$MYSQL_HOST" \
            -P "$MYSQL_PORT" \
            -u "$MYSQL_USER" \
            ${MYSQL_PASSWORD:+-p"$MYSQL_PASSWORD"} \
            "$MYSQL_DATABASE" \
            < "$file"
    fi
}

# List migrations
list_migrations() {
    find "$MIGRATIONS_DIR" -name "*.sql" -type f | sort
}

# Apply pending migrations
migrate_up() {
    log "Starting migrations (up)..."

    for migration_file in $(list_migrations); do
        migration_name=$(basename "$migration_file")

        if grep -q "$migration_name" "$METADATA_FILE"; then
            log "Skipping already-applied: $migration_name"
        else
            log "Applying: $migration_name"
            run_sql_file "$migration_file"

            # Record as applied
            if [ "$DRY_RUN" = false ]; then
                # Append to applied list in metadata
                temp_file=$(mktemp)
                jq --arg name "$migration_name" \
                    '.applied += [$name]' \
                    "$METADATA_FILE" > "$temp_file"
                mv "$temp_file" "$METADATA_FILE"
                log "Recorded: $migration_name"
            fi
        fi
    done

    log "Migrations complete"
}

# Show status
show_status() {
    log "Migration Status"
    log "================"

    applied=$(jq -r '.applied[]' "$METADATA_FILE" 2>/dev/null | wc -l)
    log "Applied: $applied"

    log "Applied migrations:"
    jq -r '.applied[]' "$METADATA_FILE" 2>/dev/null | while read -r line; do
        log "  ✓ $line"
    done

    log ""
    log "Pending migrations:"
    for migration_file in $(list_migrations); do
        migration_name=$(basename "$migration_file")
        if ! grep -q "$migration_name" "$METADATA_FILE"; then
            log "  ○ $migration_name"
        fi
    done
}

# Main
case "$DIRECTION" in
    up)
        migrate_up
        ;;
    status)
        show_status
        ;;
    *)
        error "Unknown direction: $DIRECTION"
        ;;
esac
