#!/bin/bash
set -e

# Clear screen for crisp UX
clear
echo "================================================================="
echo "  ⚡ ZILCH: Scale-to-Zero GCP Infrastructure Installer ⚡"
echo "================================================================="
echo ""

# --- PREREQUISITE CHECKS (Run before any prompts) ---

echo "🔍 Checking prerequisites..."
echo ""

# 1. Verify gcloud authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q '@'; then
    echo "❌ Error: No active gcloud authentication found."
    echo ""
    echo "Please log in first:"
    echo "  gcloud auth login"
    echo ""
    echo "Then run deploy.sh again."
    exit 1
fi

CURRENT_USER=$(gcloud config get-value account)
echo "✓ Authenticated as: ${CURRENT_USER}"

# 2. Get and validate project ID
read -p "👉 Enter your target GCP Project ID: " PROJECT_ID
if [ -z "$PROJECT_ID" ]; then
    echo "❌ Error: Project ID cannot be empty."
    exit 1
fi

# 3. Verify project exists and user has access
if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    echo "❌ Error: Project '$PROJECT_ID' not found or you don't have access."
    echo ""
    echo "Check:"
    echo "  • Project ID spelling is correct"
    echo "  • You have 'Viewer' role on the project"
    exit 1
fi
echo "✓ Project found: ${PROJECT_ID}"

# 4. Verify user has required IAM permissions (Editor or Owner)
echo "✓ Checking IAM permissions..."
ROLE_CHECK=$(gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:${CURRENT_USER} AND (bindings.role:roles/editor OR bindings.role:roles/owner)" \
  --format="value(bindings.role)" 2>/dev/null | head -1)

if [ -z "$ROLE_CHECK" ]; then
    echo "❌ Error: ${CURRENT_USER} does not have Editor or Owner role on project ${PROJECT_ID}."
    echo ""
    echo "Zilch requires Editor or Owner role to:"
    echo "  • Create and manage Cloud Storage buckets"
    echo "  • Enable Google Cloud APIs"
    echo "  • Create service accounts and manage IAM"
    echo ""
    echo "NEXT STEP: Ask your project admin (someone with Owner/Editor role) to run this:"
    echo ""
    echo "  gcloud projects add-iam-policy-binding ${PROJECT_ID} \\"
    echo "    --member=user:${CURRENT_USER} \\"
    echo "    --role=roles/editor"
    echo ""
    echo "Once they've granted you the role, run deploy.sh again."
    exit 1
fi
echo "✓ IAM permissions verified"
echo ""
echo "✅ All prerequisites met. Ready to deploy."
echo ""

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
CURRENT_USER=$(gcloud config get-value account)
echo ""
echo "📦 Setting up remote state bucket..."

# Check if bucket exists
if ! gcloud storage buckets describe "gs://${STATE_BUCKET}" &>/dev/null; then
    echo "🛠️ Creating state bucket 'gs://${STATE_BUCKET}'..."

    # Create bucket
    if ! gcloud storage buckets create "gs://${STATE_BUCKET}" \
        --project="$PROJECT_ID" \
        --location="$REGION" \
        --uniform-bucket-level-access; then
        echo "❌ Failed to create state bucket. You may need Storage Admin permissions."
        echo "Run this to grant yourself permissions:"
        echo "  gcloud projects add-iam-policy-binding $PROJECT_ID --member=user:${CURRENT_USER} --role=roles/storage.admin"
        exit 1
    fi

    echo "✓ State bucket ready"
else
    echo "✓ State bucket exists (reusing)"
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
