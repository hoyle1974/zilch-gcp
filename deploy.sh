#!/bin/bash
set -e

# Color definitions (ANSI-C quoting for proper interpretation)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# Check for --auto flag to skip all prompts
AUTO_MODE=false
if [ "$1" = "--auto" ]; then
    AUTO_MODE=true
fi

clear
echo -e "${BOLD}${CYAN}Zilch GCP Infrastructure Deployment${NC}"
if [ "$AUTO_MODE" = true ]; then
    echo -e "${BLUE}(auto mode - using defaults)${NC}"
fi
echo ""

echo -e "${BOLD}Prerequisites${NC}"
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q '@'; then
    echo -e "${RED}✗ No active gcloud authentication${NC}"
    echo ""
    echo "  gcloud auth login"
    exit 1
fi

CURRENT_USER=$(gcloud config get-value account)
echo -e "${GREEN}✓${NC} Authenticated as ${CYAN}${CURRENT_USER}${NC}"

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
ENABLE_CLOUD_BUILD="true"
ENABLE_PUBSUB="false"
ENABLE_CLOUD_TASKS="false"
ENABLE_BIGQUERY="false"
ENABLE_CLOUD_KMS="false"
ENABLE_VISION_AI="false"
ENABLE_SPEECH_TO_TEXT="false"
ENABLE_TRANSLATION="false"
ENABLE_SCHEDULER="false"
ENABLE_MONITORING="false"
ALLOW_UNAUTHENTICATED_ACCESS="true"
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
    echo -e "${BLUE}→${NC} Loading ${CYAN}.zilch.config${NC}"

    # Parse config file safely without executing code. Whitelist variables to prevent injection.

    while IFS='=' read -r key value; do
        # Skip comments and blank lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Trim leading/trailing whitespace from key and value
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Remove all surrounding quotes (handle multiple layers from repeated saves)
        while [[ "$value" == \"* ]] && [[ "$value" == *\" ]]; do
            value="${value#\"}"
            value="${value%\"}"
        done

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

    echo -e "${GREEN}✓${NC} Loaded"
fi

DEFAULT_PROJECT="${PROJECT_ID:-}"
if [ "$AUTO_MODE" = false ]; then
    if [ -z "$DEFAULT_PROJECT" ]; then
        read -p "${BLUE}GCP Project ID${NC}: " PROJECT_ID
    else
        read -p "${BLUE}GCP Project ID${NC} ${CYAN}[${DEFAULT_PROJECT}]${NC}: " INPUT
        PROJECT_ID="${INPUT:-$DEFAULT_PROJECT}"
    fi
fi
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}✗ Project ID required${NC}"
    exit 1
fi

if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
    echo -e "${RED}✗ Project ${CYAN}${PROJECT_ID}${RED} not found or no access${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Project ${CYAN}${PROJECT_ID}${NC}"

echo -e "${BOLD}Verification${NC}"
ROLE_CHECK=$(gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten="bindings[].members" \
  --filter="bindings.members:user:${CURRENT_USER} AND (bindings.role:roles/editor OR bindings.role:roles/owner)" \
  --format="value(bindings.role)" 2>/dev/null | head -1)

if [ -z "$ROLE_CHECK" ]; then
    echo -e "${RED}✗ Need Editor or Owner role on ${CYAN}${PROJECT_ID}${NC}"
    echo ""
    echo "Ask your admin:"
    echo -e "  ${CYAN}gcloud projects add-iam-policy-binding ${PROJECT_ID} \\${NC}"
    echo -e "    ${CYAN}--member=user:${CURRENT_USER} \\${NC}"
    echo -e "    ${CYAN}--role=roles/editor${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} IAM permissions OK"

if [ "$ENABLE_FIRESTORE" = "true" ]; then
    FIRESTORE_ROLE=$(gcloud projects get-iam-policy "$PROJECT_ID" \
      --flatten="bindings[].members" \
      --filter="bindings.members:user:${CURRENT_USER} AND bindings.role:roles/datastore.admin" \
      --format="value(bindings.role)" 2>/dev/null | head -1)

    if [ -z "$FIRESTORE_ROLE" ]; then
        echo -e "${YELLOW}⚠${NC} Firestore Admin role may be needed"
        echo "If creation fails, ask your admin:"
        echo -e "  ${CYAN}gcloud projects add-iam-policy-binding ${PROJECT_ID} \\${NC}"
        echo -e "    ${CYAN}--member=user:${CURRENT_USER} \\${NC}"
        echo -e "    ${CYAN}--role=roles/datastore.admin${NC}"
        echo ""
    fi
fi
echo ""
echo ""
echo -e "${BOLD}Configuration${NC}"
DEFAULT_APP_NAME="${APP_NAME:-zilch-app}"
if [ "$AUTO_MODE" = false ]; then
    read -p "${BLUE}App Name${NC} ${CYAN}[${DEFAULT_APP_NAME}]${NC}: " INPUT_APP_NAME
    APP_NAME="${INPUT_APP_NAME:-$DEFAULT_APP_NAME}"
else
    APP_NAME="${APP_NAME:-$DEFAULT_APP_NAME}"
fi

if [[ ! "$APP_NAME" =~ ^[a-z0-9-]{3,30}$ ]]; then
    echo -e "${RED}✗ Invalid app name (3-30 lowercase/numbers/hyphens)${NC}"
    exit 1
fi

echo ""
echo -e "${BOLD}Region${NC}"

# Show current region as default
REGION_DEFAULT="1"
if [ "$GCP_REGION" = "us-east1" ]; then
    REGION_DEFAULT="2"
elif [ "$GCP_REGION" = "us-west1" ]; then
    REGION_DEFAULT="3"
fi

if [ "$AUTO_MODE" = false ]; then
    if [ "$GCP_REGION" = "us-east1" ]; then
        echo "  [1] us-central1 (Iowa)"
        echo -e "  ${CYAN}[2] us-east1    (South Carolina) ← current${NC}"
        echo "  [3] us-west1    (Oregon)"
    elif [ "$GCP_REGION" = "us-west1" ]; then
        echo "  [1] us-central1 (Iowa)"
        echo "  [2] us-east1    (South Carolina)"
        echo -e "  ${CYAN}[3] us-west1    (Oregon) ← current${NC}"
    else
        echo -e "  ${CYAN}[1] us-central1 (Iowa) ← current${NC}"
        echo "  [2] us-east1    (South Carolina)"
        echo "  [3] us-west1    (Oregon)"
    fi
    read -p "${BLUE}Select${NC} ${CYAN}[1-3, default: ${REGION_DEFAULT}]${NC}: " REGION_CHOICE
    REGION_CHOICE="${REGION_CHOICE:-$REGION_DEFAULT}"
else
    REGION_CHOICE="$REGION_DEFAULT"
fi

case "$REGION_CHOICE" in
    2) GCP_REGION="us-east1" ;;
    3) GCP_REGION="us-west1" ;;
    *) GCP_REGION="us-central1" ;;
