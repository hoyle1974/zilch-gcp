#!/bin/bash
set -e

# Clear screen for crisp UX
clear
echo "================================================================="
echo "  ⚡ ZILCH: Scale-to-Zero GCP Infrastructure Installer ⚡"
echo "================================================================="
echo ""

# 1. Verification of Core Authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q '@'; then
    echo "❌ Error: Active gcloud credential context not discovered."
    echo "Please execute 'gcloud auth login' in the terminal window first, then run this installer again."
    exit 1
fi

# 2. Extract Valid Project Identification Context
read -p "👉 Enter your target GCP Project ID: " PROJECT_ID
if [ -z "$PROJECT_ID" ]; then
    echo "❌ Error: Project ID context cannot be empty."
    exit 1
fi

if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    echo "❌ Error: Unable to verify project connection details for '$PROJECT_ID'."
    echo "Confirm spelling parameters or check permissions before retrying."
    exit 1
fi

# Verify user has minimum required IAM permissions
CURRENT_USER=$(gcloud config get-value account)
echo "🔍 Verifying IAM permissions for ${CURRENT_USER}..."

# Check for Editor or Owner role (needed for Cloud Run, Firestore, etc.)
ROLE_CHECK=$(gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:${CURRENT_USER} AND (bindings.role:roles/editor OR bindings.role:roles/owner OR bindings.role:roles/compute.admin)" \
  --format="value(bindings.role)" 2>/dev/null | head -1)

if [ -z "$ROLE_CHECK" ]; then
    echo "⚠️  Warning: ${CURRENT_USER} may not have sufficient permissions."
    echo "Zilch requires one of: Editor, Owner, or Cloud Run Admin + Compute Admin roles."
    read -p "Continue anyway? (y/n): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        echo "Aborted. Please grant yourself the necessary IAM roles and try again."
        exit 1
    fi
fi

# 3. Read App Name with Formatting Validations
read -p "👉 Enter your application name (e.g., my-awesome-app): " APP_NAME
if [[ ! "$APP_NAME" =~ ^[a-z0-9-]{3,30}$ ]]; then
    echo "❌ Error: Invalid structure. App name must be 3-30 lowercase characters, numbers, or hyphens."
    exit 1
fi

# 4. Standardize Target Region Selection
echo "🌐 Choose your infrastructure anchor zone (Always Free Eligible):"
echo "  [1] us-central1 (Iowa - Preferred Default)"
echo "  [2] us-east1    (South Carolina)"
echo "  [3] us-west1    (Oregon)"
read -p "Selection [1-3]: " REGION_CHOICE

case "$REGION_CHOICE" in
    2) REGION="us-east1" ;;
    3) REGION="us-west1" ;;
    *) REGION="us-central1" ;;
esac

# 5. Capture Service Configuration Feature Flags
prompt_toggle() {
    local feature_name=$1
    read -p "❓ Enable $feature_name support? (y/n): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo "true"
    else
        echo "false"
    fi
}

FIRESTORE=$(prompt_toggle "Firestore NoSQL Database")
SECRETS=$(prompt_toggle "Secret Manager Keys")
STORAGE=$(prompt_toggle "Cloud Storage Asset Buckets")
FIREBASE=$(prompt_toggle "Firebase Social Authentication")
VERTEX=$(prompt_toggle "Vertex AI Gemini Platform")

# 6. Automate State Bucket Isolation (The Bootstrap)
STATE_BUCKET="${PROJECT_ID}-zilch-tfstate"
echo ""
echo "📦 Inspecting remote state architecture parameters..."
if ! gcloud storage buckets describe "gs://${STATE_BUCKET}" &>/dev/null; then
    echo "🛠️ Remote state storage missing. Building state bucket 'gs://${STATE_BUCKET}'..."
    gcloud storage buckets create "gs://${STATE_BUCKET}" --project="$PROJECT_ID" --location="$REGION"

    # Grant the current user Storage Admin on the bucket (needed for Terraform state access)
    CURRENT_USER=$(gcloud config get-value account)
    echo "🔐 Granting Storage permissions to ${CURRENT_USER}..."
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="user:${CURRENT_USER}" \
        --role="roles/storage.admin" \
        --quiet &>/dev/null || true
