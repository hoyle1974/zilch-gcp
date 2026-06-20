#!/bin/bash
# Shared functions for deploy.sh and teardown.sh
# Keeps both scripts synchronized on configuration loading, validation, and terraform setup

# Color definitions (ANSI-C quoting for proper interpretation)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# Check for required tools and provide guidance
check_required_tools() {
    local IN_CLOUD_SHELL=false
    if [ -n "$CLOUD_SHELL" ]; then
        IN_CLOUD_SHELL=true
    fi

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
        return 1
    fi

    if [ -n "$CLOUD_SHELL" ]; then
        echo -e "${GREEN}✓${NC} Running in Google Cloud Shell"
    fi
    echo -e "${GREEN}✓${NC} Required tools available"
    return 0
}

# Load configuration from .zilch.config
load_config() {
    PROJECT_ID=""
    APP_NAME=""
    GCP_REGION="us-central1"
    GCP_BILLING_ACCOUNT_ID=""

    if [ -f ".zilch.config" ]; then
        echo -e "${BLUE}→${NC} Loading ${CYAN}.zilch.config${NC}"

        while IFS='=' read -r key value; do
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # Remove surrounding quotes (handle multiple layers)
            while [[ "$value" == \"* ]] && [[ "$value" == *\" ]]; do
                value="${value#\"}"
                value="${value%\"}"
            done

            case "$key" in
                gcp_project_id) PROJECT_ID="$value" ;;
                app_name) APP_NAME="$value" ;;
                gcp_region) GCP_REGION="$value" ;;
                gcp_billing_account_id) GCP_BILLING_ACCOUNT_ID="$value" ;;
            esac
        done < .zilch.config

        echo -e "${GREEN}✓${NC} Loaded"
    fi
}

# Validate GCP authentication
validate_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q '@'; then
        echo -e "${RED}✗ No active gcloud authentication${NC}"
        echo ""
        echo "  gcloud auth login"
        return 1
    fi

    CURRENT_USER=$(gcloud config get-value account)
    echo -e "${GREEN}✓${NC} Authenticated as ${CYAN}${CURRENT_USER}${NC}"
    return 0
}

# Validate project exists and user has access
validate_project() {
    if [ -z "$PROJECT_ID" ]; then
        read -p "${BLUE}GCP Project ID${NC}: " PROJECT_ID
    fi

    if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}✗ Project ID required${NC}"
        return 1
    fi

    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        echo -e "${RED}✗ Project ${CYAN}${PROJECT_ID}${RED} not found or no access${NC}"
        return 1
    fi

    echo -e "${GREEN}✓${NC} Project ${CYAN}${PROJECT_ID}${NC}"
    return 0
}

# Set GCP project context
set_gcp_context() {
    if ! gcloud config set project "$PROJECT_ID" --quiet; then
        echo -e "${YELLOW}⚠${NC} Warning: Could not set gcloud project context."
    fi
}

# Get terraform variables as command-line arguments
get_terraform_vars() {
    echo "-var=\"gcp_project_id=${PROJECT_ID}\" \
-var=\"app_name=${APP_NAME}\" \
-var=\"gcp_region=${GCP_REGION}\" \
-var=\"github_owner=${GITHUB_OWNER:-}\" \
-var=\"github_repo=${GITHUB_REPO:-}\" \
-var=\"gcp_billing_account_id=${GCP_BILLING_ACCOUNT_ID:-}\""
}

# Export terraform variables for terraform commands
export_terraform_vars() {
    export GOOGLE_CLOUD_QUOTA_PROJECT="${PROJECT_ID}"
}