esac

prompt_toggle() {
    local feature_name=$1
    local current_value=$2
    local default_response="n"
    local status_display=""

    if [ "$current_value" = "true" ]; then
        default_response="y"
        status_display=" ${GREEN}[enabled]${NC}"
    else
        status_display=" ${CYAN}[disabled]${NC}"
    fi

    if [ "$AUTO_MODE" = false ]; then
        read -p "${BLUE}  ${feature_name}?${NC}${status_display} ${CYAN}[y/n]${NC} " choice
        choice="${choice:-$default_response}"
    else
        choice="$default_response"
    fi

    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo "true"
    else
        echo "false"
    fi
}

confirm_gcp_action() {
    local action=$1
    local default_response="y"

    if [ "$AUTO_MODE" = true ]; then
        # In auto mode, proceed without asking
        return 0
    fi

    read -p "${CYAN}${action}${NC} ${BLUE}[Y/n]${NC}: " choice
    choice="${choice:-$default_response}"

    if [[ "$choice" =~ ^[Yy]$ ]]; then
        return 0
    else
        echo -e "${YELLOW}⚠${NC} Skipped. Cannot continue without this step."
        exit 1
    fi
}

check_firestore_permissions() {
    local project=$1
    local current_user=$(gcloud config get-value account 2>/dev/null)

    # Check if user has Firestore Admin role
    FIRESTORE_BINDINGS=$(gcloud projects get-iam-policy "$project" \
        --flatten="bindings[].members" \
        --filter="bindings.role:datastore.admin AND bindings.members:serviceAccount:* OR bindings.members:user:*" \
        --format="value(bindings.members)" 2>/dev/null | grep -c "$current_user" || echo "0")

    if [ "$FIRESTORE_BINDINGS" -gt 0 ]; then
        return 0  # Has permission
    else
        return 1  # No permission
    fi
}

