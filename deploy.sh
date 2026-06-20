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

# Parse command line arguments
AUTO_MODE=false
DRY_RUN=false
VERBOSE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --auto)
            AUTO_MODE=true
            ;;
        --dry-run|--preview)
            DRY_RUN=true
            AUTO_MODE=true
            ;;
        --verbose|-v)
            VERBOSE=true
            ;;
        --help|-h)
            cat << 'HELP'
Zilch GCP Infrastructure Deployment

Usage:
  ./deploy.sh              Interactive mode - prompts for all settings
  ./deploy.sh --auto       Non-interactive mode - uses .zilch.config defaults
  ./deploy.sh --dry-run    Preview what would be deployed (no changes)
  ./deploy.sh --verbose    Show detailed output during deployment
  ./deploy.sh --help       Show this message

Examples:
  First time setup:
    ./deploy.sh

  Redeployment with saved config:
    ./deploy.sh --auto

  Preview changes before deploying:
    ./deploy.sh --dry-run

For more help, see: https://github.com/zilch-ai/reference-app
HELP
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
    shift
done

# Progress indicator helper
show_progress() {
    local msg=$1
    echo -ne "${BLUE}→${NC} $msg"
}

progress_done() {
    echo -e " ${GREEN}✓${NC}"
}

progress_fail() {
    local msg=$1
    echo -e " ${RED}✗${NC}"
    [ -n "$msg" ] && echo -e "  ${RED}$msg${NC}"
}

# Section header helper
section() {
    echo ""
    echo -e "${BOLD}━━━ $1 ━━━${NC}"
}

clear
echo -e "${BOLD}${CYAN}Zilch GCP Infrastructure Deployment${NC}"
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}(dry-run mode - no changes will be made)${NC}"
elif [ "$AUTO_MODE" = true ]; then
    echo -e "${BLUE}(auto mode - using defaults)${NC}"
fi
echo ""

# ============================================================================
# Helper Functions
# ============================================================================

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

    if gcloud projects get-iam-policy "$project" \
        --flatten="bindings[].members" \
        --filter="bindings.role:datastore.admin" \
        --format="value(bindings.members)" 2>/dev/null | grep -q "user:$current_user"; then
        return 0
    else
        return 1
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

build_tf_vars() {
    # Build consistent Terraform variable string
    echo "-var=gcp_project_id=${PROJECT_ID} \
-var=app_name=${APP_NAME} \
-var=gcp_region=${GCP_REGION} \
-var=github_owner=${GITHUB_OWNER:-} \
-var=github_repo=${GITHUB_REPO:-} \
-var=enable_cloud_build=${ENABLE_CLOUD_BUILD} \
-var=enable_firestore=${ENABLE_FIRESTORE} \
-var=enable_secret_manager=${ENABLE_SECRET_MANAGER} \
-var=enable_cloud_storage=${ENABLE_CLOUD_STORAGE} \
-var=enable_firebase_auth=${ENABLE_FIREBASE_AUTH} \
-var=enable_vertex_ai=${ENABLE_VERTEX_AI} \
-var=enable_pubsub=${ENABLE_PUBSUB} \
-var=enable_cloud_tasks=${ENABLE_CLOUD_TASKS} \
-var=enable_bigquery=${ENABLE_BIGQUERY} \
-var=enable_cloud_kms=${ENABLE_CLOUD_KMS} \
-var=enable_vision_ai=${ENABLE_VISION_AI} \
-var=enable_speech_to_text=${ENABLE_SPEECH_TO_TEXT} \
-var=enable_translation=${ENABLE_TRANSLATION} \
-var=enable_scheduler=${ENABLE_SCHEDULER} \
-var=scheduler_schedule=${SCHEDULER_SCHEDULE} \
-var=scheduler_timezone=${SCHEDULER_TIMEZONE} \
-var=scheduler_endpoint=${SCHEDULER_ENDPOINT} \
-var=enable_monitoring=${ENABLE_MONITORING} \
-var=billing_account_name=${BILLING_ACCOUNT_NAME} \
-var=billing_budget_limit_usd=${BILLING_BUDGET_LIMIT_USD} \
-var=enable_mysql=${ENABLE_MYSQL} \
-var=mysql_database_name=${MYSQL_DB_NAME} \
-var=allow_unauthenticated_access=${ALLOW_UNAUTHENTICATED_ACCESS} \
-var=gcp_billing_account_id=${GCP_BILLING_ACCOUNT_ID:-}"
}

# ============================================================================
# Prerequisites Check
# ============================================================================

section "Prerequisites"

# Check if running in Google Cloud Shell (has all tools pre-installed)
if [ -z "$CLOUD_SHELL" ]; then
    IN_CLOUD_SHELL=false
else
    IN_CLOUD_SHELL=true
    echo -e "${GREEN}✓${NC} Running in Google Cloud Shell"
fi

# Check for required tools
MISSING_TOOLS=""
for cmd in gcloud terraform curl bq; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING_TOOLS="$MISSING_TOOLS $cmd"
    fi
done

if [ -n "$MISSING_TOOLS" ]; then
    echo -e "${RED}✗ Required tools not found:$MISSING_TOOLS${NC}"
    echo ""
    if [ "$IN_CLOUD_SHELL" = false ]; then
        echo "Recommended: Use Google Cloud Shell (no installation needed)"
        echo "  1. Open https://console.cloud.google.com"
        echo "  2. Click the Cloud Shell icon (terminal icon)"
        echo "  3. Run this script from Cloud Shell"
        echo ""
        echo "Or install locally:"
        echo "  • gcloud CLI: https://cloud.google.com/sdk/docs/install"
        echo "  • Terraform: https://www.terraform.io/downloads"
        echo "  • curl: included in most systems"
        echo "  • bq: included with gcloud CLI"
    fi
    exit 1
