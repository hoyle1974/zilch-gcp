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
ENABLE_PUBSUB="false"
ENABLE_CLOUD_TASKS="false"
ENABLE_BIGQUERY="false"
ENABLE_CLOUD_KMS="false"
ENABLE_VISION_AI="false"
ENABLE_SPEECH_TO_TEXT="false"
ENABLE_TRANSLATION="false"
ENABLE_SCHEDULER="false"
ENABLE_MONITORING="false"
SCHEDULER_SCHEDULE="0 0 * * *"
SCHEDULER_TIMEZONE="UTC"
SCHEDULER_ENDPOINT="/api/cron"
BILLING_ACCOUNT_NAME="My Billing Account"
BILLING_BUDGET_LIMIT_USD="10"
ALLOW_UNAUTHENTICATED_ACCESS="true"
GCP_BILLING_ACCOUNT_ID=""
GITHUB_OWNER=""
GITHUB_REPO=""

# Load from .zilch.config if it exists (uses lowercase variable names)
if [ -f ".zilch.config" ]; then
    echo "📋 Reading .zilch.config..."

    # SECURITY: Parse config file safely without executing code.
    # Instead of 'source .zilch.config' which executes arbitrary bash,
    # use a while loop to read key=value pairs and only set whitelisted variables.
    # This prevents injection attacks if the config file is compromised.

    while IFS='=' read -r key value; do
        # Skip comments and blank lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Trim leading/trailing whitespace from key and value
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Only set known, safe variables from the config file
        case "$key" in
            gcp_project_id) PROJECT_ID="$value" ;;
            app_name) APP_NAME="$value" ;;
            gcp_region) GCP_REGION="$value" ;;
            enable_firestore) ENABLE_FIRESTORE="$value" ;;
            enable_secret_manager) ENABLE_SECRET_MANAGER="$value" ;;
            enable_cloud_storage) ENABLE_CLOUD_STORAGE="$value" ;;
            enable_firebase_auth) ENABLE_FIREBASE_AUTH="$value" ;;
            enable_vertex_ai) ENABLE_VERTEX_AI="$value" ;;
            enable_cloud_build) ENABLE_CLOUD_BUILD="$value" ;;
            enable_pubsub) ENABLE_PUBSUB="$value" ;;
            enable_cloud_tasks) ENABLE_CLOUD_TASKS="$value" ;;
            enable_bigquery) ENABLE_BIGQUERY="$value" ;;
            enable_cloud_kms) ENABLE_CLOUD_KMS="$value" ;;
            enable_vision_ai) ENABLE_VISION_AI="$value" ;;
            enable_speech_to_text) ENABLE_SPEECH_TO_TEXT="$value" ;;
            enable_translation) ENABLE_TRANSLATION="$value" ;;
            enable_scheduler) ENABLE_SCHEDULER="$value" ;;
            enable_monitoring) ENABLE_MONITORING="$value" ;;
            allow_unauthenticated_access) ALLOW_UNAUTHENTICATED_ACCESS="$value" ;;
            scheduler_schedule) SCHEDULER_SCHEDULE="$value" ;;
            scheduler_timezone) SCHEDULER_TIMEZONE="$value" ;;
            scheduler_endpoint) SCHEDULER_ENDPOINT="$value" ;;
            billing_account_name) BILLING_ACCOUNT_NAME="$value" ;;
            billing_budget_limit_usd) BILLING_BUDGET_LIMIT_USD="$value" ;;
            gcp_billing_account_id) GCP_BILLING_ACCOUNT_ID="$value" ;;
            github_owner) GITHUB_OWNER="$value" ;;
            github_repo) GITHUB_REPO="$value" ;;
            *) : ;; # Silently ignore unknown keys (future-proof)
        esac
    done < .zilch.config

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

# Phase 3: Advanced Services
echo ""
ENABLE_PUBSUB=$(prompt_toggle "Pub/Sub Event Streaming" "$ENABLE_PUBSUB")
ENABLE_CLOUD_TASKS=$(prompt_toggle "Cloud Tasks Job Queues" "$ENABLE_CLOUD_TASKS")
ENABLE_BIGQUERY=$(prompt_toggle "BigQuery Analytics Engine" "$ENABLE_BIGQUERY")
ENABLE_CLOUD_KMS=$(prompt_toggle "Cloud KMS Encryption Keys" "$ENABLE_CLOUD_KMS")
ENABLE_VISION_AI=$(prompt_toggle "Vision AI Image Processing" "$ENABLE_VISION_AI")
ENABLE_SPEECH_TO_TEXT=$(prompt_toggle "Speech-to-Text Audio Transcription" "$ENABLE_SPEECH_TO_TEXT")
ENABLE_TRANSLATION=$(prompt_toggle "Translation API Multi-Language" "$ENABLE_TRANSLATION")

