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

# --- LOAD CONFIG EARLY (before any prompts) ---
# Initialize defaults
PROJECT_ID=""
APP_NAME=""
GCP_REGION="us-central1"
ENABLE_FIRESTORE="false"
ENABLE_SECRET_MANAGER="false"
ENABLE_CLOUD_STORAGE="false"
ENABLE_FIREBASE_AUTH="false"
ENABLE_VERTEX_AI="false"
ENABLE_CLOUD_BUILD="false"
GITHUB_OWNER=""
GITHUB_REPO=""

# Load from .zilch.config if it exists (uses lowercase variable names)
if [ -f ".zilch.config" ]; then
    echo "📋 Reading .zilch.config..."
    source .zilch.config
    # Map lowercase config names to uppercase internal variables
    [ -n "$gcp_project_id" ] && PROJECT_ID="$gcp_project_id"
    [ -n "$app_name" ] && APP_NAME="$app_name"
    [ -n "$gcp_region" ] && GCP_REGION="$gcp_region"
    [ -n "$enable_firestore" ] && ENABLE_FIRESTORE="$enable_firestore"
    [ -n "$enable_secret_manager" ] && ENABLE_SECRET_MANAGER="$enable_secret_manager"
    [ -n "$enable_cloud_storage" ] && ENABLE_CLOUD_STORAGE="$enable_cloud_storage"
    [ -n "$enable_firebase_auth" ] && ENABLE_FIREBASE_AUTH="$enable_firebase_auth"
    [ -n "$enable_vertex_ai" ] && ENABLE_VERTEX_AI="$enable_vertex_ai"
    [ -n "$enable_cloud_build" ] && ENABLE_CLOUD_BUILD="$enable_cloud_build"
    [ -n "$github_owner" ] && GITHUB_OWNER="$github_owner"
    [ -n "$github_repo" ] && GITHUB_REPO="$github_repo"
    echo "✓ Configuration loaded"
fi

# 2. Get and validate project ID (with default from config)
DEFAULT_PROJECT="${PROJECT_ID:-}"
if [ -z "$DEFAULT_PROJECT" ]; then
    read -p "👉 Enter your target GCP Project ID: " PROJECT_ID
else
    read -p "👉 Enter your target GCP Project ID [$DEFAULT_PROJECT]: " INPUT
    PROJECT_ID="${INPUT:-$DEFAULT_PROJECT}"
fi
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

# --- INTERACTIVE PROMPTS WITH DEFAULTS FROM CONFIG ---

# 3. Read App Name (with default from config)
DEFAULT_APP_NAME="${APP_NAME:-zilch-app}"
read -p "👉 Enter your application name [$DEFAULT_APP_NAME]: " INPUT_APP_NAME
APP_NAME="${INPUT_APP_NAME:-$DEFAULT_APP_NAME}"

if [[ ! "$APP_NAME" =~ ^[a-z0-9-]{3,30}$ ]]; then
    echo "❌ Error: Invalid structure. App name must be 3-30 lowercase characters, numbers, or hyphens."
    exit 1
fi

# 4. Standardize Target Region Selection (with default from config)
echo ""
echo "🌐 Choose your infrastructure anchor zone (Always Free Eligible):"
echo "  [1] us-central1 (Iowa - Preferred Default)"
echo "  [2] us-east1    (South Carolina)"
echo "  [3] us-west1    (Oregon)"

# Show current region as default
REGION_DEFAULT="1"
[ "$GCP_REGION" = "us-east1" ] && REGION_DEFAULT="2"
[ "$GCP_REGION" = "us-west1" ] && REGION_DEFAULT="3"

read -p "Selection [1-3, default: $REGION_DEFAULT]: " REGION_CHOICE
REGION_CHOICE="${REGION_CHOICE:-$REGION_DEFAULT}"

case "$REGION_CHOICE" in
    2) GCP_REGION="us-east1" ;;
    3) GCP_REGION="us-west1" ;;
    *) GCP_REGION="us-central1" ;;
esac