fi

# 7. Terraform Execution Execution Lifecycle
echo "🚀 Initializing Terraform modules over secure remote state..."
if ! terraform init -backend-config="bucket=${STATE_BUCKET}" -reconfigure; then
    echo "❌ Terraform init failed. Common causes:"
    echo "   • Missing IAM permissions (you may need Editor or Owner role)"
    echo "   • State bucket exists but you don't have access (contact project admin)"
    echo "   • Organization policy restricting Cloud Storage or Terraform"
    echo ""
    echo "To grant yourself permissions, run:"
    echo "  gcloud projects add-iam-policy-binding ${PROJECT_ID} --member=user:${CURRENT_USER} --role=roles/editor"
    exit 1
fi

echo "🏗️ Applying architectural blueprint definitions to Google Cloud..."
if ! terraform apply -auto-approve \
  -var="gcp_project_id=${PROJECT_ID}" \
  -var="app_name=${APP_NAME}" \
  -var="gcp_region=${REGION}" \
  -var="enable_firestore=${FIRESTORE}" \
  -var="enable_secret_manager=${SECRETS}" \
  -var="enable_cloud_storage=${STORAGE}" \
  -var="enable_firebase_auth=${FIREBASE}" \
  -var="enable_vertex_ai=${VERTEX}"; then
    echo "❌ Terraform apply failed. Check the error above."
    echo "   Most common: insufficient permissions for required services."
    exit 1
fi

# 8. Post-Deployment Endpoint Performance Validation Checks
RUN_URL=$(terraform output -raw cloud_run_url)
echo ""
echo "🔍 Initiating app endpoint connection checks at: ${RUN_URL}"

RETRY_COUNT=0
MAX_RETRIES=3
HEALTHY=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$RUN_URL" || echo "000")
    if [ "$HTTP_STATUS" == "200" ]; then
        HEALTHY=true
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT+1))
    echo "⚠️ Ping response read: HTTP ${HTTP_STATUS}. Retrying engine connection ($RETRY_COUNT/$MAX_RETRIES) in 5s..."
    sleep 5
done

if [ "$HEALTHY" = false ]; then
    echo "🚨 Warning: App deployed but automated health checks timed out."
    echo "Review your Cloud Run execution engine console logs to trace unexpected boot failures."
fi

# 9. Format Summary Diagnostics Output
echo ""
echo "================================================================="
echo " 🎉 SUCCESS: Zilch Architecture Instantiated Successfully! "
echo "================================================================="
echo "📍 Service Endpoint URL: ${RUN_URL}"
echo "👤 Bound Run Identity:   $(terraform output -raw service_account_email)"
echo "🌐 Operational Region:   ${REGION}"
echo ""
echo "📋 Available Runtime Application Discovery Environment Tunnels:"
if [ "$FIRESTORE" == "true" ]; then echo "  ↳ ZILCH_FIRESTORE_DATABASE : (default)"; fi
if [ "$SECRETS" == "true" ]; then echo "  ↳ ZILCH_SECRET_PREFIX      : ${APP_NAME}-"; fi
if [ "$STORAGE" == "true" ]; then echo "  ↳ ZILCH_STORAGE_BUCKET     : ${APP_NAME}-storage-$(terraform output -raw storage_bucket 2>/dev/null || echo 'SUFFIX')"; fi
if [ "$VERTEX" == "true" ]; then echo "  ↳ ZILCH_VERTEX_AI_ENABLED  : true"; fi
if [ "$FIREBASE" == "true" ]; then echo "  ↳ ZILCH_FIREBASE_ENABLED   : true"; fi
echo ""
echo "💡 Reminder: Your setup operates completely on Google's Free tier limits."
echo "   Track parameters safely via: https://cloud.google.com/always-free"
echo ""
echo "📚 Next Steps:"
echo "   1. Deploy your code: gcloud run deploy ${APP_NAME} --source ."
echo "   2. View logs: gcloud run logs read ${APP_NAME} --region=${REGION}"
if [ "$FIREBASE" == "true" ]; then
    echo "   3. Configure auth: https://console.firebase.google.com/project/${PROJECT_ID}/authentication"
fi
echo "================================================================="
