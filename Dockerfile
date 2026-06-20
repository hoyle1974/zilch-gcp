# Zilch Cloud Run Application with Cloud SQL Proxy Support
# Base image for Python applications (adjust as needed for your runtime)
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies for Cloud SQL Proxy and MySQL client
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Install Cloud SQL Proxy (MySQL support)
RUN curl -o /usr/local/bin/cloud_sql_proxy https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 && \
    chmod +x /usr/local/bin/cloud_sql_proxy

# Copy application files (adjust as needed for your project structure)
# COPY requirements.txt .
# RUN pip install --no-cache-dir -r requirements.txt
# COPY . .

# Create startup wrapper script that runs both Cloud SQL Proxy and the app
RUN cat > /app/start.sh <<'EOF'
#!/bin/bash
set -e

if [ ! -z "${ZILCH_MYSQL_HOST:-}" ]; then
    echo "Starting Cloud SQL Proxy for MySQL..."
    /usr/local/bin/cloud_sql_proxy \
        -ip_address_types=PRIVATE \
        -instances="${GCP_PROJECT_ID}:${GCP_REGION}:${ZILCH_MYSQL_VM_NAME}" \
        -use_http_health_check \
        &
    PROXY_PID=$!
    echo "Cloud SQL Proxy started (PID: $PROXY_PID)"
    sleep 2
fi

echo "Starting application..."
exec "$@"
EOF
chmod +x /app/start.sh

# Health check for Cloud Run
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Set entrypoint to wrapper script
ENTRYPOINT ["/app/start.sh"]

# Default command - override with your actual app command
CMD ["python", "app.py"]
