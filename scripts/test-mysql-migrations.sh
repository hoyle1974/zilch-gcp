#!/bin/bash
set -euo pipefail

# Test MySQL migrations locally or in CI/CD

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "ERROR: $*" >&2
    exit 1
}

# Check if MySQL is accessible
log "Testing MySQL connectivity..."
mysql -h "${ZILCH_MYSQL_HOST:=127.0.0.1}" \
       -P "${ZILCH_MYSQL_PORT:=3306}" \
       -u "${ZILCH_MYSQL_USER:=zilch_user}" \
       ${ZILCH_MYSQL_PASSWORD:+-p"$ZILCH_MYSQL_PASSWORD"} \
       "${ZILCH_MYSQL_DATABASE:=zilch_app}" \
       -e "SELECT 1" || error "Could not connect to MySQL"

log "MySQL is accessible"

# Run migrations
log "Running migrations..."
cd "$(dirname "${BASH_SOURCE[0]}")/.."
./db/migrate.sh up || error "Migration failed"

# Show status
log "Migration status:"
./db/migrate.sh status

log "All tests passed"
