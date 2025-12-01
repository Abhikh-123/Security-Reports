#!/bin/bash
# download_all_pdfs.sh
# Description: Trigger and download PDFs for multiple projects from CodeScoring
# Usage: ./download_all_pdfs.sh /full/path/to/output_dir

# -------------------------
# Arguments
# -------------------------
OUTPUT_DIR="$1"
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="./reports/pdf"
fi

# -------------------------
# Configuration
# -------------------------
TOKEN="b50e1d4e33a85cd85f0025607613bdad6e967d19"
BASE_URL="http://192.168.4.149:8081"
MAX_ATTEMPTS=10
WAIT_TIME=10  # seconds between checks

# -------------------------
# Projects list
# -------------------------
declare -A projects=(
    ["icyberpro-its-internal-frontend"]=17
    ["icyberpro-its-internal-backend"]=18
    ["icyberpro-its-file-saving-server"]=19
    ["icyberpro-its-external-backend"]=20
    ["rapifuzzorg-rapifuzz-one"]=21
    ["Cyberkshetra-Frontend"]=22
    ["Cyberkshetra-Backend"]=23
    ["CRISISIM-frontend"]=27
    ["CRISISIM-backend"]=24
    ["icyberpro-django-cms-website"]=39
    ["threatensics-TI-UI-Portal"]=28
    ["threatensics-TI-Management-Toolkit"]=29
    ["threatensics-TI-Feed-Processing"]=30
    ["threatensics-labeller"]=31
    ["threatensics-collector"]=32
    ["threatensics-dbwriter"]=33
    ["threatensics-annotator"]=34
    ["threatensics-enricher"]=35
    ["threatensics-deduplicator"]=36
    ["CERTIn-Website"]=1
    ["CERTIn-Website-updated"]=4
)

# -------------------------
# Create output folder if not exists
# -------------------------
mkdir -p "$OUTPUT_DIR"

echo "=== Starting PDF download for all projects ==="

# -------------------------
# Loop through projects
# -------------------------
for project_name in "${!projects[@]}"; do
    project_id="${projects[$project_name]}"

    echo -e "\n========================================"
    echo "Processing Project: $project_name (ID: $project_id)"
    echo "========================================"

    # Trigger async PDF export
    export_response=$(curl -s -H "Authorization: Token $TOKEN" \
        "$BASE_URL/api/projects/$project_id/pdf/async_export/?content=summary&content=dependencies&content=licenses&content=vulnerabilities&content=policy_alerts&content=dependency_tree")

    media_id=$(echo "$export_response" | jq -r '.media_id')
    if [[ -z "$media_id" || "$media_id" == "null" ]]; then
        echo " Failed to trigger PDF export for $project_name"
        continue
    fi
    echo "✔ PDF export triggered: media_id=$media_id"

    # Wait until PDF is ready
    attempt=1
    while true; do
        content_length=$(curl -s -I -H "Authorization: Token $TOKEN" \
            "$BASE_URL/api/media/download/?media_id=$media_id" \
            | grep -i Content-Length | awk '{print $2}' | tr -d '\r')

        if [[ -n "$content_length" && "$content_length" -gt 10000 ]]; then
            echo " PDF ready (Content-Length: $content_length bytes)"
            break
        else
            echo " PDF not ready yet. Waiting $WAIT_TIME sec... (Attempt $attempt/$MAX_ATTEMPTS)"
            sleep $WAIT_TIME
            ((attempt++))
        fi

        if [[ $attempt -gt $MAX_ATTEMPTS ]]; then
            echo " PDF not ready after $MAX_ATTEMPTS attempts for $project_name"
            break
        fi
    done

    # Download the PDF directly into OUTPUT_DIR
    output_file="$OUTPUT_DIR/${project_name}_${project_id}.pdf"
    curl -s -o "$output_file" -H "Authorization: Token $TOKEN" \
        "$BASE_URL/api/media/download/?media_id=$media_id"

    # Verify file size
    file_size=$(stat -c%s "$output_file")
    if [[ "$file_size" -lt 10000 ]]; then
        echo "⚠ Warning: downloaded PDF looks too small ($file_size bytes)"
    else
        echo " PDF saved: $output_file"
    fi
done

echo -e "\n=== All PDF downloads completed ==="