# Phase 4: Cloud Scheduler & Monitoring
echo ""
ENABLE_SCHEDULER=$(prompt_toggle "Cloud Scheduler (serverless cron jobs)" "$ENABLE_SCHEDULER")

if [ "$ENABLE_SCHEDULER" == "true" ]; then
    read -p "👉 Cloud Scheduler cron expression [$SCHEDULER_SCHEDULE]: " INPUT
    SCHEDULER_SCHEDULE="${INPUT:-$SCHEDULER_SCHEDULE}"

    read -p "👉 Scheduler endpoint path [$SCHEDULER_ENDPOINT]: " INPUT
    SCHEDULER_ENDPOINT="${INPUT:-$SCHEDULER_ENDPOINT}"
fi

# Cloud Run access control
echo ""
ALLOW_UNAUTHENTICATED_ACCESS=$(prompt_toggle "Allow unauthenticated access to Cloud Run service" "$ALLOW_UNAUTHENTICATED_ACCESS")

ENABLE_MONITORING=$(prompt_toggle "Cloud Monitoring with Budget Alerts (emergency circuit breaker)" "$ENABLE_MONITORING")

if [ "$ENABLE_MONITORING" == "true" ]; then
    read -p "👉 Monthly budget limit in USD [$BILLING_BUDGET_LIMIT_USD]: " INPUT
    BILLING_BUDGET_LIMIT_USD="${INPUT:-$BILLING_BUDGET_LIMIT_USD}"

    echo ""
    echo "📋 GCP Billing Accounts:"
    BILLING_LIST_OUTPUT=$(gcloud beta billing accounts list --format="csv[no-heading](name,displayName)" 2>&1)
    BILLING_LIST_EXIT=$?

    if [ $BILLING_LIST_EXIT -eq 0 ] && [ -n "$BILLING_LIST_OUTPUT" ]; then
        # Interactive menu for billing account selection
        declare -a BILLING_IDS
        declare -a BILLING_NAMES
        local index=1

        while IFS=',' read -r account_id display_name; do
            # Clean up quotes from CSV
            account_id=$(echo "$account_id" | sed 's/"//g')
            display_name=$(echo "$display_name" | sed 's/"//g')

            BILLING_IDS[$index]="$account_id"
            BILLING_NAMES[$index]="$display_name"
            printf "  [%d] %s (%s)\n" "$index" "$display_name" "$account_id"
            index=$((index + 1))
        done <<< "$BILLING_LIST_OUTPUT"

        echo ""
        read -p "👉 Select billing account [1-$((index - 1)), or leave blank to skip]: " CHOICE
        if [ -n "$CHOICE" ] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -lt "$index" ]; then
            GCP_BILLING_ACCOUNT_ID="${BILLING_IDS[$CHOICE]}"
            BILLING_ACCOUNT_NAME="${BILLING_NAMES[$CHOICE]}"
        fi
    else
        echo "⚠️  Could not list billing accounts (requires organization-level 'Billing Account User' role)."
        echo ""
        echo "To find your Billing Account ID, choose one of:"
        echo ""
        echo "  Option 1: GCP Console"
        echo "    • Visit: https://console.cloud.google.com/billing"
        echo "    • Click 'Manage billing accounts'"
        echo "    • Select your account and copy the Account ID"
        echo "    • Format: billingAccounts/012345-678901-234567"
        echo ""
        echo "  Option 2: If you have org-level access"
        echo "    • Run: gcloud beta billing accounts list"
        echo ""
        echo "  Option 3: Ask your Billing Account Admin to provide the ID"
        echo ""
        read -p "👉 Enter GCP Billing Account ID (or leave blank to skip): " INPUT
        GCP_BILLING_ACCOUNT_ID="${INPUT:-}"
    fi
fi

# If Cloud Build is enabled, GitHub info is required
if [ "$ENABLE_CLOUD_BUILD" == "true" ]; then
    if [ -z "$GITHUB_OWNER" ] || [ -z "$GITHUB_REPO" ]; then
        echo ""
        echo "⚙️  Cloud Build requires GitHub repository connection."
        read -p "👉 Enter your GitHub username/org: " GITHUB_OWNER
        read -p "👉 Enter your GitHub repository name: " GITHUB_REPO

        if [ -z "$GITHUB_OWNER" ] || [ -z "$GITHUB_REPO" ]; then
            echo "❌ Error: GitHub credentials are required for Cloud Build."
            exit 1
        fi
    fi
