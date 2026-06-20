#!/bin/bash
set -e

# --- ZILCH TEARDOWN SCRIPT ---
# Safely destroys all Zilch infrastructure and cleans up the remote state bucket

clear
echo "================================================================="
echo "  ⚠️  ZILCH INFRASTRUCTURE TEARDOWN ⚠️"
echo "================================================================="
echo ""
echo "This script will:"
echo "  1. Destroy all Terraform-managed resources"
echo "  2. Delete the remote state bucket"
echo "  3. Clean up your GCP project"
echo ""
echo "⚠️  WARNING: This action is IRREVERSIBLE."
echo ""

# --- PREREQUISITE CHECKS ---

echo "🔍 Checking prerequisites..."
echo ""

# 1. Verify gcloud authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q '@'; then
    echo "❌ Error: No active gcloud authentication found."
    echo ""
    echo "Please log in first:"
    echo "  gcloud auth login"
    exit 1
fi

CURRENT_USER=$(gcloud config get-value account)
echo "✓ Authenticated as: ${CURRENT_USER}"

# --- LOAD CONFIG ---

PROJECT_ID=""
APP_NAME=""
GCP_REGION="us-central1"
GCP_BILLING_ACCOUNT_ID=""

if [ -f ".zilch.config" ]; then
    echo "📋 Reading .zilch.config..."
    # Parse config file safely without executing code
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ "$key" = "gcp_project_id" ] && PROJECT_ID="$value"
        [ "$key" = "app_name" ] && APP_NAME="$value"
        [ "$key" = "gcp_region" ] && GCP_REGION="$value"
        [ "$key" = "gcp_billing_account_id" ] && GCP_BILLING_ACCOUNT_ID="$value"
    done < .zilch.config
fi

# If not found in config, prompt
if [ -z "$PROJECT_ID" ]; then
    read -p "👉 Enter your GCP Project ID: " PROJECT_ID
fi

if [ -z "$APP_NAME" ]; then
    read -p "👉 Enter your application name: " APP_NAME
fi

if [ -z "$PROJECT_ID" ] || [ -z "$APP_NAME" ]; then
    echo "❌ Error: Project ID and app name are required."
    exit 1
fi

# Verify project exists
if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    echo "❌ Error: Project '$PROJECT_ID' not found or you don't have access."
    exit 1
fi

echo "✓ Project found: ${PROJECT_ID}"
echo "✓ Application: ${APP_NAME}"
echo ""

# --- CONFIRMATION PROMPTS ---

echo "🚨 FINAL WARNING 🚨"
echo ""
echo "You are about to DELETE:"
echo "  • Cloud Run service: ${APP_NAME}"
echo "  • All enabled services (Firestore, Storage, Pub/Sub, etc.)"
echo "  • Service accounts and IAM bindings"
echo "  • Terraform state bucket: ${PROJECT_ID}-zilch-tfstate"
echo ""
echo "This CANNOT be undone. All running applications will stop."
echo ""

read -p "⚠️  Type 'destroy' to confirm teardown: " CONFIRM

if [ "$CONFIRM" != "destroy" ]; then
    echo "❌ Teardown cancelled."
    exit 0
fi

echo ""
read -p "⚠️  Type '${PROJECT_ID}' to confirm project ID: " PROJECT_CONFIRM

if [ "$PROJECT_CONFIRM" != "$PROJECT_ID" ]; then
    echo "❌ Project ID mismatch. Teardown cancelled."
    exit 1
fi

echo ""
echo "🔓 Understood. Proceeding with teardown..."
echo ""

# Set the project context
gcloud config set project "$PROJECT_ID" --quiet

# --- TERRAFORM DESTROY ---

echo "🚀 Running terraform destroy..."
echo ""

# Export quota project for billing API access in Terraform
export GOOGLE_CLOUD_QUOTA_PROJECT="${PROJECT_ID}"

