#!/bin/bash
# Discord Release Notification
#
# Sends a rich Discord embed notification for releases with:
# - Changelog content (truncated for Discord limits)
# - Download links (CurseForge, Wago, GitHub)
# - Support links (Discord, Issues, Roadmap)
# - Auto-detects addon name and reads per-addon config
#
# Usage: ./send-discord-notification.sh [changelog_file]
#
# Environment variables:
#   DISCORD_WEBHOOK_URL: Discord webhook URL (required)
#   GITHUB_REF: GitHub ref for version detection
#   ADDON_NAME: Override addon name (auto-detected if not set)

set -e

# === CONFIGURATION ===
CHANGELOG_FILE="${1:-CHANGELOG.md}"
MAX_DESC_LENGTH=4000  # Discord embed description limit is 4096

# Colors (decimal values for Discord embeds)
COLOR_STABLE=5763719   # Green (#57F287)
COLOR_BETA=16776960    # Yellow (#FFFF00)

# Logging
log_info() { echo "[INFO] $1" >&2; }
log_error() { echo "[ERROR] $1" >&2; }

# === ADDON NAME & CONFIG AUTO-DETECTION ===

# Load per-addon config from .addon-release.yml
load_addon_config() {
    local config=".addon-release.yml"
    if [ ! -f "$config" ]; then return; fi

    log_info "Loading config from $config..."
    [ -z "$ADDON_NAME" ] && ADDON_NAME=$(grep "^addon-name:" "$config" | sed 's/^addon-name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | sed 's/^ *//;s/ *$//')
    [ -z "$CF_URL" ] && CF_URL=$(grep "  curseforge:" "$config" | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | sed 's/^ *//;s/ *$//')
    [ -z "$WAGO_URL" ] && WAGO_URL=$(grep "  wago:" "$config" | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | sed 's/^ *//;s/ *$//')
    [ -z "$DISCORD_SUPPORT" ] && DISCORD_SUPPORT=$(grep "  discord:" "$config" | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | sed 's/^ *//;s/ *$//')
    [ -z "$GH_PROJECT" ] && GH_PROJECT=$(grep "  roadmap:" "$config" | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | sed 's/^ *//;s/ *$//')
}

# Auto-detect addon name from repo metadata
detect_addon_name() {
    if [ -n "$ADDON_NAME" ]; then return; fi

    load_addon_config
    if [ -n "$ADDON_NAME" ]; then return; fi

    if [ -f ".pkgmeta" ]; then
        ADDON_NAME=$(grep "^package-as:" .pkgmeta | sed 's/^package-as: *//' | sed 's/^ *//;s/ *$//')
    fi
    if [ -n "$ADDON_NAME" ]; then return; fi

    local toc_file=$(ls *.toc 2>/dev/null | head -1)
    if [ -n "$toc_file" ]; then
        ADDON_NAME=$(basename "$toc_file" .toc)
    fi
    if [ -n "$ADDON_NAME" ]; then return; fi

    ADDON_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
}

detect_addon_name
load_addon_config

# Project URLs (from config or defaults using GITHUB_REPOSITORY)
GH_RELEASES="${GH_RELEASES:-https://github.com/${GITHUB_REPOSITORY}/releases}"
GH_ISSUES="${GH_ISSUES:-https://github.com/${GITHUB_REPOSITORY}/issues}"

log_info "Addon name: $ADDON_NAME"

# === HELPER FUNCTIONS ===

# Escape string for JSON
json_escape() {
    local input="$1"
    python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))" <<< "$input"
}

# === VERSION DETECTION ===
detect_version() {
    if [[ "$GITHUB_REF" =~ ^refs/tags/ ]]; then
        VERSION=$(echo "$GITHUB_REF" | sed 's|refs/tags/||')
        # Check if this is a beta release (e.g., 1.2.3-Beta1, 1.2.3-beta2)
        if [[ "$VERSION" =~ -[Bb]eta ]]; then
            IS_BETA=true
            log_info "Detected beta release: $VERSION"
        else
            IS_BETA=false
            log_info "Detected stable release: $VERSION"
        fi
    else
        VERSION="unknown"
        IS_BETA=false
        log_info "Warning: Not a tag push, unexpected ref: $GITHUB_REF"
    fi
}

# === BUILD JSON PAYLOAD ===
build_payload() {
    local description=$(build_description)
    local desc_json=$(json_escape "$description")

    # Determine color and title based on release type
    local color=$COLOR_STABLE
    local title="$ADDON_NAME $VERSION Released!"

    if [ "$IS_BETA" = true ]; then
        color=$COLOR_BETA
        title="$ADDON_NAME $VERSION (Beta)"
    fi

    # Determine title URL (prefer CurseForge, fallback to GitHub releases)
    local title_url="${CF_URL:-$GH_RELEASES}"

    # Get current timestamp
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

    # Build download field value
    local download_value=""
    if [ -n "$CF_URL" ]; then
        download_value="[CurseForge]($CF_URL) (Recommended)"
    fi
    if [ -n "$WAGO_URL" ]; then
        [ -n "$download_value" ] && download_value="$download_value\\n"
        download_value="${download_value}[Wago Addons]($WAGO_URL)"
    fi
    [ -n "$download_value" ] && download_value="$download_value\\n"
    download_value="${download_value}[GitHub Releases]($GH_RELEASES)"

    # Build support field value
    local support_value=""
    if [ -n "$DISCORD_SUPPORT" ]; then
        support_value="[Discord]($DISCORD_SUPPORT)"
    fi
    [ -n "$support_value" ] && support_value="$support_value\\n"
    support_value="${support_value}[Report Issues]($GH_ISSUES)"
    if [ -n "$GH_PROJECT" ]; then
        support_value="$support_value\\n[Roadmap]($GH_PROJECT)"
    fi

    # Build the JSON payload
    cat << EOJSON
{
  "embeds": [{
    "title": "$title",
    "url": "$title_url",
    "description": $desc_json,
    "color": $color,
    "fields": [
      {
        "name": "Download",
        "value": "$download_value",
        "inline": true
      },
      {
        "name": "Support",
        "value": "$support_value",
        "inline": true
      }
    ],
    "footer": {
      "text": "$ADDON_NAME - World of Warcraft"
    },
    "timestamp": "$timestamp"
  }]
}
EOJSON
}