fi

# Early Config Save: Persist user input before Terraform runs
# This allows easy recovery if Terraform fails - just re-run with same settings
echo ""
echo "💾 Saving configuration for quick recovery..."
cat > .zilch.config << CONFIGEOF
# Zilch Reference App Configuration
# This app demonstrates all Zilch Phase 1 + Phase 2 + Phase 3 + Phase 4 services
# Last updated: $(date)

# GitHub Integration (required for Cloud Build)
github_owner=${GITHUB_OWNER}
github_repo=${GITHUB_REPO}

# GCP Settings
gcp_project_id=${PROJECT_ID}
app_name=${APP_NAME}
gcp_region=${GCP_REGION}

# Phase 1 Optional Features
enable_firestore=${ENABLE_FIRESTORE}
enable_secret_manager=${ENABLE_SECRET_MANAGER}
enable_cloud_storage=${ENABLE_CLOUD_STORAGE}
enable_firebase_auth=${ENABLE_FIREBASE_AUTH}
enable_vertex_ai=${ENABLE_VERTEX_AI}

# Phase 2: Cloud Build + GitOps (optional)
enable_cloud_build=${ENABLE_CLOUD_BUILD}

# Phase 3: Advanced Services (optional)
enable_pubsub=${ENABLE_PUBSUB}
enable_cloud_tasks=${ENABLE_CLOUD_TASKS}
enable_bigquery=${ENABLE_BIGQUERY}
enable_cloud_kms=${ENABLE_CLOUD_KMS}
enable_vision_ai=${ENABLE_VISION_AI}
enable_speech_to_text=${ENABLE_SPEECH_TO_TEXT}
enable_translation=${ENABLE_TRANSLATION}

# Phase 4: Cloud Scheduler & Monitoring (optional)
enable_scheduler=${ENABLE_SCHEDULER}
scheduler_schedule="${SCHEDULER_SCHEDULE}"
scheduler_timezone="${SCHEDULER_TIMEZONE}"
scheduler_endpoint="${SCHEDULER_ENDPOINT}"
enable_monitoring=${ENABLE_MONITORING}
billing_account_name="${BILLING_ACCOUNT_NAME}"
billing_budget_limit_usd=${BILLING_BUDGET_LIMIT_USD}

# Cloud Run Access Control & Billing
allow_unauthenticated_access=${ALLOW_UNAUTHENTICATED_ACCESS}
gcp_billing_account_id="${GCP_BILLING_ACCOUNT_ID}"
CONFIGEOF
echo "✓ Configuration saved to .zilch.config"

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
if ! gcloud storage buckets describe "gs://${STATE_BUCKET}" &>/dev/null 2>&1; then
    echo "❌ Cannot access state bucket at this moment."
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
    if terraform -chdir="$(dirname "$0")" init \
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
if ! terraform -chdir="$(dirname "$0")" apply -auto-approve \
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
  -var="enable_vertex_ai=${ENABLE_VERTEX_AI}" \
  -var="enable_pubsub=${ENABLE_PUBSUB}" \
  -var="enable_cloud_tasks=${ENABLE_CLOUD_TASKS}" \
  -var="enable_bigquery=${ENABLE_BIGQUERY}" \
  -var="enable_cloud_kms=${ENABLE_CLOUD_KMS}" \
  -var="enable_vision_ai=${ENABLE_VISION_AI}" \
  -var="enable_speech_to_text=${ENABLE_SPEECH_TO_TEXT}" \
  -var="enable_translation=${ENABLE_TRANSLATION}" \
  -var="enable_scheduler=${ENABLE_SCHEDULER}" \
  -var="scheduler_schedule=${SCHEDULER_SCHEDULE}" \
  -var="scheduler_timezone=${SCHEDULER_TIMEZONE}" \
  -var="scheduler_endpoint=${SCHEDULER_ENDPOINT}" \
  -var="enable_monitoring=${ENABLE_MONITORING}" \
  -var="billing_account_name=${BILLING_ACCOUNT_NAME}" \
  -var="billing_budget_limit_usd=${BILLING_BUDGET_LIMIT_USD}" \
  -var="allow_unauthenticated_access=${ALLOW_UNAUTHENTICATED_ACCESS}" \
  -var="gcp_billing_account_id=${GCP_BILLING_ACCOUNT_ID}"; then
    echo "❌ Terraform apply failed. Check the error above."
    echo "   Most common: insufficient permissions for required services."
    exit 1
