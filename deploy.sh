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
echo ""
echo "📦 Setting up remote state bucket..."

# Always attempt to create the bucket (idempotent: succeeds if exists, fails only on real errors)
BUCKET_CREATED=false
if gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
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

# Wait for Terraform-specific global replication
if [ "$BUCKET_CREATED" = true ]; then
    echo ""
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