fi
echo -e "${GREEN}✓${NC} Required tools available"

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
ENABLE_MYSQL="false"
MYSQL_DB_NAME="zilch_app"
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

# Create config from template on first run if it doesn't exist
if [ ! -f ".zilch.config" ]; then
    if [ -f ".zilch.config.template" ]; then
        echo -e "${BLUE}→${NC} Creating ${CYAN}.zilch.config${NC} from template"
        cp .zilch.config.template .zilch.config
        echo -e "${GREEN}✓${NC} Template copied"
        echo -e "${CYAN}→${NC} Edit .zilch.config and uncomment settings, then re-run deploy.sh"
        echo ""
    else
        echo -e "${YELLOW}⚠${NC} No .zilch.config or template found"
        echo -e "   Run from the deploy.sh directory or copy .zilch.config.template"
        exit 1
    fi
fi

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
            enable_mysql) ENABLE_MYSQL="$value" ;;
            mysql_database_name) MYSQL_DB_NAME="$value" ;;
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

    # Normalize ENABLE_MYSQL to true/false (accepts y/yes/true or n/no/false)
    if [[ "$ENABLE_MYSQL" == "y" || "$ENABLE_MYSQL" == "yes" || "$ENABLE_MYSQL" == "true" ]]; then
        ENABLE_MYSQL="true"
    else
        ENABLE_MYSQL="false"
    fi

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
    echo ""
    echo "Make sure:"
    echo "  • The project ID is correct"
    echo "  • You have access to the project"
    echo "  • You can list your projects with: ${CYAN}gcloud projects list${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Project ${CYAN}${PROJECT_ID}${NC}"

section "Verification"
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
section "Configuration"
DEFAULT_APP_NAME="${APP_NAME:-zilch-app}"
if [ "$AUTO_MODE" = false ]; then
    read -p "${BLUE}App Name${NC} ${CYAN}[${DEFAULT_APP_NAME}]${NC}: " INPUT_APP_NAME
    APP_NAME="${INPUT_APP_NAME:-$DEFAULT_APP_NAME}"
else
    APP_NAME="${APP_NAME:-$DEFAULT_APP_NAME}"
fi

if [[ ! "$APP_NAME" =~ ^[a-z0-9-]{3,30}$ ]]; then
    echo -e "${RED}✗ Invalid app name${NC}"
    echo ""
    echo "App names must:"
    echo "  • Be 3-30 characters long"
    echo "  • Contain only lowercase letters, numbers, and hyphens"
    echo "  • Not start or end with a hyphen"
    echo ""
    echo "Examples: my-app, zilch-prod, app123"
    exit 1
fi

section "Region Selection"

# Simplified region selection
regions=("us-central1:Iowa" "us-east1:South Carolina" "us-west1:Oregon")
region_default=1
for i in "${!regions[@]}"; do
    if [[ "${regions[$i]}" == "${GCP_REGION}:"* ]]; then
        region_default=$((i + 1))
        break
    fi
done

if [ "$AUTO_MODE" = false ]; then
    for i in "${!regions[@]}"; do
        IFS=':' read -r region_code region_name <<< "${regions[$i]}"
        marker=""
        [ $((i + 1)) -eq $region_default ] && marker=" ${CYAN}← current${NC}"
        printf "  [%d] %-15s %s%s\n" $((i + 1)) "$region_code" "($region_name)" "$marker"
    done
    read -p "${BLUE}Select${NC} ${CYAN}[1-3, default: ${region_default}]${NC}: " REGION_CHOICE
    REGION_CHOICE="${REGION_CHOICE:-$region_default}"
else
    REGION_CHOICE="$region_default"
fi

# Set region based on choice
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

interactive_service_menu() {
    # Numbered menu for service selection - simple and reliable
    local services_list=(
        "Firestore|ENABLE_FIRESTORE|NoSQL Database: document storage, real-time sync"
        "Cloud Storage|ENABLE_CLOUD_STORAGE|File Storage: user uploads, media, large files"
        "Secret Manager|ENABLE_SECRET_MANAGER|Secrets: API keys, passwords, config"
        "Firebase Auth|ENABLE_FIREBASE_AUTH|Authentication: user login, social auth"
        "Vertex AI|ENABLE_VERTEX_AI|Machine Learning: predictions, model training"
        "Cloud Build|ENABLE_CLOUD_BUILD|CI/CD: auto-deploy from GitHub"
        "Pub/Sub|ENABLE_PUBSUB|Event Streaming: async messaging, events"
        "Cloud Tasks|ENABLE_CLOUD_TASKS|Task Queue: distributed work, retries"
        "BigQuery|ENABLE_BIGQUERY|Data Warehouse: SQL on big data"
        "Cloud KMS|ENABLE_CLOUD_KMS|Encryption Keys: key management, data protection"
        "Vision AI|ENABLE_VISION_AI|Image Recognition: OCR, object detection"
        "Speech-to-Text|ENABLE_SPEECH_TO_TEXT|Audio: speech recognition, transcription"
        "Translation|ENABLE_TRANSLATION|Languages: multi-language text translation"
        "Cloud Scheduler|ENABLE_SCHEDULER|Cron Jobs: periodic tasks, schedules"
        "Cloud Monitoring|ENABLE_MONITORING|Monitoring: alerts, budgets, log monitoring"
        "MySQL Database|ENABLE_MYSQL|Relational DB: SQL, complex queries"
    )

    echo ""
    echo -e "${BOLD}Services Configuration${NC}"
    echo "Toggle each service on/off:"
    echo ""

    # Display menu with current state
    for i in "${!services_list[@]}"; do
        IFS='|' read -r name var desc <<< "${services_list[$i]}"
        eval current=\${$var}
        local checkbox="[-]"
        [ "$current" = "true" ] && checkbox="[X]"
        printf "  %2d. $checkbox %-25s %s\n" $((i+1)) "$name" "$([ "$current" = "true" ] && echo "ENABLED" || echo "disabled")"
    done

    echo ""
    echo "Enter service number to toggle (or press Enter to continue):"
    echo ""

    while true; do
        read -p "> " choice

        # Empty input = continue
        if [ -z "$choice" ]; then
            break
        fi

        # Validate input is a number between 1 and 16
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt 16 ]; then
            echo "Invalid choice. Enter 1-16 or press Enter to continue."
            continue
        fi

        # Toggle the selected service
        idx=$((choice - 1))
        IFS='|' read -r name var desc <<< "${services_list[$idx]}"
        eval current=\${$var}

        if [ "$current" = "true" ]; then
            eval $var=false
        else
            eval $var=true
        fi

        # Show updated state
        eval new_state=\${$var}
        local checkbox="[-]"
        [ "$new_state" = "true" ] && checkbox="[X]"
        echo -e "  $checkbox $name now $([ "$new_state" = "true" ] && echo -e "${GREEN}ENABLED${NC}" || echo -e "${YELLOW}disabled${NC}")"
        echo ""
    done

    # Show summary
    echo ""
    echo -e "${BOLD}Selected Services:${NC}"
    for i in "${!services_list[@]}"; do
        IFS='|' read -r name var desc <<< "${services_list[$i]}"
        eval state=\${$var}
        [ "$state" = "true" ] && echo -e "  ${GREEN}✓${NC} $name"
    done
    echo ""
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

    # Check if user has Firestore Admin role by looking for user in datastore.admin bindings
    if gcloud projects get-iam-policy "$project" \
        --flatten="bindings[].members" \
        --filter="bindings.role:datastore.admin" \
        --format="value(bindings.members)" 2>/dev/null | grep -q "user:$current_user"; then
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