setup_firestore_permissions() {
    local project=$1
    local current_user=$(gcloud config get-value account 2>/dev/null)

    echo ""
    echo -e "${YELLOW}⚠${NC}  ${BOLD}Firestore Admin role required${NC}"
    echo ""
    echo "Your account (${CYAN}${current_user}${NC}) does not have Firestore Admin role."
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo ""
    echo "  1. ${BOLD}Self-grant role${NC} (if you have permissions):"
    echo -e "     ${CYAN}gcloud projects add-iam-policy-binding $project \\"
    echo "       --member=user:$current_user \\"
    echo "       --role=roles/datastore.admin${NC}"
    echo ""
    echo "  2. ${BOLD}Request from GCP admin${NC}:"
    echo -e "     Send them this command to run:"
    echo -e "     ${CYAN}gcloud projects add-iam-policy-binding $project \\"
    echo "       --member=user:$current_user \\"
    echo "       --role=roles/datastore.admin${NC}"
    echo ""
    echo "  3. ${BOLD}Check in Cloud Console${NC}:"
    echo -e "     ${CYAN}https://console.cloud.google.com/iam-admin/iam?project=$project${NC}"
    echo ""

    read -p "Try to grant yourself the role? ${BLUE}[y/n]${NC}: " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        if gcloud projects add-iam-policy-binding "$project" \
            --member="user:$current_user" \
            --role="roles/datastore.admin" \
            --quiet 2>/dev/null; then
            echo -e "${GREEN}✓${NC} Firestore Admin role granted"
            return 0
        else
            echo -e "${RED}✗${NC} Failed to grant role (you may not have permissions to modify IAM)"
            echo -e "   ${YELLOW}Contact your GCP admin and ask them to grant you: roles/datastore.admin${NC}"
            return 1
        fi
    fi
    return 1
}

echo ""
echo -e "${BOLD}Services${NC}"
ENABLE_FIRESTORE=$(prompt_toggle "Firestore" "$ENABLE_FIRESTORE")

if [ "$ENABLE_FIRESTORE" == "true" ] && [ "$AUTO_MODE" = false ]; then
    # Check if user has Firestore Admin permissions
    if ! check_firestore_permissions "$PROJECT_ID"; then
        if ! setup_firestore_permissions "$PROJECT_ID"; then
            echo -e "${YELLOW}⚠${NC}  Proceeding anyway, but Terraform may fail without Firestore Admin role"
        fi
    else
        echo -e "${GREEN}✓${NC} Firestore Admin role confirmed"
    fi
fi

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

if [ "$ENABLE_SCHEDULER" == "true" ] && [ "$AUTO_MODE" = false ]; then
    echo ""
    echo -e "${BOLD}Scheduler Settings${NC}"
    read -p "${BLUE}Cron expression${NC} ${CYAN}[${SCHEDULER_SCHEDULE}]${NC}: " INPUT
    SCHEDULER_SCHEDULE="${INPUT:-$SCHEDULER_SCHEDULE}"
    read -p "${BLUE}Endpoint path${NC} ${CYAN}[${SCHEDULER_ENDPOINT}]${NC}: " INPUT
    SCHEDULER_ENDPOINT="${INPUT:-$SCHEDULER_ENDPOINT}"
fi

echo ""
echo -e "${BOLD}Access & Monitoring${NC}"
ALLOW_UNAUTHENTICATED_ACCESS=$(prompt_toggle "Unauthenticated access" "$ALLOW_UNAUTHENTICATED_ACCESS")
ENABLE_MONITORING=$(prompt_toggle "Cloud Monitoring" "$ENABLE_MONITORING")