if ! terraform -chdir="$(dirname "$0")" destroy -auto-approve \
    -var="gcp_project_id=${PROJECT_ID}" \
    -var="app_name=${APP_NAME}" \
    -var="gcp_region=${GCP_REGION}" \
    -var="github_owner=" \
    -var="github_repo=" \
    -var="enable_cloud_build=false" \
    -var="enable_firestore=false" \
    -var="enable_secret_manager=false" \
    -var="enable_cloud_storage=false" \
    -var="enable_firebase_auth=false" \
    -var="enable_vertex_ai=false" \
    -var="enable_pubsub=false" \
    -var="enable_cloud_tasks=false" \
    -var="enable_bigquery=false" \
    -var="enable_cloud_kms=false" \
    -var="enable_vision_ai=false" \
    -var="enable_speech_to_text=false" \
    -var="enable_translation=false" \
    -var="enable_scheduler=false" \
    -var="enable_monitoring=false" \
    -var="billing_budget_limit_usd=10"; then
    echo "⚠️  Terraform destroy encountered errors. Continuing cleanup..."
fi

echo ""
echo "✓ Terraform resources destroyed"

# --- CLEANUP STATE BUCKET ---

STATE_BUCKET="${PROJECT_ID}-zilch-tfstate"
echo ""
echo "🧹 Cleaning up remaining resources..."

# Manually delete resources that Terraform couldn't handle
echo "  Deleting Cloud Run services..."
gcloud run services delete "${APP_NAME}" --region="us-central1" --project="$PROJECT_ID" --quiet 2>/dev/null || true

echo "  Deleting service accounts..."
gcloud iam service-accounts delete "${APP_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID" --quiet 2>/dev/null || true
gcloud iam service-accounts delete "${APP_NAME}-builder@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID" --quiet 2>/dev/null || true

echo "  Deleting Pub/Sub topics..."
gcloud pubsub topics delete "${APP_NAME}-budget-alerts" --project="$PROJECT_ID" --quiet 2>/dev/null || true
gcloud pubsub topics delete "${APP_NAME}-events" --project="$PROJECT_ID" --quiet 2>/dev/null || true

echo "  Deleting Firestore databases..."
gcloud firestore databases delete --database='(default)' --project="$PROJECT_ID" --quiet 2>/dev/null || true

echo "  Deleting Cloud Build logs buckets..."
gcloud storage buckets delete "gs://${PROJECT_ID}_cloudbuild" --project="$PROJECT_ID" --quiet 2>/dev/null || true

echo "  Deleting storage buckets..."
gcloud storage buckets list --project="$PROJECT_ID" --filter="name:${APP_NAME}" --format="value(name)" 2>/dev/null | while read -r bucket; do
    [ -n "$bucket" ] && gcloud storage buckets delete "gs://$bucket" --project="$PROJECT_ID" --quiet 2>/dev/null || true
done

echo "  Deleting artifact registries..."
gcloud artifacts repositories delete "${APP_NAME}-images" --location=us-central1 --project="$PROJECT_ID" --quiet 2>/dev/null || true

echo "  Deleting Pub/Sub subscriptions..."
gcloud pubsub subscriptions list --project="$PROJECT_ID" --filter="name:${APP_NAME}" --format="value(name)" 2>/dev/null | while read -r sub; do
    [ -n "$sub" ] && gcloud pubsub subscriptions delete "$sub" --project="$PROJECT_ID" --quiet 2>/dev/null || true
done

echo "  Deleting BigQuery datasets..."
gcloud bigquery datasets list --project="$PROJECT_ID" --filter="name:$(echo ${APP_NAME} | tr '-' '_')" --format="value(name)" 2>/dev/null | while read -r dataset; do
    [ -n "$dataset" ] && gcloud bigquery datasets delete --dataset="$dataset" --project="$PROJECT_ID" --quiet 2>/dev/null || true
done

echo "  Deleting secrets..."
gcloud secrets list --project="$PROJECT_ID" --filter="name:${APP_NAME}" --format="value(name)" 2>/dev/null | while read -r secret; do
    [ -n "$secret" ] && gcloud secrets delete "$secret" --project="$PROJECT_ID" --quiet 2>/dev/null || true
done