fi

# 8. Post-Deployment Endpoint Performance Validation Checks
RUN_URL=$(terraform -chdir="$(dirname "$0")" output -raw cloud_run_url)
echo ""
echo "🔍 Initiating app endpoint connection checks at: ${RUN_URL}"

RETRY_COUNT=0
MAX_RETRIES=3
HEALTHY=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$RUN_URL" || echo "000")
    # Accept 2xx success, 401 unauthorized, 404 not found as healthy
    # (proves container is running; reject 5xx errors and timeouts which indicate crashes)
    if [[ "$HTTP_STATUS" =~ ^2[0-9][0-9]$ ]] || [ "$HTTP_STATUS" == "401" ] || [ "$HTTP_STATUS" == "404" ]; then
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

# Config already saved early (before Terraform) for quick recovery on failure

# 9. Format Summary Diagnostics Output
echo ""
echo "================================================================="
echo " 🎉 SUCCESS: Zilch Architecture Instantiated Successfully! "
echo "================================================================="
echo "📍 Service Endpoint URL: ${RUN_URL}"
echo "👤 Bound Run Identity:   $(terraform -chdir="$(dirname "$0")" output -raw service_account_email)"
echo "🌐 Operational Region:   ${GCP_REGION}"
echo ""
echo "📋 Available Runtime Application Discovery Environment Tunnels:"
if [ "$ENABLE_FIRESTORE" == "true" ]; then echo "  ↳ ZILCH_FIRESTORE_DATABASE : (default)"; fi
if [ "$ENABLE_SECRET_MANAGER" == "true" ]; then echo "  ↳ ZILCH_SECRET_PREFIX      : ${APP_NAME}-"; fi
if [ "$ENABLE_CLOUD_STORAGE" == "true" ]; then echo "  ↳ ZILCH_STORAGE_BUCKET     : $(terraform -chdir="$(dirname "$0")" output -raw storage_bucket 2>/dev/null)"; fi
if [ "$ENABLE_VERTEX_AI" == "true" ]; then echo "  ↳ ZILCH_VERTEX_AI_ENABLED  : true"; fi
if [ "$ENABLE_FIREBASE_AUTH" == "true" ]; then echo "  ↳ ZILCH_FIREBASE_ENABLED   : true"; fi
if [ "$ENABLE_PUBSUB" == "true" ]; then echo "  ↳ ZILCH_PUBSUB_TOPIC       : ${APP_NAME}-events"; fi
if [ "$ENABLE_PUBSUB" == "true" ]; then echo "  ↳ ZILCH_PUBSUB_SUBSCRIPTION: ${APP_NAME}-events-subscription"; fi
if [ "$ENABLE_CLOUD_TASKS" == "true" ]; then echo "  ↳ ZILCH_CLOUD_TASKS_QUEUE  : projects/${PROJECT_ID}/locations/${GCP_REGION}/queues/${APP_NAME}-jobs"; fi
if [ "$ENABLE_BIGQUERY" == "true" ]; then echo "  ↳ ZILCH_BIGQUERY_DATASET   : $(echo ${APP_NAME} | tr '-' '_')_analytics"; fi
if [ "$ENABLE_CLOUD_KMS" == "true" ]; then echo "  ↳ ZILCH_KMS_KEY_ID         : $(terraform -chdir="$(dirname "$0")" output -raw kms_key_id 2>/dev/null)"; fi
if [ "$ENABLE_VISION_AI" == "true" ]; then echo "  ↳ ZILCH_VISION_AI_ENABLED  : true"; fi
if [ "$ENABLE_SPEECH_TO_TEXT" == "true" ]; then echo "  ↳ ZILCH_SPEECH_TO_TEXT_ENABLED: true"; fi
if [ "$ENABLE_TRANSLATION" == "true" ]; then echo "  ↳ ZILCH_TRANSLATION_ENABLED: true"; fi
if [ "$ENABLE_SCHEDULER" == "true" ]; then echo "  ↳ ZILCH_SCHEDULER_ENABLED  : ${SCHEDULER_SCHEDULE} (${SCHEDULER_TIMEZONE})"; fi
if [ "$ENABLE_MONITORING" == "true" ]; then echo "  ↳ ZILCH_MONITORING_ENABLED : ${BILLING_BUDGET_LIMIT_USD} USD/month alert"; fi
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
