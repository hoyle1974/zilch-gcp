#!/bin/bash
set -e

clear
echo "=========================================="
echo "  Zilch GCP Infrastructure Deployment"
echo "=========================================="
echo ""

echo "Checking prerequisites..."
echo ""

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q '@'; then
    echo "Error: No active gcloud authentication."
    echo ""
    echo "Log in first:"
    echo "  gcloud auth login"
    echo ""
    echo "Then run deploy.sh again."
    exit 1
fi

CURRENT_USER=$(gcloud config get-value account)
echo "Authenticated as: ${CURRENT_USER}"

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
    echo "Loading .zilch.config..."

    # Parse config file safely without executing code. Whitelist variables to prevent injection.

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

    echo "Configuration loaded"
fi

DEFAULT_PROJECT="${PROJECT_ID:-}"
if [ -z "$DEFAULT_PROJECT" ]; then
    read -p "GCP Project ID: " PROJECT_ID
else
    read -p "GCP Project ID [$DEFAULT_PROJECT]: " INPUT
    PROJECT_ID="${INPUT:-$DEFAULT_PROJECT}"
fi
if [ -z "$PROJECT_ID" ]; then
    echo "Error: Project ID cannot be empty."
    exit 1
fi

if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    echo "Error: Project '$PROJECT_ID' not found or no access."
    exit 1
fi

echo "Checking IAM permissions..."
ROLE_CHECK=$(gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:${CURRENT_USER} AND (bindings.role:roles/editor OR bindings.role:roles/owner)" \
  --format="value(bindings.role)" 2>/dev/null | head -1)

if [ -z "$ROLE_CHECK" ]; then
    echo "Error: Need Editor or Owner role on ${PROJECT_ID}."
    echo ""
    echo "Ask your admin to run:"
    echo "  gcloud projects add-iam-policy-binding ${PROJECT_ID} \\"
    echo "    --member=user:${CURRENT_USER} \\"
    echo "    --role=roles/editor"
    exit 1
fi

if [ "$ENABLE_FIRESTORE" = "true" ]; then
    FIRESTORE_ROLE=$(gcloud projects get-iam-policy "$PROJECT_ID" \
      --flatten="bindings[].members" \
      --filter="bindings.members:user:${CURRENT_USER} AND bindings.role:roles/datastore.admin" \
      --format="value(bindings.role)" 2>/dev/null | head -1)

    if [ -z "$FIRESTORE_ROLE" ]; then
        echo "Warning: You may not have Firestore Admin role. If creation fails, ask your admin:"
        echo "  gcloud projects add-iam-policy-binding ${PROJECT_ID} \\"
        echo "    --member=user:${CURRENT_USER} \\"
        echo "    --role=roles/datastore.admin"
        echo ""
    fi
fi
echo ""
echo ""
echo "App Name:"
DEFAULT_APP_NAME="${APP_NAME:-zilch-app}"
read -p "  [$DEFAULT_APP_NAME]: " INPUT_APP_NAME
APP_NAME="${INPUT_APP_NAME:-$DEFAULT_APP_NAME}"

if [[ ! "$APP_NAME" =~ ^[a-z0-9-]{3,30}$ ]]; then
    echo "Error: App name must be 3-30 lowercase characters, numbers, or hyphens."
    exit 1
fi

echo ""
echo "Region (Always Free Eligible):"
echo "  [1] us-central1 (Iowa - Preferred Default)"
echo "  [2] us-east1    (South Carolina)"
echo "  [3] us-west1    (Oregon)"

# Show current region as default
REGION_DEFAULT="1"
[ "$GCP_REGION" = "us-east1" ] && REGION_DEFAULT="2"
[ "$GCP_REGION" = "us-west1" ] && REGION_DEFAULT="3"

read -p "  [1-3, default: $REGION_DEFAULT]: " REGION_CHOICE
REGION_CHOICE="${REGION_CHOICE:-$REGION_DEFAULT}"

case "$REGION_CHOICE" in
    2) GCP_REGION="us-east1" ;;
    3) GCP_REGION="us-west1" ;;
    *) GCP_REGION="us-central1" ;;
esac

prompt_toggle() {
    local feature_name=$1
    local current_value=$2
    local default_response="n"
    if [ "$current_value" = "true" ]; then
        default_response="y"
    fi
    read -p "  $feature_name? (y/n) [default: $default_response]: " choice
    choice="${choice:-$default_response}"
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo "true"
    else
        echo "false"
    fi
}

