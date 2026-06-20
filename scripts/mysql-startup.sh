#!/bin/bash
set -uo pipefail

# Zilch MySQL Startup Script
# Runs on e2-micro VM boot to initialize MySQL in Docker

MYSQL_DATA_DIR="/data"
MYSQL_USER="root"
MYSQL_PORT="${MYSQL_PORT}"
MYSQL_APP_USER="zilch_user"
MYSQL_DATABASE="zilch_app"

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/zilch-mysql-startup.log
}

log "Starting Zilch MySQL initialization..."

# Get secrets from Secret Manager (with retry logic)
log "Fetching MySQL credentials from Secret Manager..."
RESOURCE_SUFFIX="${RESOURCE_SUFFIX}"
PROJECT_ID="${PROJECT_ID}"

# Retry secret fetches up to 3 times (metadata server takes time to be ready)
for attempt in 1 2 3; do
    MYSQL_ROOT_PASSWORD=$(gcloud secrets versions access latest --secret="zilch-mysql-root-password-${RESOURCE_SUFFIX}" --project="${PROJECT_ID}" 2>/dev/null | tr -d '\n' || echo "")
    MYSQL_APP_PASSWORD=$(gcloud secrets versions access latest --secret="zilch-mysql-app-password-${RESOURCE_SUFFIX}" --project="${PROJECT_ID}" 2>/dev/null | tr -d '\n' || echo "")

    if [ -n "$MYSQL_ROOT_PASSWORD" ] && [ -n "$MYSQL_APP_PASSWORD" ]; then
        log "Secrets retrieved successfully"
        break
    fi

    if [ $attempt -lt 3 ]; then
        log "Attempt $attempt to fetch secrets failed, retrying in 10 seconds..."
        sleep 10
    else
        log "ERROR: Failed to fetch secrets after 3 attempts"
        exit 1
    fi
done

# Update system packages
log "Updating system packages..."
apt-get update -qq 2>&1 | grep -v "^Get:" || true
apt-get install -qq -y docker.io google-cloud-cli 2>/dev/null || log "WARNING: Package install had issues"

# Start Docker daemon
log "Starting Docker daemon..."
systemctl start docker || log "Docker start failed, retrying..."
sleep 2
systemctl enable docker || true

# Wait for Docker to be ready (up to 60 seconds)
log "Waiting for Docker to be ready..."
DOCKER_READY=false
for i in {1..60}; do
    if docker info > /dev/null 2>&1; then
        log "Docker is ready"
        DOCKER_READY=true
        break
    fi
    if [ $((i % 10)) -eq 0 ]; then
        log "Docker not ready yet (attempt $i/60), waiting..."
    fi
    sleep 1
done

if [ "$DOCKER_READY" = false ]; then
    log "ERROR: Docker failed to start after 60 seconds"
    exit 1
fi

# Create data directory and mount persistent disk
log "Preparing persistent disk..."
if [ ! -d "$MYSQL_DATA_DIR" ]; then
    mkdir -p "$MYSQL_DATA_DIR"
fi

# Format and mount persistent disk (if not already mounted)
if ! mountpoint -q "$MYSQL_DATA_DIR"; then
    DISK_DEVICE=$(lsblk -np -o NAME,SERIAL | grep mysql-data | awk '{print $1}')
    if [ -z "$DISK_DEVICE" ]; then
        log "Warning: Could not find persistent disk, using local storage"
    else
        log "Formatting persistent disk: $DISK_DEVICE"
        mkfs.ext4 -F "$DISK_DEVICE" > /dev/null 2>&1 || true

        log "Mounting persistent disk to $MYSQL_DATA_DIR"
        mount "$DISK_DEVICE" "$MYSQL_DATA_DIR" || log "Warning: Failed to mount disk"
    fi
fi

chmod 755 "$MYSQL_DATA_DIR"

# Create MySQL data directory
log "Creating MySQL data directory..."
mkdir -p "$MYSQL_DATA_DIR/mysql"
chmod 700 "$MYSQL_DATA_DIR/mysql"

# Create data directory
log "Preparing persistent disk..."
mkdir -p "$MYSQL_DATA_DIR/mysql"
chmod 755 "$MYSQL_DATA_DIR"
chmod 700 "$MYSQL_DATA_DIR/mysql"

# Check if MySQL is already running
if docker ps -a --format "{{.Names}}" 2>/dev/null | grep -q "mysql-server"; then
    log "MySQL container already exists, restarting it..."
    docker stop mysql-server 2>/dev/null || true
    sleep 2
    docker start mysql-server || log "WARNING: Container start may have failed"
else
    log "Starting MySQL container..."
    if docker run \
        --name mysql-server \
        --restart=always \
        -d \
        -e "MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD" \
        -e "MYSQL_DATABASE=$MYSQL_DATABASE" \
        -e "MYSQL_USER=$MYSQL_APP_USER" \
        -e "MYSQL_PASSWORD=$MYSQL_APP_PASSWORD" \
        -p "${MYSQL_PORT}:3306" \
        -v "$MYSQL_DATA_DIR/mysql":/var/lib/mysql \
        mysql:8.0 \
        --default-authentication-plugin=mysql_native_password \
        --max_connections=200 \
        --character-set-server=utf8mb4 \
        --collation-server=utf8mb4_unicode_ci; then
        log "MySQL container started successfully"
    else
        log "ERROR: Failed to start MySQL container"
        exit 1
    fi
fi

# Wait for MySQL to be ready (up to 120 seconds)
log "Waiting for MySQL to accept connections..."
MYSQL_READY=false
for i in {1..120}; do
    if docker exec mysql-server mysql -u"$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" > /dev/null 2>&1; then
        log "MySQL is ready and accepting connections"
        MYSQL_READY=true
        break
    fi
    if [ $((i % 20)) -eq 0 ]; then
        log "Attempt $i/120: MySQL not ready yet, waiting..."
    fi
    sleep 1
done

if [ "$MYSQL_READY" = false ]; then
    log "ERROR: MySQL failed to start after 120 seconds"
    docker logs mysql-server | tail -20 >> /var/log/zilch-mysql-startup.log
    exit 1
fi

# Verify database and user are created
log "Verifying database and user..."
docker exec mysql-server mysql -u"$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES LIKE '$MYSQL_DATABASE';" 2>&1 | tee -a /var/log/zilch-mysql-startup.log || true
docker exec mysql-server mysql -u"$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" -e "SELECT User FROM mysql.user WHERE User='$MYSQL_APP_USER';" 2>&1 | tee -a /var/log/zilch-mysql-startup.log || true

log "MySQL initialization complete"
