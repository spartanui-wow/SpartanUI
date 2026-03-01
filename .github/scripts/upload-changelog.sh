#!/bin/bash
# Upload Changelog to ProfileHub Website
#
# Extracts the current version's changelog section from CHANGELOG.md
# and POSTs it to the ProfileHub API for display on the website.
#
# Usage: ./upload-changelog.sh [changelog_file]
#   changelog_file: Path to CHANGELOG.md (default: CHANGELOG.md)
#
# Environment variables:
#   CHANGELOG_API_KEY: API key for ProfileHub changelog endpoint (required)
#   GITHUB_REF: GitHub ref (refs/tags/vX.Y.Z) for version detection

set -eE
trap 'echo "ERROR at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

CHANGELOG_FILE="${1:-CHANGELOG.md}"
API_URL="https://dev.spartanui.net/api/changelogs"

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------

if [ -z "$CHANGELOG_API_KEY" ]; then
    echo "ERROR: CHANGELOG_API_KEY not set" >&2
    exit 1
fi

if [ ! -f "$CHANGELOG_FILE" ]; then
    echo "ERROR: Changelog file not found: $CHANGELOG_FILE" >&2
    exit 1
fi

if [ -z "$GITHUB_REF" ] || [[ ! "$GITHUB_REF" =~ ^refs/tags/ ]]; then
    echo "SKIP: Not a tag push (GITHUB_REF=$GITHUB_REF), skipping upload" >&2
    exit 0
fi

# ---------------------------------------------------------------------------
# Detect addon name and CurseForge URL from .addon-release.yml
# ---------------------------------------------------------------------------

ADDON_NAME=""
CF_URL=""

if [ -f ".addon-release.yml" ]; then
    ADDON_NAME=$(grep "^addon-name:" .addon-release.yml | sed 's/^addon-name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | sed 's/^ *//;s/ *$//')
    CF_URL=$(grep "  curseforge:" .addon-release.yml | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | sed 's/^ *//;s/ *$//')
fi

if [ -z "$ADDON_NAME" ]; then
    # Fallback: use repo directory name
    ADDON_NAME=$(basename "$(pwd)")
fi

echo "Addon: $ADDON_NAME"

# ---------------------------------------------------------------------------
# Extract version from tag
# ---------------------------------------------------------------------------

TAG="${GITHUB_REF#refs/tags/}"
# Strip leading 'v' if present
VERSION="${TAG#v}"

echo "Version: $VERSION"

# ---------------------------------------------------------------------------
# Extract changelog content for this version
# ---------------------------------------------------------------------------

# The generate-changelog.sh produces sections like:
#   ## 🎯 This Release (AI summary)
#   ## Version X.Y.Z (Date)
#   ## 📅 Last Month Summary
#   ## Version A.B.C (Date)  (older versions)
#
# We want ONLY the Version X.Y.Z section's CONTENT (categorized commits).
# We skip:
#   - "This Release" section entirely (redundant AI summary)
#   - The "## Version X.Y.Z (date)" heading line itself (version/date shown by website)

extract_changelog() {
    local file="$1"
    local version="$2"
    local in_version_section=0
    local found_content=0
    local output=""

    while IFS= read -r line; do
        # Detect section headers
        if [[ "$line" =~ ^##\  ]]; then
            # Skip "This Release" section entirely
            if [[ "$line" =~ "This Release" ]]; then
                in_version_section=0
                continue
            fi

            # Our version's section - collect its content but NOT the heading
            if [[ "$line" =~ "Version ${version}" ]] || [[ "$line" =~ "Version v${version}" ]]; then
                in_version_section=1
                found_content=1
                # Intentionally do NOT add the heading line to output
                continue
            fi

            # Any other ## heading - stop collecting
            in_version_section=0
            continue
        fi

        # Collect lines within our version section
        if [ $in_version_section -eq 1 ]; then
            output+="$line"$'\n'
        fi
    done < "$file"

    # If we didn't find specific sections, grab everything up to "Last Month"
    if [ $found_content -eq 0 ]; then
        local in_content=0
        while IFS= read -r line; do
            if [[ "$line" =~ ^"# " ]] && [ $in_content -eq 0 ]; then
                in_content=1
                continue
            fi
            if [[ "$line" =~ "Last Month" ]] || [[ "$line" =~ ^"---"$ ]]; then
                break
            fi
            # Also skip "This Release" and "Version" headings in fallback
            if [[ "$line" =~ ^"## " ]] && ([[ "$line" =~ "This Release" ]] || [[ "$line" =~ ^"## Version " ]]); then
                continue
            fi
            if [ $in_content -eq 1 ]; then
                output+="$line"$'\n'
            fi
        done < "$file"
    fi

    echo "$output"
}

CHANGELOG_CONTENT=$(extract_changelog "$CHANGELOG_FILE" "$VERSION")

if [ -z "$(echo "$CHANGELOG_CONTENT" | tr -d '[:space:]')" ]; then
    echo "WARNING: No changelog content extracted for version $VERSION" >&2
    echo "Uploading minimal entry..." >&2
    CHANGELOG_CONTENT="Release $VERSION"
fi

echo "Extracted $(echo "$CHANGELOG_CONTENT" | wc -l) lines of changelog content"

# ---------------------------------------------------------------------------
# Build CurseForge download URL (if we have the base URL)
# ---------------------------------------------------------------------------

CF_DOWNLOAD_URL=""
if [ -n "$CF_URL" ]; then
    # CurseForge download URL pattern: /download/{fileId} - we don't have fileId
    # Just use the addon page URL; specific download link not available at this stage
    CF_DOWNLOAD_URL=""
fi

# ---------------------------------------------------------------------------
# POST to API
# ---------------------------------------------------------------------------

RELEASED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build JSON payload (using jq if available, otherwise manual escaping)
if command -v jq &>/dev/null; then
    PAYLOAD=$(jq -n \
        --arg addon_name "$ADDON_NAME" \
        --arg version "$VERSION" \
        --arg released_at "$RELEASED_AT" \
        --arg changelog "$CHANGELOG_CONTENT" \
        --arg curseforge_url "$CF_URL" \
        '{
            addon_name: $addon_name,
            version: $version,
            released_at: $released_at,
            changelog: $changelog,
            curseforge_url: (if $curseforge_url == "" then null else $curseforge_url end)
        }')
else
    # Manual JSON construction with escaping
    ESCAPED_CHANGELOG=$(echo "$CHANGELOG_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo "\"$VERSION release\"")
    PAYLOAD="{\"addon_name\":\"$ADDON_NAME\",\"version\":\"$VERSION\",\"released_at\":\"$RELEASED_AT\",\"changelog\":$ESCAPED_CHANGELOG"
    if [ -n "$CF_URL" ]; then
        PAYLOAD+=",\"curseforge_url\":\"$CF_URL\""
    fi
    PAYLOAD+="}"
fi

echo "Uploading changelog to $API_URL..."

HTTP_CODE=$(curl -s -o /tmp/changelog-response.txt -w "%{http_code}" \
    -X POST "$API_URL" \
    -H "Authorization: Bearer $CHANGELOG_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

RESPONSE=$(cat /tmp/changelog-response.txt)

if [ "$HTTP_CODE" -eq 201 ] || [ "$HTTP_CODE" -eq 200 ]; then
    echo "SUCCESS: Changelog uploaded (HTTP $HTTP_CODE)"
    echo "Response: $RESPONSE"
else
    echo "ERROR: Upload failed (HTTP $HTTP_CODE)" >&2
    echo "Response: $RESPONSE" >&2
    exit 1
fi