section "Services"

if [ "$AUTO_MODE" = false ]; then
    interactive_service_menu
else
    echo -e "${BLUE}→${NC} Using service settings from config (auto mode)"
fi

# Check Firestore permissions if enabled
if [ "$ENABLE_FIRESTORE" == "true" ]; then
    if ! check_firestore_permissions "$PROJECT_ID"; then
        if [ "$AUTO_MODE" = false ]; then
            if ! setup_firestore_permissions "$PROJECT_ID"; then
                echo -e "${YELLOW}⚠${NC}  Proceeding anyway, but Terraform may fail without Firestore Admin role"
            fi
        else
            echo -e "${RED}✗${NC} Firestore Admin role required but not found"
            echo -e "   Grant it with: ${CYAN}gcloud projects add-iam-policy-binding $PROJECT_ID --member=user:\$(gcloud config get-value account) --role=roles/datastore.admin${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}✓${NC} Firestore Admin role confirmed"
    fi
fi

# MySQL Database (NEW)
echo ""
echo "=== MySQL Database (Optional) ==="
echo "Deploy a free MySQL database on Compute Engine?"
echo "  • Cost: ~\$1.26/month (compute free, minimal storage)"
echo "  • Good for: Transactional relational data"
echo "  • Size: 1-10GB datasets, 100-500 writes/sec"
echo ""
if [ "$AUTO_MODE" = false ]; then
    # Use config value as default, or "false" if not set
    DEFAULT_MYSQL="${ENABLE_MYSQL:-false}"
    DEFAULT_DISPLAY=$([ "$DEFAULT_MYSQL" = "true" ] && echo "y" || echo "n")
    read -p "Enable MySQL? (y/n) [default: ${DEFAULT_DISPLAY}]: " INPUT
    if [[ "$INPUT" == "y" || "$INPUT" == "yes" ]]; then
        ENABLE_MYSQL="true"
    elif [[ "$INPUT" == "n" || "$INPUT" == "no" || "$INPUT" == "" ]]; then
        ENABLE_MYSQL="$DEFAULT_MYSQL"
    fi
fi

if [ "$ENABLE_MYSQL" = "true" ]; then
    TERRAFORM_VARS="$TERRAFORM_VARS -var=enable_mysql=true"
    echo "✓ MySQL will be provisioned"

    if [ "$AUTO_MODE" = false ]; then
        # Use config value as default, or "zilch_app" if not set
        DEFAULT_DB_NAME="${MYSQL_DB_NAME:-zilch_app}"
        read -p "Enter MySQL database name [default: ${DEFAULT_DB_NAME}]: " INPUT
        MYSQL_DB_NAME="${INPUT:-$DEFAULT_DB_NAME}"
    fi
    TERRAFORM_VARS="$TERRAFORM_VARS -var=mysql_database_name=$MYSQL_DB_NAME"
else
    TERRAFORM_VARS="$TERRAFORM_VARS -var=enable_mysql=false"
    echo "✓ MySQL will not be provisioned"
fi

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
    # (Run setup even in AUTO_MODE to fail fast before Terraform)
    echo ""
    echo -e "${BOLD}ADC Quota Project Setup${NC}"
    echo -e "${YELLOW}ℹ${NC} Billing API requires Application Default Credentials quota project"
    if [ -z "$PROJECT_ID" ]; then
        # Try to get project ID from gcloud config
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
    fi

    if [ "$AUTO_MODE" = false ]; then
        if confirm_gcp_action "Set up ADC quota project for ${CYAN}${PROJECT_ID}${NC}?"; then
            if gcloud auth application-default set-quota-project "$PROJECT_ID" 2>/dev/null; then
                echo -e "${GREEN}✓${NC} ADC quota project configured"
            else
                echo -e "${RED}✗${NC} Failed to set quota project (may not have permissions)"
            fi
        fi
    else
        # In auto mode, just try to set it up without asking
        if gcloud auth application-default set-quota-project "$PROJECT_ID" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} ADC quota project configured"
        else
            echo -e "${RED}✗${NC} Failed to set quota project (may not have permissions)"
            echo -e "   Run: ${CYAN}gcloud auth application-default set-quota-project $PROJECT_ID${NC}"
            exit 1
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

