#!/bin/bash
set -euo pipefail

# Zilch MySQL Startup Script
# Runs on e2-micro VM boot to initialize MySQL in Docker

MYSQL_DATA_DIR="/data"
MYSQL_USER="root"
MYSQL_ROOT_PASSWORD=$(gcloud secrets versions access latest --secret="zilch-mysql-root-password-${RESOURCE_SUFFIX}")
MYSQL_APP_USER="zilch_user"
MYSQL_APP_PASSWORD=$(gcloud secrets versions access latest --secret="zilch-mysql-app-password-${RESOURCE_SUFFIX}")
MYSQL_DATABASE="zilch_app"

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a /var/log/zilch-mysql-startup.log
}

log "Starting Zilch MySQL initialization..."

# Update system packages
log "Updating system packages..."
apt-get update -qq
apt-get install -qq -y docker.io google-cloud-cli > /dev/null 2>&1

# Start Docker daemon
log "Starting Docker daemon..."
systemctl start docker
systemctl enable docker

# Wait for Docker to be ready
log "Waiting for Docker to be ready..."
for i in {1..30}; do
    if docker info > /dev/null 2>&1; then
        log "Docker is ready"
        break
    fi
    sleep 1
done

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

# Check if MySQL is already running
if docker ps -a --format "{{.Names}}" | grep -q "mysql-server"; then
    log "MySQL container already exists, starting it..."
    docker start mysql-server || true
else
    log "Starting MySQL container..."
    docker run \
        --name mysql-server \
        --restart=always \
        -d \
        -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
        -e MYSQL_DATABASE="$MYSQL_DATABASE" \
        -e MYSQL_USER="$MYSQL_APP_USER" \
        -e MYSQL_PASSWORD="$MYSQL_APP_PASSWORD" \
        -p 3306:3306 \
        -v "$MYSQL_DATA_DIR/mysql":/var/lib/mysql \
        mysql:8.0 \
        --default-authentication-plugin=mysql_native_password \
        --max_connections=200 \
        --character-set-server=utf8mb4 \
        --collation-server=utf8mb4_unicode_ci
fi

# Wait for MySQL to be ready
log "Waiting for MySQL to be ready..."
for i in {1..60}; do
    if docker exec mysql-server mysql -u"$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" > /dev/null 2>&1; then
        log "MySQL is ready"
        break
    fi
    log "Attempt $i/60: MySQL not ready yet, waiting..."
    sleep 1
done

# Verify database and user are created
log "Verifying database and user..."
docker exec mysql-server mysql -u"$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" -e "SHOW DATABASES LIKE '$MYSQL_DATABASE';"
docker exec mysql-server mysql -u"$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" -e "SELECT User FROM mysql.user WHERE User='$MYSQL_APP_USER';"

log "MySQL initialization complete"