echo "  Deleting KMS keyrings (30-day scheduled deletion)..."
gcloud kms keyrings list --location=us-central1 --project="$PROJECT_ID" --filter="name:${APP_NAME}" --format="value(name)" 2>/dev/null | while read -r keyring; do
    [ -n "$keyring" ] && gcloud kms keyrings delete "$keyring" --location=us-central1 --project="$PROJECT_ID" --quiet 2>/dev/null || true
done

echo "  Deleting Cloud Build triggers..."
gcloud builds triggers delete "${APP_NAME}-trigger" --project="$PROJECT_ID" --quiet 2>/dev/null || true

echo "  Deleting Cloud Tasks queues..."
gcloud cloud-tasks queues list --project="$PROJECT_ID" --location=us-central1 --filter="name:${APP_NAME}" --format="value(name)" 2>/dev/null | while read -r queue; do
    [ -n "$queue" ] && gcloud cloud-tasks queues delete "$queue" --location=us-central1 --project="$PROJECT_ID" --quiet 2>/dev/null || true
done

echo "  Deleting billing budgets..."
if [ -n "$GCP_BILLING_ACCOUNT_ID" ]; then
    gcloud beta billing budgets list --billing-account="$GCP_BILLING_ACCOUNT_ID" \
        --filter="displayName:${APP_NAME}" --format="value(name)" 2>/dev/null | while read -r budget_name; do
        if [ -n "$budget_name" ]; then
            gcloud beta billing budgets delete "$budget_name" --quiet 2>/dev/null || true
        fi
    done
fi

echo "  ✓ Manual cleanup complete"
echo ""
echo "🗑️  Cleaning up state bucket: gs://${STATE_BUCKET}..."

# Delete all objects in the bucket
if gcloud storage ls "gs://${STATE_BUCKET}/" &>/dev/null 2>&1; then
    echo "  Deleting bucket contents..."
    if gcloud storage rm "gs://${STATE_BUCKET}/" --recursive --quiet &>/dev/null 2>&1; then
        echo "  ✓ Bucket contents deleted"
    else
        echo "  ⚠️  Could not delete bucket contents (may be locked)"
    fi
fi

# Delete the bucket itself
if gcloud storage buckets describe "gs://${STATE_BUCKET}" &>/dev/null 2>&1; then
    echo "  Deleting state bucket..."
    if gcloud storage buckets delete "gs://${STATE_BUCKET}" --quiet &>/dev/null 2>&1; then
        echo "  ✓ State bucket deleted"
    else
        echo "  ⚠️  Could not delete state bucket (may have retention policies)"
        echo "     Manual cleanup may be needed: gcloud storage buckets delete gs://${STATE_BUCKET}"
    fi
fi

# --- CLEANUP TERRAFORM BACKEND STATE ---

echo ""
echo "🔧 Cleaning up local Terraform state..."

if [ -d ".terraform" ]; then
    rm -rf .terraform
    echo "  ✓ Removed .terraform directory"
fi

if [ -f ".terraform.lock.hcl" ]; then
    rm .terraform.lock.hcl
    echo "  ✓ Removed .terraform.lock.hcl"
fi

# --- FINAL CLEANUP ---

echo ""
echo "📋 Optional: Remove configuration files?"
echo ""
echo "The following files contain your deployment configuration:"
echo "  • .zilch.config (GCP Project ID, service toggles, etc.)"
echo "  • .gitignore (Git ignore rules)"
echo ""

read -p "Delete .zilch.config? (y/n) [default: n]: " DELETE_CONFIG
if [[ "$DELETE_CONFIG" =~ ^[Yy]$ ]]; then
    if [ -f ".zilch.config" ]; then
        rm .zilch.config
        echo "✓ Deleted .zilch.config"
    fi
fi

echo ""
echo "================================================================="
echo " ✅ TEARDOWN COMPLETE"
echo "================================================================="
echo ""
echo "📌 Summary:"
echo "  ✓ All Terraform resources destroyed"
echo "  ✓ State bucket cleaned up"
echo "  ✓ Local Terraform state removed"
echo ""
echo "🎯 To redeploy: ./deploy.sh"
echo ""
echo "💡 Need help? Check the logs:"
echo "   gcloud run logs read ${APP_NAME} --region=us-central1"
echo ""
echo "================================================================="