section "Saving Configuration"
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

# Phase 5: MySQL Database (optional)
enable_mysql=${ENABLE_MYSQL}
mysql_database_name=${MYSQL_DB_NAME}

# Cloud Run Access Control & Billing
allow_unauthenticated_access=${ALLOW_UNAUTHENTICATED_ACCESS}
gcp_billing_account_id=${GCP_BILLING_ACCOUNT_ID}
CONFIGEOF
echo -e "${GREEN}✓${NC} Saved"

STATE_BUCKET="${PROJECT_ID}-zilch-tfstate"
section "Infrastructure Setup"
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
        if [ "$AUTO_MODE" = false ]; then
            read -p "Press ENTER once connected (or Terraform will create it)..."
        else
            echo "(auto mode - skipping GitHub prompt, Terraform will create trigger)"
        fi
    fi
fi

if [ "$BUCKET_CREATED" = true ]; then
    sleep 3
fi

section "Terraform Planning & Deployment"

# Check for and handle stale Terraform state locks
handle_terraform_lock() {
    local lock_path="gs://${STATE_BUCKET}/terraform/state/${APP_NAME}/default.tflock"

    if gcloud storage ls "$lock_path" &>/dev/null 2>&1; then
        echo -e "${YELLOW}⚠${NC} Found existing Terraform state lock"
        echo ""

        # Try to get lock metadata
        LOCK_METADATA=$(gcloud storage ls -L "$lock_path" 2>/dev/null | grep -E "Time created:|Time updated:" | head -2)
        if [ -n "$LOCK_METADATA" ]; then
            echo "Lock details:"
            echo "$LOCK_METADATA" | sed 's/^/  /'
            echo ""
        fi

        echo "This usually means:"
        echo "  • A previous deployment was interrupted"
        echo "  • Terraform crashed while holding the lock"
        echo "  • Multiple deployments are running simultaneously"
        echo ""

        if [ "$AUTO_MODE" = true ]; then
            echo -e "${RED}✗${NC} State lock exists and auto mode cannot proceed safely${NC}"
            echo ""
            echo "To recover, either:"
            echo "  1. Wait for the lock to expire (if another deployment is running)"
            echo "  2. Manually clean up: ${CYAN}gsutil rm ${lock_path}${NC}"
            echo "  3. Force-remove from previous session if confirmed stale:"
            echo "     ${CYAN}gsutil -m rm -r ${lock_path}${NC}"
            exit 1
        else
            read -p "${BLUE}Remove stale lock and continue?${NC} ${CYAN}[y/n]${NC}: " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                if gcloud storage rm "$lock_path" &>/dev/null 2>&1; then
                    echo -e "${GREEN}✓${NC} Lock removed"
                else
                    echo -e "${RED}✗${NC} Failed to remove lock"
                    exit 1
                fi
            else
                echo -e "${YELLOW}⚠${NC} Cannot proceed without removing lock"
                exit 1
            fi
        fi
    fi
}

handle_terraform_lock

echo -e "${BLUE}→${NC} Enabling required APIs"
# Cloud Resource Manager API is required by Terraform to manage services and IAM
gcloud services enable cloudresourcemanager.googleapis.com --project="$PROJECT_ID" --quiet 2>&1 >/dev/null
echo -e "  ${GREEN}✓${NC} Cloud Resource Manager API"

# Enable Compute Engine API if MySQL is enabled (MySQL runs on Compute Engine VM)
if [ "$ENABLE_MYSQL" = "true" ]; then
    gcloud services enable compute.googleapis.com --project="$PROJECT_ID" --quiet 2>&1 >/dev/null
    echo -e "  ${GREEN}✓${NC} Compute Engine API (MySQL)"
fi

# Wait for Cloud Resource Manager API to propagate (can take a few seconds)
API_READY=false
for i in {1..10}; do
    if gcloud services list --project="$PROJECT_ID" --enabled --filter="name:cloudresourcemanager" --format="value(name)" 2>/dev/null | grep -q cloudresourcemanager; then
        API_READY=true
        break
    fi
    if [ $i -lt 10 ]; then
        sleep 1
    fi
done

if [ "$API_READY" = false ]; then
    echo -e "${YELLOW}⚠${NC} Cloud Resource Manager API may still be initializing, continuing anyway..."
fi

show_progress "Initializing Terraform"
TF_INIT_SUCCESS=false
TF_INIT_RETRIES=0
TF_MAX_RETRIES=3

while [ $TF_INIT_RETRIES -lt $TF_MAX_RETRIES ]; do
    if terraform -chdir="$(dirname "$0")" init \
        -backend-config="bucket=${STATE_BUCKET}" \
        -backend-config="prefix=terraform/state/${APP_NAME}" \
        -reconfigure 2>&1 >/dev/null; then
        TF_INIT_SUCCESS=true
        break
    fi
    TF_INIT_RETRIES=$((TF_INIT_RETRIES+1))
    if [ $TF_INIT_RETRIES -lt $TF_MAX_RETRIES ]; then
        echo -ne " ${YELLOW}retrying $TF_INIT_RETRIES/$TF_MAX_RETRIES${NC}"
        sleep 2
    fi
done

if [ "$TF_INIT_SUCCESS" = false ]; then
    progress_fail "Terraform init failed"
    exit 1
fi
progress_done

# State Reconciliation: Check for pre-existing resources and import if needed
section "State Reconciliation"