# 5. Capture Service Configuration Feature Flags
prompt_toggle() {
    local feature_name=$1
    local current_value=$2

    # Show current value as default
    local default_response="n"
    if [ "$current_value" = "true" ]; then
        default_response="y"
    fi

    read -p "❓ Enable $feature_name support? (y/n) [default: $default_response]: " choice
    choice="${choice:-$default_response}"

    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo "true"
    else
        echo "false"
    fi
}

echo ""
ENABLE_FIRESTORE=$(prompt_toggle "Firestore NoSQL Database" "$ENABLE_FIRESTORE")
ENABLE_SECRET_MANAGER=$(prompt_toggle "Secret Manager Keys" "$ENABLE_SECRET_MANAGER")
ENABLE_CLOUD_STORAGE=$(prompt_toggle "Cloud Storage Asset Buckets" "$ENABLE_CLOUD_STORAGE")

ENABLE_CLOUD_BUILD=$(prompt_toggle "Cloud Build CI/CD (recommended)" "$ENABLE_CLOUD_BUILD")
ENABLE_FIREBASE_AUTH=$(prompt_toggle "Firebase Social Authentication" "$ENABLE_FIREBASE_AUTH")
ENABLE_VERTEX_AI=$(prompt_toggle "Vertex AI Gemini Platform" "$ENABLE_VERTEX_AI")

# If Cloud Build is enabled, GitHub info is required
if [ "$ENABLE_CLOUD_BUILD" == "true" ]; then
    if [ -z "$GITHUB_OWNER" ] || [ -z "$GITHUB_REPO" ]; then
        echo ""
        echo "❌ Error: Cloud Build enabled but GitHub not configured in .zilch.config"
        echo ""
        echo "Add these to .zilch.config:"
        echo "  github_owner=your-username"
        echo "  github_repo=your-repo"
        echo ""
        exit 1
    fi
fi

# 6. Automate State Bucket Isolation (The Bootstrap)
STATE_BUCKET="${PROJECT_ID}-zilch-tfstate"
echo ""
echo "📦 Setting up remote state bucket..."

# Always attempt to create the bucket (idempotent: succeeds if exists, fails only on real errors)
BUCKET_CREATED=false
if gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --project="$PROJECT_ID" \
    --location="$GCP_REGION" \
    --uniform-bucket-level-access \
    &>/dev/null 2>&1; then
    echo "🛠️ Created new state bucket: gs://${STATE_BUCKET}"
    BUCKET_CREATED=true
else
    # Verify bucket actually exists before proceeding
    if gcloud storage buckets describe "gs://${STATE_BUCKET}" &>/dev/null 2>&1; then
        echo "✓ Using existing state bucket: gs://${STATE_BUCKET}"
    else
        echo "❌ Failed to create or access state bucket 'gs://${STATE_BUCKET}'."
        echo ""
        echo "Possible issues:"
        echo "  • Missing Cloud Storage permissions (you need Editor or Owner role)"
        echo "  • Bucket name already taken (try a different project ID)"
        echo "  • Organization policy restricting Cloud Storage"
        echo ""
        echo "Run this to verify permissions:"
        echo "  gcloud projects get-iam-policy ${PROJECT_ID} --flatten='bindings[].members' --filter='bindings.members:user:*'"
        exit 1
    fi
fi