echo ""
echo "Services:"
ENABLE_FIRESTORE=$(prompt_toggle "Firestore" "$ENABLE_FIRESTORE")
ENABLE_SECRET_MANAGER=$(prompt_toggle "Secret Manager" "$ENABLE_SECRET_MANAGER")
ENABLE_CLOUD_STORAGE=$(prompt_toggle "Cloud Storage" "$ENABLE_CLOUD_STORAGE")
ENABLE_CLOUD_BUILD=$(prompt_toggle "Cloud Build" "$ENABLE_CLOUD_BUILD")
ENABLE_FIREBASE_AUTH=$(prompt_toggle "Firebase Auth" "$ENABLE_FIREBASE_AUTH")
ENABLE_VERTEX_AI=$(prompt_toggle "Vertex AI" "$ENABLE_VERTEX_AI")
ENABLE_PUBSUB=$(prompt_toggle "Pub/Sub" "$ENABLE_PUBSUB")
ENABLE_CLOUD_TASKS=$(prompt_toggle "Cloud Tasks" "$ENABLE_CLOUD_TASKS")
ENABLE_BIGQUERY=$(prompt_toggle "BigQuery" "$ENABLE_BIGQUERY")
ENABLE_CLOUD_KMS=$(prompt_toggle "Cloud KMS" "$ENABLE_CLOUD_KMS")
ENABLE_VISION_AI=$(prompt_toggle "Vision AI" "$ENABLE_VISION_AI")
ENABLE_SPEECH_TO_TEXT=$(prompt_toggle "Speech-to-Text" "$ENABLE_SPEECH_TO_TEXT")
ENABLE_TRANSLATION=$(prompt_toggle "Translation" "$ENABLE_TRANSLATION")
ENABLE_SCHEDULER=$(prompt_toggle "Cloud Scheduler" "$ENABLE_SCHEDULER")

if [ "$ENABLE_SCHEDULER" == "true" ]; then
    echo ""
    echo "Scheduler settings:"
    read -p "  Cron expression [$SCHEDULER_SCHEDULE]: " INPUT
    SCHEDULER_SCHEDULE="${INPUT:-$SCHEDULER_SCHEDULE}"
    read -p "  Endpoint path [$SCHEDULER_ENDPOINT]: " INPUT
    SCHEDULER_ENDPOINT="${INPUT:-$SCHEDULER_ENDPOINT}"
fi

echo ""
echo "Configuration:"
ALLOW_UNAUTHENTICATED_ACCESS=$(prompt_toggle "Allow unauthenticated access" "$ALLOW_UNAUTHENTICATED_ACCESS")
ENABLE_MONITORING=$(prompt_toggle "Cloud Monitoring (with budget alerts)" "$ENABLE_MONITORING")

if [ "$ENABLE_MONITORING" == "true" ]; then
    read -p "👉 Monthly budget limit in USD [$BILLING_BUDGET_LIMIT_USD]: " INPUT
    BILLING_BUDGET_LIMIT_USD="${INPUT:-$BILLING_BUDGET_LIMIT_USD}"

    echo ""
    echo "📋 GCP Billing Accounts:"
    BILLING_LIST_OUTPUT=$(gcloud beta billing accounts list --format="csv[no-heading](name,displayName,masterBillingAccount)" 2>&1)
    BILLING_LIST_EXIT=$?

    if [ $BILLING_LIST_EXIT -eq 0 ] && [ -n "$BILLING_LIST_OUTPUT" ]; then
        declare -a BILLING_IDS
        declare -a BILLING_NAMES
        index=1

        while IFS=',' read -r account_id display_name master_account; do
            account_id=$(echo "$account_id" | sed 's/"//g')
            display_name=$(echo "$display_name" | sed 's/"//g')
            master_account=$(echo "$master_account" | sed 's/"//g')

            BILLING_IDS[$index]="$account_id"
            BILLING_NAMES[$index]="$display_name"

            if [ -n "$master_account" ] && [ "$master_account" != "False" ]; then
                printf "  [%d] %s (subaccount, %s)\n" "$index" "$display_name" "$account_id"
            else
                printf "  [%d] %s (%s)\n" "$index" "$display_name" "$account_id"
            fi
            index=$((index + 1))
        done <<< "$BILLING_LIST_OUTPUT"

        echo ""
        read -p "  Select [1-$((index - 1)), or skip]: " CHOICE
        if [ -n "$CHOICE" ] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -lt "$index" ]; then
            GCP_BILLING_ACCOUNT_ID="${BILLING_IDS[$CHOICE]}"
            BILLING_ACCOUNT_NAME="${BILLING_NAMES[$CHOICE]}"
        fi
    else
        echo "Could not list billing accounts (requires org-level 'Billing Account User' role)."
        echo ""
        echo "Find your Billing Account ID:"
        echo "  1. GCP Console: https://console.cloud.google.com/billing"
        echo "  2. Run: gcloud beta billing accounts list"
        echo "  3. Ask your Billing Account Admin"
        echo ""
        read -p "  Billing Account ID (or skip): " INPUT
        GCP_BILLING_ACCOUNT_ID="${INPUT:-}"
    fi