is_in_terraform_state() {
    local resource_path=$1
    terraform -chdir="$(dirname "$0")" state list "$resource_path" &>/dev/null
}

build_tf_vars() {
    echo "-var=gcp_project_id=${PROJECT_ID} \
-var=app_name=${APP_NAME} \
-var=gcp_region=${GCP_REGION} \
-var=github_owner=${GITHUB_OWNER:-} \
-var=github_repo=${GITHUB_REPO:-} \
-var=enable_cloud_build=${ENABLE_CLOUD_BUILD} \
-var=enable_firestore=${ENABLE_FIRESTORE} \
-var=enable_secret_manager=${ENABLE_SECRET_MANAGER} \
-var=enable_cloud_storage=${ENABLE_CLOUD_STORAGE} \
-var=enable_firebase_auth=${ENABLE_FIREBASE_AUTH} \
-var=enable_vertex_ai=${ENABLE_VERTEX_AI} \
-var=enable_pubsub=${ENABLE_PUBSUB} \
-var=enable_cloud_tasks=${ENABLE_CLOUD_TASKS} \
-var=enable_bigquery=${ENABLE_BIGQUERY} \
-var=enable_cloud_kms=${ENABLE_CLOUD_KMS} \
-var=enable_vision_ai=${ENABLE_VISION_AI} \
-var=enable_speech_to_text=${ENABLE_SPEECH_TO_TEXT} \
-var=enable_translation=${ENABLE_TRANSLATION} \
-var=enable_scheduler=${ENABLE_SCHEDULER} \
-var=scheduler_schedule=${SCHEDULER_SCHEDULE} \
-var=scheduler_timezone=${SCHEDULER_TIMEZONE} \
-var=scheduler_endpoint=${SCHEDULER_ENDPOINT} \
-var=enable_monitoring=${ENABLE_MONITORING} \
-var=billing_account_name=${BILLING_ACCOUNT_NAME} \
-var=billing_budget_limit_usd=${BILLING_BUDGET_LIMIT_USD} \
-var=enable_mysql=${ENABLE_MYSQL} \
-var=mysql_database_name=${MYSQL_DB_NAME} \
-var=allow_unauthenticated_access=${ALLOW_UNAUTHENTICATED_ACCESS} \
-var=gcp_billing_account_id=${GCP_BILLING_ACCOUNT_ID:-}"
}

import_resource() {
    local resource_type=$1
    local resource_id=$2
    local output

    output=$(terraform -chdir="$(dirname "$0")" import \
      $(build_tf_vars) \
      "${resource_type}" "${resource_id}" 2>&1)

    if echo "$output" | grep -qE "Successfully imported|Import successful"; then
        return 0
    elif echo "$output" | grep -q "Configuration for import target does not exist"; then
        return 0
    else
        echo "$output"
        return 1
    fi
}

check_and_import_resource() {
    # Parallel worker for state reconciliation
    # Args: resource_type resource_id gcp_check_cmd display_name
    local resource_type=$1
    local resource_id=$2
    local gcp_check_cmd=$3
    local display_name=$4
    local state_path=$5

    # Check if already in state
    if terraform -chdir="$(dirname "$0")" state list "$state_path" &>/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $display_name already in Terraform state"
        return 0
    fi

    # Check if exists in GCP
    if eval "$gcp_check_cmd" &>/dev/null 2>&1; then
        echo -e "${BLUE}→${NC} Found $display_name in GCP but not in Terraform state"
        if import_resource "$resource_type" "$resource_id"; then
            echo -e "${GREEN}✓${NC} Imported $display_name"
        else
            echo -e "${RED}✗${NC} Failed to import $display_name"
            return 1
        fi
    fi
    return 0
}

# Run import checks in parallel (all are independent)
# Collect PIDs of background processes
declare -a import_pids

# Service Accounts - always check
check_and_import_resource "google_service_account.app" \
    "${APP_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
    "gcloud iam service-accounts describe ${APP_NAME}@${PROJECT_ID}.iam.gserviceaccount.com --project=${PROJECT_ID}" \
    "Service account (app)" \
    "google_service_account.app" &
import_pids+=($!)

check_and_import_resource "google_service_account.cloud_build" \
    "${APP_NAME}-builder@${PROJECT_ID}.iam.gserviceaccount.com" \
    "gcloud iam service-accounts describe ${APP_NAME}-builder@${PROJECT_ID}.iam.gserviceaccount.com --project=${PROJECT_ID}" \
    "Cloud Build service account" \
    "google_service_account.cloud_build" &
import_pids+=($!)

# Artifact Registry - always check
check_and_import_resource "google_artifact_registry_repository.app_images[0]" \
    "projects/${PROJECT_ID}/locations/${GCP_REGION}/repositories/${APP_NAME}-images" \
    "gcloud artifacts repositories describe ${APP_NAME}-images --location=${GCP_REGION} --project=${PROJECT_ID}" \
    "Artifact Registry repository" \
    "google_artifact_registry_repository.app_images[0]" &
import_pids+=($!)

# Cloud Run Service - always check
check_and_import_resource "google_cloud_run_v2_service.app" \
    "${GCP_REGION}/${APP_NAME}" \
    "gcloud run services describe ${APP_NAME} --region=${GCP_REGION} --project=${PROJECT_ID}" \
    "Cloud Run service" \
    "google_cloud_run_v2_service.app" &
import_pids+=($!)

# BigQuery Dataset
if [ "$ENABLE_BIGQUERY" == "true" ]; then
    DATASET_ID=$(echo ${APP_NAME} | tr '-' '_')_analytics
    check_and_import_resource "google_bigquery_dataset.app_analytics[0]" \
        "$DATASET_ID" \
        "bq ls -d $DATASET_ID --project_id=${PROJECT_ID}" \
        "BigQuery dataset" \
        "google_bigquery_dataset.app_analytics[0]" &
    import_pids+=($!)