# Wait and verify bucket is accessible (handle eventual consistency)
if [ "$BUCKET_CREATED" = true ]; then
    echo "⏳ Waiting for bucket to be globally available..."
    RETRY_COUNT=0
    MAX_RETRIES=15
    BUCKET_READY=false

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        # Test 1: Can we list objects?
        if gcloud storage ls "gs://${STATE_BUCKET}/" &>/dev/null 2>&1; then
            # Test 2: Can we write a test file?
            if echo "test" | gcloud storage cp - "gs://${STATE_BUCKET}/test-write" &>/dev/null 2>&1; then
                # Test 3: Can we delete it?
                if gcloud storage rm "gs://${STATE_BUCKET}/test-write" &>/dev/null 2>&1; then
                    echo "✓ Bucket is accessible and writable"
                    BUCKET_READY=true
                    break
                fi
            fi
        fi
        RETRY_COUNT=$((RETRY_COUNT+1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "  Attempt $RETRY_COUNT/$MAX_RETRIES... waiting"
            sleep 1
        fi
    done

    if [ "$BUCKET_READY" = false ]; then
        echo "❌ Bucket was created but is not accessible or writable after $MAX_RETRIES seconds."
        echo ""
        echo "Debugging:"
        echo "  1. Check bucket exists: gcloud storage buckets describe gs://${STATE_BUCKET}"
        echo "  2. Check your permissions: gcloud projects get-iam-policy ${PROJECT_ID} --flatten='bindings[].members' --filter='bindings.members:user:*'"
        echo "  3. Check for org policies: gcloud resource-manager org-policies list --project=${PROJECT_ID}"
        exit 1
    fi
fi

# 7. Final pre-flight check before Terraform
echo ""
echo "🔐 Final verification before Terraform..."
TERRAFORM_TEST=$(gcloud storage ls "gs://${STATE_BUCKET}/" 2>&1)
if [ $? -ne 0 ]; then
    echo "❌ Cannot access state bucket at this moment."
    echo "Error: $TERRAFORM_TEST"
    echo ""
    echo "This may be:"
    echo "  • Organization policy blocking Cloud Storage access"
    echo "  • VPC-SC restrictions"
    echo "  • Project-level Cloud Storage API disabled"
    echo ""
    echo "Try manually verifying bucket access:"
    echo "  gcloud storage buckets describe gs://${STATE_BUCKET}"
    exit 1
fi
echo "✓ State bucket verified"

# Set gcloud context to the correct project (required for Terraform ADC)
echo ""
echo "🔧 Configuring gcloud context for Terraform..."
if ! gcloud config set project "$PROJECT_ID" --quiet; then
    echo "⚠️  Warning: Could not set gcloud project context."
fi

# 5. Check if Cloud Build is enabled and validate GitHub connection
if [ "$ENABLE_CLOUD_BUILD" == "true" ]; then
    echo ""
    echo "☁️ Phase 2: Cloud Build + GitOps Setup"
    echo ""

    # Check if GitHub is already connected
    TRIGGER_EXISTS=$(gcloud builds triggers list --project="$PROJECT_ID" --filter="name:${APP_NAME}-trigger" --format="value(id)" 2>/dev/null | head -1)

    if [ -z "$TRIGGER_EXISTS" ]; then
        echo "⚠️  GitHub integration requires manual setup (GCP OAuth limitation)."
        echo ""
        echo "NEXT STEP: Click the link below to connect your GitHub repository:"
        echo "👉 https://console.cloud.google.com/cloud-build/repositories?project=${PROJECT_ID}"
        echo ""
        echo "Instructions:"
        echo "  1. Click 'Connect Repository'"
        echo "  2. Select your GitHub account"
        echo "  3. Select repository: ${GITHUB_OWNER}/${GITHUB_REPO}"
        echo "  4. Click 'Connect' and authorize the Cloud Build GitHub App"
        echo "  5. Return here and press ENTER to continue"
        echo ""
        read -p "Press ENTER once you've connected your GitHub repository..."

        # Verify connection was successful
        TRIGGER_EXISTS=$(gcloud builds triggers list --project="$PROJECT_ID" --filter="name:${APP_NAME}-trigger" --format="value(id)" 2>/dev/null | head -1)
        if [ -z "$TRIGGER_EXISTS" ]; then
            echo "⚠️  GitHub connection not detected yet. Continuing anyway..."
            echo "The trigger will be created by Terraform. Manual GitHub link:"
            echo "   https://console.cloud.google.com/cloud-build/repositories?project=${PROJECT_ID}"
        fi
    else
        echo "✓ GitHub repository already connected"
    fi
fi

# Also set ADC quota project to match (handles Application Default Credentials mismatch)
if ! gcloud auth application-default set-quota-project "$PROJECT_ID" --quiet 2>/dev/null; then
    # Not critical if this fails - some ADC setups don't have quota projects
    true
fi

# Wait for Terraform-specific global replication
if [ "$BUCKET_CREATED" = true ]; then
    echo "⏳ Waiting for Terraform backend propagation (3 seconds)..."
    sleep 3
fi

# 8. Terraform Execution Execution Lifecycle
echo ""
echo "🚀 Initializing Terraform modules over secure remote state..."

# Retry terraform init up to 3 times (handles eventual consistency)
TF_INIT_SUCCESS=false
TF_INIT_RETRIES=0
TF_MAX_RETRIES=3

while [ $TF_INIT_RETRIES -lt $TF_MAX_RETRIES ]; do
    if terraform init \
        -backend-config="bucket=${STATE_BUCKET}" \
        -backend-config="prefix=terraform/state" \
        -reconfigure 2>&1; then
        TF_INIT_SUCCESS=true
        break
    fi
    TF_INIT_RETRIES=$((TF_INIT_RETRIES+1))
    if [ $TF_INIT_RETRIES -lt $TF_MAX_RETRIES ]; then
        echo "⚠️  Terraform init failed. Retrying ($TF_INIT_RETRIES/$TF_MAX_RETRIES)..."
        sleep 2
    fi
done

if [ "$TF_INIT_SUCCESS" = false ]; then
    echo "❌ Terraform init failed after $TF_MAX_RETRIES attempts."
    echo ""
    echo "The state bucket exists and is accessible, but Terraform init still failed."
    echo "This usually means:"
    echo "  • Terraform files have syntax errors (run: terraform validate)"
    echo "  • Missing or incompatible provider versions"
    echo "  • Backend configuration issue"
    echo ""
    echo "For debugging:"
    echo "  1. Run: terraform validate"
    echo "  2. Check for Terraform syntax errors in *.tf files"
    echo "  3. Try: terraform init -upgrade"
    exit 1
fi

echo "🏗️ Applying architectural blueprint definitions to Google Cloud..."
if ! terraform apply -auto-approve \
  -var="gcp_project_id=${PROJECT_ID}" \
  -var="app_name=${APP_NAME}" \
  -var="gcp_region=${GCP_REGION}" \
  -var="github_owner=${GITHUB_OWNER}" \
  -var="github_repo=${GITHUB_REPO}" \
  -var="enable_cloud_build=${ENABLE_CLOUD_BUILD}" \
  -var="enable_firestore=${ENABLE_FIRESTORE}" \
  -var="enable_secret_manager=${ENABLE_SECRET_MANAGER}" \
  -var="enable_cloud_storage=${ENABLE_CLOUD_STORAGE}" \
  -var="enable_firebase_auth=${ENABLE_FIREBASE_AUTH}" \
  -var="enable_vertex_ai=${ENABLE_VERTEX_AI}"; then
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
echo "🌐 Operational Region:   ${GCP_REGION}"
echo ""
echo "📋 Available Runtime Application Discovery Environment Tunnels:"
if [ "$ENABLE_FIRESTORE" == "true" ]; then echo "  ↳ ZILCH_FIRESTORE_DATABASE : (default)"; fi
if [ "$ENABLE_SECRET_MANAGER" == "true" ]; then echo "  ↳ ZILCH_SECRET_PREFIX      : ${APP_NAME}-"; fi
if [ "$ENABLE_CLOUD_STORAGE" == "true" ]; then echo "  ↳ ZILCH_STORAGE_BUCKET     : $(terraform output -raw storage_bucket 2>/dev/null)"; fi
if [ "$ENABLE_VERTEX_AI" == "true" ]; then echo "  ↳ ZILCH_VERTEX_AI_ENABLED  : true"; fi
if [ "$ENABLE_FIREBASE_AUTH" == "true" ]; then echo "  ↳ ZILCH_FIREBASE_ENABLED   : true"; fi
echo ""
echo "💡 Reminder: Your setup operates completely on Google's Free tier limits."
echo "   Track parameters safely via: https://cloud.google.com/always-free"
echo ""
echo "📚 Next Steps:"
echo "   1. Deploy your code: gcloud run deploy ${APP_NAME} --source ."
echo "   2. View logs: gcloud run logs read ${APP_NAME} --region=${GCP_REGION}"
if [ "$ENABLE_FIREBASE_AUTH" == "true" ]; then
    echo "   3. Configure auth: https://console.firebase.google.com/project/${PROJECT_ID}/authentication"
fi
echo "================================================================="