fi

# If Cloud Build is enabled, GitHub info is required
if [ "$ENABLE_CLOUD_BUILD" == "true" ]; then
    if [ -z "$GITHUB_OWNER" ] || [ -z "$GITHUB_REPO" ]; then
        echo ""
        echo "Cloud Build requires GitHub repository connection."
        read -p "  GitHub username/org: " GITHUB_OWNER
        read -p "  GitHub repository name: " GITHUB_REPO

        if [ -z "$GITHUB_OWNER" ] || [ -z "$GITHUB_REPO" ]; then
            echo "Error: GitHub credentials are required for Cloud Build."
            exit 1
        fi
    fi
fi

echo ""
echo "Saving configuration..."
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
echo "Configuration saved"

STATE_BUCKET="${PROJECT_ID}-zilch-tfstate"
echo ""
echo "Setting up state bucket..."

# Always attempt to create the bucket (idempotent: succeeds if exists, fails only on real errors)
BUCKET_CREATED=false
if gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --project="$PROJECT_ID" \
    --location="$GCP_REGION" \
    --uniform-bucket-level-access \
    &>/dev/null 2>&1; then
    echo "Created: gs://${STATE_BUCKET}"
    BUCKET_CREATED=true
else
    if gcloud storage buckets describe "gs://${STATE_BUCKET}" &>/dev/null 2>&1; then
        echo "Using existing: gs://${STATE_BUCKET}"
    else
        echo "Error: Failed to create or access bucket 'gs://${STATE_BUCKET}'."
        exit 1
    fi
fi

if [ "$BUCKET_CREATED" = true ]; then
    echo "Waiting for bucket propagation..."
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
            echo "  Attempt $RETRY_COUNT/$MAX_RETRIES..."
            sleep 1
        fi
    done

    if [ "$BUCKET_READY" = false ]; then
        echo "Error: Bucket not accessible after $MAX_RETRIES attempts."
        exit 1
    fi
fi

echo ""
echo "Verifying bucket..."
if ! gcloud storage buckets describe "gs://${STATE_BUCKET}" &>/dev/null 2>&1; then
    echo "Error: Cannot access state bucket."
    exit 1
fi

echo ""
if ! gcloud config set project "$PROJECT_ID" --quiet; then
    echo "Warning: Could not set gcloud project context."
fi

if [ "$ENABLE_CLOUD_BUILD" == "true" ]; then
    echo ""
    TRIGGER_EXISTS=$(gcloud builds triggers list --project="$PROJECT_ID" --filter="name:${APP_NAME}-trigger" --format="value(id)" 2>/dev/null | head -1)

    if [ -z "$TRIGGER_EXISTS" ]; then
        echo "Connect GitHub repository (manual OAuth required):"
        echo "  https://console.cloud.google.com/cloud-build/repositories?project=${PROJECT_ID}"
        echo ""
        echo "Steps:"
        echo "  1. Click 'Connect Repository'"
        echo "  2. Select ${GITHUB_OWNER}/${GITHUB_REPO}"
        echo "  3. Authorize the Cloud Build GitHub App"
        echo ""
        read -p "Press ENTER once connected (or Terraform will create it)..."
    fi
fi

if [ "$BUCKET_CREATED" = true ]; then
    sleep 3
fi

echo ""
echo "Terraform init..."
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
        echo "Init failed, retrying ($TF_INIT_RETRIES/$TF_MAX_RETRIES)..."
        sleep 2
    fi
done

if [ "$TF_INIT_SUCCESS" = false ]; then
    echo "Error: Terraform init failed after $TF_MAX_RETRIES attempts."
    exit 1
fi

if [ "$ENABLE_MONITORING" = "true" ] && [ -n "$GCP_BILLING_ACCOUNT_ID" ]; then
    echo "Setting ADC quota project for billing..."
    gcloud auth application-default set-quota-project "$PROJECT_ID" --quiet 2>/dev/null || true
fi

echo "Applying Terraform..."
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