fi

# Firestore Database
if [ "$ENABLE_FIRESTORE" == "true" ]; then
    check_and_import_resource "google_firestore_database.default[0]" \
        "(default)" \
        "gcloud firestore databases list --project=${PROJECT_ID} --format=value(name) | grep -q ." \
        "Firestore database" \
        "google_firestore_database.default[0]" &
    import_pids+=($!)
fi

# Cloud Storage - app bucket
if [ "$ENABLE_CLOUD_STORAGE" == "true" ]; then
    EXISTING_BUCKET=$(gcloud storage buckets list --project="${PROJECT_ID}" --filter="name:${APP_NAME}-storage" --format="value(name)" 2>/dev/null | head -1)
    if [ -n "$EXISTING_BUCKET" ]; then
        check_and_import_resource "google_storage_bucket.app[0]" \
            "$EXISTING_BUCKET" \
            "gcloud storage buckets describe gs://${EXISTING_BUCKET} --project=${PROJECT_ID}" \
            "Storage bucket (app)" \
            "google_storage_bucket.app[0]" &
        import_pids+=($!)
    fi
fi

# Cloud Storage - Cloud Build logs
if [ "$ENABLE_CLOUD_BUILD" == "true" ]; then
    LOGS_BUCKET="${PROJECT_ID}_cloudbuild"
    check_and_import_resource "google_storage_bucket.cloud_build_logs[0]" \
        "$LOGS_BUCKET" \
        "gcloud storage buckets describe gs://${LOGS_BUCKET} --project=${PROJECT_ID}" \
        "Cloud Build logs bucket" \
        "google_storage_bucket.cloud_build_logs[0]" &
    import_pids+=($!)
fi

# Cloud Scheduler
if [ "$ENABLE_SCHEDULER" == "true" ]; then
    check_and_import_resource "google_cloud_scheduler_job.app_cron[0]" \
        "projects/${PROJECT_ID}/locations/${GCP_REGION}/jobs/${APP_NAME}-cron" \
        "gcloud scheduler jobs describe ${APP_NAME}-cron --location=${GCP_REGION} --project=${PROJECT_ID}" \
        "Cloud Scheduler job" \
        "google_cloud_scheduler_job.app_cron[0]" &
    import_pids+=($!)
fi

# Pub/Sub Topic (app events)
if [ "$ENABLE_PUBSUB" == "true" ]; then
    check_and_import_resource "google_pubsub_topic.app_events[0]" \
        "projects/${PROJECT_ID}/topics/${APP_NAME}-events" \
        "gcloud pubsub topics describe ${APP_NAME}-events --project=${PROJECT_ID}" \
        "Pub/Sub topic (app events)" \
        "google_pubsub_topic.app_events[0]" &
    import_pids+=($!)

    check_and_import_resource "google_pubsub_subscription.app_events_sub[0]" \
        "projects/${PROJECT_ID}/subscriptions/${APP_NAME}-events-subscription" \
        "gcloud pubsub subscriptions describe ${APP_NAME}-events-subscription --project=${PROJECT_ID}" \
        "Pub/Sub subscription (app events)" \
        "google_pubsub_subscription.app_events_sub[0]" &
    import_pids+=($!)
fi

# Cloud Tasks Queue
if [ "$ENABLE_CLOUD_TASKS" == "true" ]; then
    QUEUE_NAME=$(gcloud tasks queues list --location="${GCP_REGION}" --project="${PROJECT_ID}" --filter="name:${APP_NAME}-jobs" --format="value(name)" 2>/dev/null | head -1)
    if [ -n "$QUEUE_NAME" ]; then
        check_and_import_resource "google_cloud_tasks_queue.app_jobs[0]" \
            "projects/${PROJECT_ID}/locations/${GCP_REGION}/queues/${QUEUE_NAME}" \
            "gcloud tasks queues describe ${QUEUE_NAME} --location=${GCP_REGION} --project=${PROJECT_ID}" \
            "Cloud Tasks queue" \
            "google_cloud_tasks_queue.app_jobs[0]" &
        import_pids+=($!)
    fi
fi

# Secret Manager Secret
if [ "$ENABLE_SECRET_MANAGER" == "true" ]; then
    EXAMPLE_SECRET="${APP_NAME}-example-secret"
    check_and_import_resource "google_secret_manager_secret.example[0]" \
        "$EXAMPLE_SECRET" \
        "gcloud secrets describe $EXAMPLE_SECRET --project=${PROJECT_ID}" \
        "Secret Manager secret" \
        "google_secret_manager_secret.example[0]" &
    import_pids+=($!)
fi

# Cloud Build Trigger
if [ "$ENABLE_CLOUD_BUILD" == "true" ]; then
    TRIGGER_ID=$(gcloud builds triggers list --project="${PROJECT_ID}" --filter="name:${APP_NAME}-trigger" --format="value(id)" 2>/dev/null | head -1)
    if [ -n "$TRIGGER_ID" ]; then
        check_and_import_resource "google_cloudbuild_trigger.app_build[0]" \
            "$TRIGGER_ID" \
            "gcloud builds triggers describe $TRIGGER_ID --project=${PROJECT_ID}" \
            "Cloud Build trigger" \
            "google_cloudbuild_trigger.app_build[0]" &
        import_pids+=($!)
    fi
fi

