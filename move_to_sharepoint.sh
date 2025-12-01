#!/bin/bash

############################################
# BASIC CONFIG
############################################

CLIENT_ID="216f8903-e743-4227-91df-ac0aefd84586"
CLIENT_SECRET="TC98Q~8th9SWwpH5zqBjVQuq0wbXFwYbgwbYVbg6"
TENANT_ID="6e5de1c4-b3c1-47c7-8e1f-aee7bbfbe640"

SITE_ID="rapifuzz.sharepoint.com,df72cfff-4b41-4ee3-8797-64723264dd93,570769dc-45ab-4482-aebb-2dc8c8107efc"
DRIVE_ID="b!_89y30FL406Hl2RyMmTdk9xpB1erRYJErrstyMgQfvy-4342L70EQaGFQsKlJesA"

ROOT_FOLDER="Reports"

PDF_FOLDER="${1:-/home/ubuntu/CodeScoring/reports/pdf}"
LINK_FILE="/home/ubuntu/CodeScoring/reports/uploaded_links.txt"

mkdir -p "$PDF_FOLDER"


############################################
# FIX OWNERSHIP SAFELY
############################################

if [[ $EUID -eq 0 ]]; then
    echo "🔧 Adjusting folder ownership..."
    chown ubuntu:ubuntu /home/ubuntu/CodeScoring/reports
    chown ubuntu:ubuntu /home/ubuntu/CodeScoring/reports/pdf
else
    echo "ℹ️ Skipping chown (run as root if needed)"
fi

> "$LINK_FILE"   # clean file


############################################
# GENERATE ACCESS TOKEN
############################################

generate_token() {
    echo "🔐 Generating access token..."
    RESPONSE=$(curl -s -X POST \
        -d "client_id=$CLIENT_ID" \
        -d "scope=https://graph.microsoft.com/.default" \
        -d "client_secret=$CLIENT_SECRET" \
        -d "grant_type=client_credentials" \
        "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token")

    ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r ".access_token")

    [[ "$ACCESS_TOKEN" == "null" || -z "$ACCESS_TOKEN" ]] && {
        echo "❌ ERROR: Failed to generate token"
        echo "$RESPONSE"
        exit 1
    }

    echo "✅ Token OK"
}

generate_token


############################################
# SHAREPOINT HELPERS
############################################

# Ensure folder exists
create_folder() {
    local path="$1"
    curl -s -X POST \
        "https://graph.microsoft.com/v1.0/sites/$SITE_ID/drives/$DRIVE_ID/root:/$path:/children" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"folder": {}, "@microsoft.graph.conflictBehavior": "replace"}' >/dev/null
}

# Timestamp filename
timestamp_name() {
    echo "$(basename "$1" .pdf)_$(date +%H%M%S).pdf"
}

# Detect project
detect_project() {
    local f="$1"

    if [[ "$f" == *"django-cms"* || "$f" == *"django_cms"* || "$f" == *"cms-website"* ]]; then
        echo "django_cms"
        return
    fi

    local proj=$(echo "$f" | cut -d'-' -f1)
    case "$proj" in
        icyberpro) echo "ITS" ;;
        rapifuzzorg) echo "rapifuzz" ;;
        *) echo "$proj" ;;
    esac
}

# Detect tool
detect_tool() {
    local tool=$(echo "$1" | cut -d'-' -f2 | tr A-Z a-z)

    case "$tool" in
        sonarqube|sonar) echo "sonarqube" ;;
        flom) echo "flom" ;;
        sbom) echo "sbom" ;;
        kics) echo "kics" ;;
        zap) echo "zap" ;;
        *) echo "CodeScoring" ;;
    esac
}


############################################
# MAIN PROCESSING
############################################

echo "📁 Scanning folder: $PDF_FOLDER"
PDF_FILES=("$PDF_FOLDER"/*.pdf)

if [[ ! -f "${PDF_FILES[0]}" ]]; then
    echo "⚠️ No PDF files found. Exiting."
    exit 0
fi

CURRENT_DATE=$(date +%Y-%m-%d)

# Ensure root folder exists
create_folder "$ROOT_FOLDER"

for FILE in "${PDF_FILES[@]}"; do
    BASENAME=$(basename "$FILE")

    PROJECT=$(detect_project "$BASENAME")
    TOOL=$(detect_tool "$BASENAME")

    TARGET_FOLDER="$ROOT_FOLDER/$PROJECT/$TOOL/$CURRENT_DATE"
    TIMESTAMPED=$(timestamp_name "$BASENAME")

    echo ""
    echo "---------------------------------------"
    echo "📌 Project: $PROJECT"
    echo "🔧 Tool:    $TOOL"
    echo "📆 Date:    $CURRENT_DATE"
    echo "📄 File:    $TIMESTAMPED"
    echo "---------------------------------------"

    # Create folder path
    create_folder "$ROOT_FOLDER/$PROJECT"
    create_folder "$ROOT_FOLDER/$PROJECT/$TOOL"
    create_folder "$TARGET_FOLDER"

    # Upload
    UPLOAD_PATH="$TARGET_FOLDER/$TIMESTAMPED"
    echo "⬆️ Uploading to SharePoint..."

    RESPONSE=$(curl -s -X PUT \
        "https://graph.microsoft.com/v1.0/sites/$SITE_ID/drives/$DRIVE_ID/root:/$UPLOAD_PATH:/content" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/pdf" \
        --data-binary @"$FILE")

    WEBURL=$(echo "$RESPONSE" | jq -r ".webUrl")

    if [[ -z "$WEBURL" || "$WEBURL" == "null" ]]; then
        echo "❌ Upload failed!"
        echo "$RESPONSE"
    else
        echo "✅ Uploaded: $WEBURL"
        echo "$WEBURL" >> "$LINK_FILE"
    fi
done

echo ""
echo "---------------------------------------"
echo "🎉 Upload Completed"
echo "🔗 Saved links at: $LINK_FILE"
echo "---------------------------------------"