# === CHANGELOG PROCESSING ===

# Build the description for the Discord embed (using Python for proper UTF-8 handling)
build_description() {
    python3 << PYEOF
import sys
import re
import os

# Read the changelog file with proper encoding
with open("$CHANGELOG_FILE", 'r', encoding='utf-8') as f:
    content = f.read()

# Emoji replacements
replacements = {
    '\U0001F3AF': ':dart:',      # target
    '\U0001F680': ':rocket:',    # rocket
    '\U0001F41B': ':bug:',       # bug
    '\U0001F4DD': ':memo:',      # memo
    '\u26A0\uFE0F': ':warning:', # warning with variation selector
    '\u26A0': ':warning:',       # warning without variation selector
    '\U0001F4DA': ':books:',     # books
    '\U0001F527': ':wrench:',    # wrench
    '\u26A1': ':zap:',           # zap
    '\U0001F4C5': ':calendar:',  # calendar
}

lines = content.split('\n')
description_parts = []

# 1. Extract AI summary from "This Release" section
in_this_release = False
ai_summary = []
for line in lines:
    if '## ' in line and ('This Release' in line or 'Alpha Build' in line):
        in_this_release = True
        continue
    if in_this_release and line.startswith('## ') and not line.startswith('### '):
        break
    if in_this_release and line.strip() and not line.startswith('#'):
        ai_summary.append(line)

if ai_summary:
    description_parts.append('\n'.join(ai_summary).strip())

# 2. Extract the version section matching VERSION
version = "$VERSION"
in_version = False
version_content = []
for line in lines:
    # Match "## Version X.X.X" header
    if line.startswith('## Version') and version in line:
        in_version = True
        continue
    # Stop at next ## section (but not ###)
    if in_version and line.startswith('## ') and not line.startswith('### '):
        break
    if in_version:
        version_content.append(line)

if version_content:
    # Join and clean up excessive blank lines
    version_text = '\n'.join(version_content).strip()
    # Remove more than 2 consecutive newlines
    version_text = re.sub(r'\n{3,}', '\n\n', version_text)
    description_parts.append(version_text)

# Combine summary + changelog
description = '\n\n'.join(description_parts)

# Apply emoji replacements
for emoji, shortcode in replacements.items():
    description = description.replace(emoji, shortcode)

# Truncate if needed
max_len = $MAX_DESC_LENGTH
gh_repo = os.environ.get('GITHUB_REPOSITORY', '')
release_url = f"https://github.com/{gh_repo}/releases/tag/$VERSION" if gh_repo else ""

if len(description) > max_len:
    description = description[:max_len]
    # Find last newline for clean break
    last_nl = description.rfind('\n')
    if last_nl > max_len // 2:
        description = description[:last_nl]

    # Count remaining items we're cutting off
    full_lines = content.split('\n')
    truncated_lines = description.split('\n')
    # Count bullet points (lines starting with -)
    full_count = sum(1 for l in full_lines if l.strip().startswith('-'))
    shown_count = sum(1 for l in truncated_lines if l.strip().startswith('-'))
    remaining = full_count - shown_count

    if remaining > 0 and release_url:
        description += f'\n\n### [(+{remaining} more changes...)]({release_url})'
    elif release_url:
        description += f'\n\n### [View full changelog]({release_url})'

# Default message if empty
if not description.strip():
    description = "A new version has been released! Check the changelog for details."

print(description)
PYEOF
}

# === SEND WEBHOOK ===
send_notification() {
    local payload="$1"

    if [ -z "$DISCORD_WEBHOOK_URL" ]; then
        log_error "DISCORD_WEBHOOK_URL not set!"
        exit 1
    fi

    log_info "Sending Discord notification..."

    # Send the webhook request
    local response=$(curl -s -w "\n%{http_code}" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$DISCORD_WEBHOOK_URL")

    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | head -n-1)

    if [ "$http_code" != "200" ] && [ "$http_code" != "204" ]; then
        log_error "Discord webhook failed with HTTP $http_code"
        log_error "Response: $response_body"
        exit 1
    fi

    log_info "Discord notification sent successfully!"
}

# === MAIN ===
main() {
    log_info "Starting Discord release notification..."

    # Detect version from GitHub ref
    detect_version

    # Verify changelog exists
    if [ ! -f "$CHANGELOG_FILE" ]; then
        log_error "Changelog file not found: $CHANGELOG_FILE"
        exit 1
    fi

    log_info "Reading changelog from: $CHANGELOG_FILE"

    # Build and send the notification
    local payload=$(build_payload)

    # Debug: show payload (optional, remove in production)
    log_info "Payload preview:"
    echo "$payload" | head -30 >&2

    send_notification "$payload"

    log_info "Done!"
}

main "$@"