# Pub/Sub Topic (budget alerts)
if [ "$ENABLE_MONITORING" == "true" ]; then
    BUDGET_TOPIC="${APP_NAME}-budget-alerts"
    check_and_import_resource "google_pubsub_topic.budget_alerts[0]" \
        "projects/${PROJECT_ID}/topics/${BUDGET_TOPIC}" \
        "gcloud pubsub topics describe $BUDGET_TOPIC --project=${PROJECT_ID}" \
        "Pub/Sub topic (budget alerts)" \
        "google_pubsub_topic.budget_alerts[0]" &
    import_pids+=($!)

    ALERTS_SUB="${APP_NAME}-budget-alerts-sub"
    check_and_import_resource "google_pubsub_subscription.budget_alerts_sub[0]" \
        "projects/${PROJECT_ID}/subscriptions/${ALERTS_SUB}" \
        "gcloud pubsub subscriptions describe $ALERTS_SUB --project=${PROJECT_ID}" \
        "Pub/Sub subscription (budget alerts)" \
        "google_pubsub_subscription.budget_alerts_sub[0]" &
    import_pids+=($!)
fi

# Cloud KMS - Key Ring and Crypto Key
if [ "$ENABLE_CLOUD_KMS" == "true" ]; then
    KEYRING_NAME=$(gcloud kms keyrings list --location="${GCP_REGION}" --project="${PROJECT_ID}" --filter="name:${APP_NAME}-keyring" --format="value(displayName)" 2>/dev/null | head -1)
    if [ -z "$KEYRING_NAME" ]; then
        KEYRING=$(gcloud kms keyrings list --location="${GCP_REGION}" --project="${PROJECT_ID}" --filter="name:${APP_NAME}-keyring" --format="value(name)" 2>/dev/null | head -1)
        KEYRING_NAME=$(echo "$KEYRING" | sed 's|.*/||')
    fi

    if [ -n "$KEYRING_NAME" ]; then
        check_and_import_resource "google_kms_key_ring.app_keys[0]" \
            "${GCP_REGION}/${KEYRING_NAME}" \
            "gcloud kms keyrings describe $KEYRING_NAME --location=${GCP_REGION} --project=${PROJECT_ID}" \
            "KMS key ring" \
            "google_kms_key_ring.app_keys[0]" &
        import_pids+=($!)

        # Crypto key depends on key ring existing
        if gcloud kms keys list --location="${GCP_REGION}" --keyring="${KEYRING_NAME}" --project="${PROJECT_ID}" --filter="name:${APP_NAME}-key" &>/dev/null 2>&1; then
            check_and_import_resource "google_kms_crypto_key.app_key[0]" \
                "${PROJECT_ID}/${GCP_REGION}/${KEYRING_NAME}/${APP_NAME}-key" \
                "gcloud kms keys describe ${APP_NAME}-key --location=${GCP_REGION} --keyring=${KEYRING_NAME} --project=${PROJECT_ID}" \
                "KMS crypto key" \
                "google_kms_crypto_key.app_key[0]" &
            import_pids+=($!)
        fi
    fi
fi

# Wait for all background processes and collect any failures
echo -e "${BLUE}→${NC} Checking resources in parallel..."
declare import_failed=false
for pid in "${import_pids[@]}"; do
    if ! wait $pid; then
        import_failed=true
    fi
done

if [ "$import_failed" = true ]; then
    echo -e "${YELLOW}⚠${NC} Some imports had issues (check output above), continuing anyway..."
fi

echo ""
show_progress "Planning infrastructure changes"

# Export quota project for billing API access in Terraform
export GOOGLE_CLOUD_QUOTA_PROJECT="${PROJECT_ID}"

# In dry-run mode, show plan instead of applying
if [ "$DRY_RUN" = true ]; then
    eval "terraform -chdir=\"\$(dirname \"\$0\")\" plan $(build_tf_vars)" 2>&1 | tail -20
    progress_done
    echo ""
    echo -e "${YELLOW}Preview complete.${NC} No changes were made."
    echo "Run without --dry-run to apply these changes."
    exit 0
else
    eval "terraform -chdir=\"\$(dirname \"\$0\")\" apply -auto-approve $(build_tf_vars)" || exit 1
    progress_done
fi

echo -e "${GREEN}✓${NC} Infrastructure deployed"

if ! RUN_URL=$(terraform -chdir="$(dirname "$0")" output -raw cloud_run_url 2>&1); then
    echo -e "${RED}✗${NC} Failed to retrieve Cloud Run URL"
    echo "$RUN_URL"
    exit 1
fi

section "Post-Deployment Verification"
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

# Helper to safely get terraform outputs
get_tf_output() {
    local output_name=$1
    terraform -chdir="$(dirname "$0")" output -raw "$output_name" 2>/dev/null || echo ""
}

SERVICE_ACCOUNT_EMAIL=$(get_tf_output service_account_email)
STORAGE_BUCKET=$(get_tf_output storage_bucket)
KMS_KEY_ID=$(get_tf_output kms_key_id)

echo ""
# Create deployment summary file
SUMMARY_FILE=".zilch-deployment-$(date +%s).txt"
{
    echo "═══════════════════════════════════════════════════════════════"
    echo "Zilch Deployment Summary"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Deployment Time: $(date)"
    echo "Project: $PROJECT_ID"
    echo "Application: $APP_NAME"
    echo "Region: $GCP_REGION"
    echo ""
    echo "───────────────────────────────────────────────────────────────"
    echo "Endpoints"
    echo "───────────────────────────────────────────────────────────────"
    echo "Cloud Run URL: $RUN_URL"
    if [ -n "$SERVICE_ACCOUNT_EMAIL" ]; then
        echo "Service Account: $SERVICE_ACCOUNT_EMAIL"
    fi
    echo ""
} > "$SUMMARY_FILE"

echo -e "${GREEN}${BOLD}✓ Deployment Complete${NC}"
echo ""
echo -e "Summary saved to: ${CYAN}$SUMMARY_FILE${NC}"
echo ""
echo -e "  Endpoint:  ${CYAN}${RUN_URL}${NC}"
if [ -n "$SERVICE_ACCOUNT_EMAIL" ]; then
    echo -e "  Identity:  ${CYAN}${SERVICE_ACCOUNT_EMAIL}${NC}"
