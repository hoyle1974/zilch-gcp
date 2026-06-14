#!/bin/bash
# Test script: Verify GCS backend works before running full deploy.sh
# Usage: ./test-gcs-backend.sh <project-id>

set -e

if [ -z "$1" ]; then
    echo "Usage: ./test-gcs-backend.sh <project-id>"
    exit 1
fi

PROJECT_ID="$1"
TEST_BUCKET="${PROJECT_ID}-zilch-test-$RANDOM"
CURRENT_USER=$(gcloud config get-value account)

echo "=================================================="
echo "GCS Backend Test"
echo "=================================================="
echo "Project: $PROJECT_ID"
echo "User: $CURRENT_USER"
echo "Test Bucket: $TEST_BUCKET"
echo ""

# 1. Verify auth
echo "1️⃣  Testing gcloud authentication..."
if gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q '@'; then
    echo "   ✓ Authenticated"
else
    echo "   ✗ Not authenticated"
    exit 1
fi

# 2. Verify project access
echo "2️⃣  Testing project access..."
if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    echo "   ✓ Project accessible"
else
    echo "   ✗ Project not found"
    exit 1
fi

# 3. Create test bucket
echo "3️⃣  Creating test bucket..."
if gcloud storage buckets create "gs://${TEST_BUCKET}" \
    --project="$PROJECT_ID" \
    --location="us-central1" \
    --uniform-bucket-level-access &>/dev/null; then
    echo "   ✓ Bucket created"
else
    echo "   ✗ Bucket creation failed"
    exit 1
fi

# 4. Test write
echo "4️⃣  Testing write to bucket..."
if echo "test" | gcloud storage cp - "gs://${TEST_BUCKET}/test-write" &>/dev/null; then
    echo "   ✓ Write successful"
else
    echo "   ✗ Write failed"
    gcloud storage buckets delete "gs://${TEST_BUCKET}" --quiet
    exit 1
fi

# 5. Test read
echo "5️⃣  Testing read from bucket..."
if gcloud storage ls "gs://${TEST_BUCKET}/" &>/dev/null; then
    echo "   ✓ Read successful"
else
    echo "   ✗ Read failed"
    gcloud storage buckets delete "gs://${TEST_BUCKET}" --quiet
    exit 1
fi

# 6. Test Terraform backend init
echo "6️⃣  Testing Terraform backend initialization..."
mkdir -p /tmp/tf-test
cat > /tmp/tf-test/test-backend.tf <<EOF
terraform {
  backend "gcs" {}
}

provider "google" {
  project = "$PROJECT_ID"
}

resource "null_resource" "test" {
  triggers = {
    test = "success"
  }
}
EOF

cd /tmp/tf-test
if terraform init \
    -backend-config="bucket=${TEST_BUCKET}" \
    -backend-config="project=${PROJECT_ID}" \
    -backend-config="prefix=test" \
    -no-color &>/dev/null; then
    echo "   ✓ Terraform init successful"
else
    echo "   ✗ Terraform init failed"
    cd /
    gcloud storage buckets delete "gs://${TEST_BUCKET}" --quiet
    exit 1
fi

# Cleanup
echo ""
echo "7️⃣  Cleaning up..."
cd /
rm -rf /tmp/tf-test
gcloud storage rm "gs://${TEST_BUCKET}/test-write" --quiet || true
gcloud storage buckets delete "gs://${TEST_BUCKET}" --quiet
echo "   ✓ Cleanup complete"

echo ""
echo "=================================================="
echo "✅ All tests passed!"
echo "=================================================="
echo ""
echo "Your environment is ready for deploy.sh"
echo "Run: ./deploy.sh"
