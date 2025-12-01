#!/bin/bash

# CONFIG

CLIENT_ID="216f8903-e743-4227-91df-ac0aefd84586"
CLIENT_SECRET="TC98Q~8th9SWwpH5zqBjVQuq0wbXFwYbgwbYVbg6"
TENANT_ID="6e5de1c4-b3c1-47c7-8e1f-aee7bbfbe640"

SITE_ID="rapifuzz.sharepoint.com,df72cfff-4b41-4ee3-8797-64723264dd93,570769dc-45ab-4482-aebb-2dc8c8107efc"
DRIVE_ID="b!_89y30FL406Hl2RyMmTdk9xpB1erRYJErrstyMgQfvy-4342L70EQaGFQsKlJesA"

ROOT_FOLDER="Reports"
PDF_FOLDER="${1:-/home/ubuntu/CodeScoring/reports/pdf}"
LINK_FILE="/home/ubuntu/CodeScoring/reports/uploaded_links.txt"

mkdir -p "$PDF_FOLDER"
rm -f "$LINK_FILE"

# TOKEN

generate_token() {
    echo " Generating access token..."

    RESPONSE=$(curl -s -X POST \
        -d "client_id=$CLIENT_ID" \
        -d "scope=https://graph.microsoft.com/.default" \
        -d "client_secret=$CLIENT_SECRET" \
        -d "grant_type=client_credentials" \
        "https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token")

    ACCESS_TOKEN=$(echo "$RESPONSE" | jq -r ".access_token")

    if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
        echo " Token generation failed!"
        echo "$RESPONSE"
        exit 1
    fi

    echo "✅ Token OK"
}

generate_token

###############################################
# SIMPLE FOLDER CREATION
###############################################
create_folder() {
    local path="$1"

    echo " Ensuring folder exists: $path"

    RESPONSE=$(curl -s -X POST \
        "https://graph.microsoft.com/v1.0/sites/$SITE_ID/drives/$DRIVE_ID/root:/$path:/children" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"folder": {}, "@microsoft.graph.conflictBehavior": "replace"}')

    # ignore errors like "already exists"
}


# TIMESTAMPING

timestamp_name() {
    local base=$(basename "$1" .pdf)
    local ts=$(date +%H%M%S)
    echo "${base}_${ts}.pdf"
}


# CREATE ROOT REPORTS FOLDER

create_folder "$ROOT_FOLDER"


# PROCESS PDF FILES

echo " Looking for PDF files in: $PDF_FOLDER"
PDF_COUNT=$(find "$PDF_FOLDER" -name "*.pdf" | wc -l)

echo " Found: $PDF_COUNT files"

CURRENT_DATE=$(date +%Y-%m-%d)

for FILE in "$PDF_FOLDER"/*.pdf; do
    [[ -f "$FILE" ]] || continue

    BASENAME=$(basename "$FILE")

    # Extract project + tool
    PROJECT=$(echo "$BASENAME" | cut -d'-' -f1)
    TOOL=$(echo "$BASENAME" | cut -d'-' -f2 | tr '[:upper:]' '[:lower:]')

    case "$TOOL" in
        sonarqube|sonar) TOOL="sonarqube" ;;
        flom) TOOL="flom" ;;
        sbom) TOOL="sbom" ;;
        kics) TOOL="kics" ;;
        zap) TOOL="zap" ;;
        *) TOOL="CodeScoring" ;;
    esac

    TARGET_FOLDER="$ROOT_FOLDER/$PROJECT/$TOOL/$CURRENT_DATE"
    TIMESTAMPED=$(timestamp_name "$BASENAME")
    UPLOAD_PATH="$TARGET_FOLDER/$TIMESTAMPED"

    echo ""
    echo "---------------------------------------"
    echo " PROJECT: $PROJECT"
    echo " TOOL: $TOOL"
    echo " DATE FOLDER: $CURRENT_DATE"
    echo " File: $BASENAME → $TIMESTAMPED"
    echo "---------------------------------------"

    # Create folders
    create_folder "$ROOT_FOLDER/$PROJECT"
    create_folder "$ROOT_FOLDER/$PROJECT/$TOOL"
    create_folder "$TARGET_FOLDER"

    # Upload
    echo " Uploading file..."
    RESPONSE=$(curl -s -X PUT \
        "https://graph.microsoft.com/v1.0/sites/$SITE_ID/drives/$DRIVE_ID/root:/$UPLOAD_PATH:/content" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/pdf" \
        --data-binary @"$FILE")

    WEBURL=$(echo "$RESPONSE" | jq -r '.webUrl')

    if [[ -z "$WEBURL" || "$WEBURL" == "null" ]]; then
        echo  Upload failed!"
        echo "$RESPONSE"
        continue
    fi

    echo " Uploaded: $WEBURL"

    # Save link for Jenkins Teams message
    echo "$WEBURL" >> "$LINK_FILE"
done

echo ""
echo "---------------------------------------"
echo " Upload Completed"
echo " Saved file links: $LINK_FILE"
echo "---------------------------------------"