if [ "$ENABLE_MONITORING" == "true" ]; then
    # Cloud Monitoring with billing budgets requires ADC quota project
    if [ "$AUTO_MODE" = false ]; then
        echo ""
        echo -e "${BOLD}ADC Quota Project Setup${NC}"
        echo -e "${YELLOW}ℹ${NC} Billing API requires Application Default Credentials quota project"
        if [ -z "$PROJECT_ID" ]; then
            # Try to get project ID from gcloud config
            PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        fi

        if confirm_gcp_action "Set up ADC quota project for ${CYAN}${PROJECT_ID}${NC}?"; then
            if gcloud auth application-default set-quota-project "$PROJECT_ID" 2>/dev/null; then
                echo -e "${GREEN}✓${NC} ADC quota project configured"
            else
                echo -e "${RED}✗${NC} Failed to set quota project (may not have permissions)"
            fi
        fi
    fi

    if [ "$AUTO_MODE" = false ]; then
        echo ""
        echo -e "${BOLD}Budget Configuration${NC}"
        read -p "${BLUE}Monthly limit (USD)${NC} ${CYAN}[${BILLING_BUDGET_LIMIT_USD}]${NC}: " INPUT
        BILLING_BUDGET_LIMIT_USD="${INPUT:-$BILLING_BUDGET_LIMIT_USD}"

        echo ""
        echo -e "${BOLD}Select Billing Account${NC}"
    fi

    if [ "$AUTO_MODE" = true ]; then
        # In auto mode, skip the interactive billing account selection
        :
    else
        BILLING_LIST_OUTPUT=$(gcloud beta billing accounts list --format="csv[no-heading](name,displayName,open)" 2>&1)
        BILLING_LIST_EXIT=$?

        if [ $BILLING_LIST_EXIT -eq 0 ] && [ -n "$BILLING_LIST_OUTPUT" ]; then
        declare -a BILLING_IDS
        declare -a BILLING_NAMES
        index=1

        while IFS=',' read -r account_id display_name is_open; do
            account_id=$(echo "$account_id" | sed 's/"//g')
            display_name=$(echo "$display_name" | sed 's/"//g')
            is_open=$(echo "$is_open" | sed 's/"//g')

            # Skip closed accounts
            if [ "$is_open" != "True" ]; then
                continue
            fi

            BILLING_IDS[$index]="$account_id"
            BILLING_NAMES[$index]="$display_name"
            printf "  [%d] %s (%s)\n" "$index" "$display_name" "$account_id"
            index=$((index + 1))
        done <<< "$BILLING_LIST_OUTPUT"

        echo ""
        read -p "${BLUE}Select${NC} ${CYAN}[1-$((index - 1)), or skip]${NC}: " CHOICE
        if [ -n "$CHOICE" ] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -lt "$index" ]; then
            GCP_BILLING_ACCOUNT_ID="${BILLING_IDS[$CHOICE]}"
            BILLING_ACCOUNT_NAME="${BILLING_NAMES[$CHOICE]}"
        fi
    else
        echo -e "${YELLOW}⚠${NC} Could not list (requires org-level Billing Account User role)"
        echo ""
        echo "Find your ID:"
        echo -e "  ${CYAN}https://console.cloud.google.com/billing${NC}"
        echo -e "  ${CYAN}gcloud beta billing accounts list${NC}"
        echo ""
            read -p "${BLUE}Billing Account ID${NC} ${CYAN}[skip]${NC}: " INPUT
            GCP_BILLING_ACCOUNT_ID="${INPUT:-}"
        fi
    fi
fi

if [ "$ENABLE_CLOUD_BUILD" == "true" ]; then
    if [ -z "$GITHUB_OWNER" ] || [ -z "$GITHUB_REPO" ]; then
        if [ "$AUTO_MODE" = false ]; then
            echo ""
            echo -e "${BOLD}GitHub Repository${NC}"
            read -p "${BLUE}Username/org${NC}: " GITHUB_OWNER
            read -p "${BLUE}Repository name${NC}: " GITHUB_REPO
        fi

        if [ -z "$GITHUB_OWNER" ] || [ -z "$GITHUB_REPO" ]; then
            if [ "$AUTO_MODE" = false ]; then
                echo -e "${RED}✗ GitHub info required for Cloud Build${NC}"
                exit 1
            fi
        fi
    fi