fi
echo -e "  Region:    ${CYAN}${GCP_REGION}${NC}"
echo ""
echo -e "${BOLD}Configured Services:${NC}"
if [ "$ENABLE_FIRESTORE" == "true" ]; then echo "  ↳ ZILCH_FIRESTORE_DATABASE : (default)"; fi
if [ "$ENABLE_SECRET_MANAGER" == "true" ]; then echo "  ↳ ZILCH_SECRET_PREFIX      : ${APP_NAME}-"; fi
if [ "$ENABLE_CLOUD_STORAGE" == "true" ] && [ -n "$STORAGE_BUCKET" ]; then echo "  ↳ ZILCH_STORAGE_BUCKET     : ${STORAGE_BUCKET}"; fi
if [ "$ENABLE_VERTEX_AI" == "true" ]; then echo "  ↳ ZILCH_VERTEX_AI_ENABLED  : true"; fi
if [ "$ENABLE_FIREBASE_AUTH" == "true" ]; then echo "  ↳ ZILCH_FIREBASE_ENABLED   : true"; fi
if [ "$ENABLE_PUBSUB" == "true" ]; then echo "  ↳ ZILCH_PUBSUB_TOPIC       : ${APP_NAME}-events"; fi
if [ "$ENABLE_PUBSUB" == "true" ]; then echo "  ↳ ZILCH_PUBSUB_SUBSCRIPTION: ${APP_NAME}-events-subscription"; fi
if [ "$ENABLE_CLOUD_TASKS" == "true" ]; then echo "  ↳ ZILCH_CLOUD_TASKS_QUEUE  : projects/${PROJECT_ID}/locations/${GCP_REGION}/queues/${APP_NAME}-jobs"; fi
if [ "$ENABLE_BIGQUERY" == "true" ]; then echo "  ↳ ZILCH_BIGQUERY_DATASET   : $(echo ${APP_NAME} | tr '-' '_')_analytics"; fi
if [ "$ENABLE_CLOUD_KMS" == "true" ] && [ -n "$KMS_KEY_ID" ]; then echo "  ↳ ZILCH_KMS_KEY_ID         : ${KMS_KEY_ID}"; fi
if [ "$ENABLE_VISION_AI" == "true" ]; then echo "  ↳ ZILCH_VISION_AI_ENABLED  : true"; fi
if [ "$ENABLE_SPEECH_TO_TEXT" == "true" ]; then echo "  ↳ ZILCH_SPEECH_TO_TEXT_ENABLED: true"; fi
if [ "$ENABLE_TRANSLATION" == "true" ]; then echo "  ↳ ZILCH_TRANSLATION_ENABLED: true"; fi
if [ "$ENABLE_SCHEDULER" == "true" ]; then echo "  ↳ ZILCH_SCHEDULER_ENABLED  : ${SCHEDULER_SCHEDULE} (${SCHEDULER_TIMEZONE})"; fi
if [ "$ENABLE_MONITORING" == "true" ]; then echo "  ↳ ZILCH_MONITORING_ENABLED : ${BILLING_BUDGET_LIMIT_USD} USD/month alert"; fi
if [ "$ENABLE_MYSQL" == "true" ] || [[ "$ENABLE_MYSQL" == "y" ]] || [[ "$ENABLE_MYSQL" == "yes" ]]; then echo "  ↳ ZILCH_MYSQL_DATABASE     : ${MYSQL_DB_NAME}"; fi
echo ""

# Append MySQL connection info to summary file (if enabled)
if [ "$ENABLE_MYSQL" == "true" ] || [[ "$ENABLE_MYSQL" == "y" ]] || [[ "$ENABLE_MYSQL" == "yes" ]]; then
    MYSQL_HOST=$(terraform -chdir="$(dirname "$0")" output -raw zilch_mysql_host 2>/dev/null || echo "")
    MYSQL_PORT=$(terraform -chdir="$(dirname "$0")" output -raw zilch_mysql_port 2>/dev/null || echo "")
    MYSQL_USER=$(terraform -chdir="$(dirname "$0")" output -raw zilch_mysql_user 2>/dev/null || echo "")

    if [ -n "$MYSQL_HOST" ] && [ -n "$MYSQL_USER" ]; then
        {
            echo ""
            echo "───────────────────────────────────────────────────────────────"
            echo "MySQL Database"
            echo "───────────────────────────────────────────────────────────────"
            echo "Host: $MYSQL_HOST"
            echo "Port: ${MYSQL_PORT:-3306}"
            echo "Database: $MYSQL_DB_NAME"
            echo "User: $MYSQL_USER"
            echo ""
            echo "Connection:"
            echo "  mysql -h $MYSQL_HOST -P ${MYSQL_PORT:-3306} -u $MYSQL_USER -p"
            echo ""
        } >> "$SUMMARY_FILE"

        echo -e "${BOLD}MySQL Database Ready${NC}"
        echo "  Host: $MYSQL_HOST"
        echo "  Port: ${MYSQL_PORT:-3306}"
        echo "  User: $MYSQL_USER"
        echo ""
    fi
fi

echo -e "${BOLD}Next Steps:${NC}"
echo -e "  ${CYAN}gcloud run deploy ${APP_NAME} --source .${NC}"
echo -e "  ${CYAN}gcloud run logs read ${APP_NAME} --region=${GCP_REGION}${NC}"
if [ "$ENABLE_FIREBASE_AUTH" == "true" ]; then
    echo -e "  ${CYAN}https://console.firebase.google.com/project/${PROJECT_ID}/auth${NC}"
fi
echo ""
echo -e "Always Free limits: ${CYAN}https://cloud.google.com/always-free${NC}"