fi

echo ""
echo -e "${BOLD}Saving Configuration${NC}"
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
scheduler_schedule=${SCHEDULER_SCHEDULE}
scheduler_timezone=${SCHEDULER_TIMEZONE}
scheduler_endpoint=${SCHEDULER_ENDPOINT}
enable_monitoring=${ENABLE_MONITORING}
billing_account_name=${BILLING_ACCOUNT_NAME}
billing_budget_limit_usd=${BILLING_BUDGET_LIMIT_USD}

# Cloud Run Access Control & Billing
allow_unauthenticated_access=${ALLOW_UNAUTHENTICATED_ACCESS}
gcp_billing_account_id=${GCP_BILLING_ACCOUNT_ID}
CONFIGEOF
echo -e "${GREEN}✓${NC} Saved"

STATE_BUCKET="${PROJECT_ID}-zilch-tfstate"
echo ""
echo -e "${BOLD}Infrastructure Setup${NC}"
echo -e "${BLUE}→${NC} State bucket ${CYAN}${STATE_BUCKET}${NC}"

# Always attempt to create the bucket (idempotent: succeeds if exists, fails only on real errors)
BUCKET_CREATED=false
if gcloud storage buckets create "gs://${STATE_BUCKET}" \
    --project="$PROJECT_ID" \
    --location="$GCP_REGION" \
    --uniform-bucket-level-access \
    &>/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Created bucket"
    BUCKET_CREATED=true
else
    if gcloud storage buckets describe "gs://${STATE_BUCKET}" &>/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Using existing bucket"
    else
        echo -e "${RED}✗ Failed to access bucket${NC}"
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
echo -e "${BOLD}Terraform${NC}"
echo -e "${BLUE}→${NC} Initializing"
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
    echo -e "${RED}✗ Terraform init failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Init complete"

# Note: Firestore, Scheduler, and Monitoring require special permissions/setup
# They're disabled by default. Users can enable them individually if they have the requirements.

echo -e "${BLUE}→${NC} Applying infrastructure"
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
    echo -e "${RED}✗ Terraform deployment failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Infrastructure deployed"

RUN_URL=$(terraform -chdir="$(dirname "$0")" output -raw cloud_run_url)
echo ""
echo -e "${BOLD}Post-Deployment Checks${NC}"
echo -e "${BLUE}→${NC} Testing endpoint ${CYAN}${RUN_URL}${NC}"

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
    echo -e "${YELLOW}⚠${NC} HTTP ${HTTP_STATUS}, retrying ($RETRY_COUNT/$MAX_RETRIES)..."
    sleep 5
done

if [ "$HEALTHY" = false ]; then
    echo -e "${YELLOW}⚠${NC} Health check timed out"
else
    echo -e "${GREEN}✓${NC} App is responding"
fi

# Config already saved early (before Terraform) for quick recovery on failure

echo ""
echo -e "${GREEN}${BOLD}Deployment Complete${NC}"
echo ""
echo -e "  Endpoint:  ${CYAN}${RUN_URL}${NC}"
echo -e "  Identity:  ${CYAN}$(terraform -chdir="$(dirname "$0")" output -raw service_account_email)${NC}"
echo -e "  Region:    ${CYAN}${GCP_REGION}${NC}"
echo ""
echo -e "${BOLD}Configured Services:${NC}"
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
echo -e "${BOLD}Next Steps:${NC}"
echo -e "  ${CYAN}gcloud run deploy ${APP_NAME} --source .${NC}"
echo -e "  ${CYAN}gcloud run logs read ${APP_NAME} --region=${GCP_REGION}${NC}"
if [ "$ENABLE_FIREBASE_AUTH" == "true" ]; then
    echo -e "  ${CYAN}https://console.firebase.google.com/project/${PROJECT_ID}/auth${NC}"
fi
echo ""
echo -e "Always Free limits: ${CYAN}https://cloud.google.com/always-free${NC}"
