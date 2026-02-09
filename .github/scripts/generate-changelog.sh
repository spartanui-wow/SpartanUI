#!/bin/bash
# Smart Changelog Generator with AI Summaries
#
# This script generates an intelligent changelog that:
# - Detects alpha builds (unreleased commits on master)
# - Shows releases from the last month
# - Categorizes commits by type (Features, Fixes, Changes, etc.)
# - Generates two AI summaries: monthly overview and current release
# - Auto-detects addon name and reads per-addon config
#
# Usage: ./generate-changelog.sh [output_file]
#   output_file: Path to output changelog file (default: CHANGELOG.md)
#
# Environment variables:
#   GEMINI_API_KEY: Google Gemini API key for AI summaries
#   AI_PROVIDER: "gemini" or "openai" (default: gemini)
#   GITHUB_REF: GitHub ref (refs/tags/vX.Y.Z for tags, refs/heads/master for branch)
#   ADDON_NAME: Override addon name (auto-detected if not set)
#   ADDON_DESCRIPTION: Short description for AI prompts (optional)

# Configuration
OUTPUT_FILE="${1:-CHANGELOG.md}"
AI_PROVIDER="${AI_PROVIDER:-gemini}"
MONTH_AGO_SECONDS=$((30 * 24 * 60 * 60)) # 30 days in seconds

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions (output to stderr)
log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $1" >&2; }

# === ADDON NAME & CONFIG AUTO-DETECTION ===

# Load per-addon config from .addon-release.yml
load_addon_config() {
    local config=".addon-release.yml"
    if [ ! -f "$config" ]; then return; fi

    log_info "Loading config from $config..."
    [ -z "$ADDON_NAME" ] && ADDON_NAME=$(grep "^addon-name:" "$config" | sed 's/^addon-name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | sed 's/^ *//;s/ *$//')
    [ -z "$ADDON_DESCRIPTION" ] && ADDON_DESCRIPTION=$(grep "^addon-description:" "$config" | sed 's/^addon-description: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | sed 's/^ *//;s/ *$//')
    [ -z "$CF_URL" ] && CF_URL=$(grep "  curseforge:" "$config" | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | sed 's/^ *//;s/ *$//')
    [ -z "$WAGO_URL" ] && WAGO_URL=$(grep "  wago:" "$config" | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | sed 's/^ *//;s/ *$//')
    [ -z "$DISCORD_SUPPORT_URL" ] && DISCORD_SUPPORT_URL=$(grep "  discord:" "$config" | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | sed 's/^ *//;s/ *$//')
    [ -z "$ROADMAP_URL" ] && ROADMAP_URL=$(grep "  roadmap:" "$config" | sed 's/.*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | sed 's/^ *//;s/ *$//')
}

# Auto-detect addon name from repo metadata
detect_addon_name() {
    # Already set via env var — highest priority
    if [ -n "$ADDON_NAME" ]; then return; fi

    # Try .addon-release.yml
    load_addon_config
    if [ -n "$ADDON_NAME" ]; then return; fi

    # Try .pkgmeta package-as field
    if [ -f ".pkgmeta" ]; then
        ADDON_NAME=$(grep "^package-as:" .pkgmeta | sed 's/^package-as: *//' | sed 's/^ *//;s/ *$//')
    fi
    if [ -n "$ADDON_NAME" ]; then return; fi

    # Try first .toc filename
    local toc_file=$(ls *.toc 2>/dev/null | head -1)
    if [ -n "$toc_file" ]; then
        ADDON_NAME=$(basename "$toc_file" .toc)
    fi
    if [ -n "$ADDON_NAME" ]; then return; fi

    # Fallback to git repo directory name
    ADDON_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
}

detect_addon_name

# Load config if not already loaded (detect_addon_name may have loaded it)
load_addon_config

# Default GitHub issues URL from GITHUB_REPOSITORY env (auto-provided by GitHub Actions)
if [ -z "$GH_ISSUES_URL" ] && [ -n "$GITHUB_REPOSITORY" ]; then
    GH_ISSUES_URL="https://github.com/${GITHUB_REPOSITORY}/issues"
fi

log_info "Addon name: $ADDON_NAME"
[ -n "$ADDON_DESCRIPTION" ] && log_info "Description: $ADDON_DESCRIPTION"

# JSON escape function
json_escape() {
    local input="$1"
    if command -v jq &> /dev/null; then
        echo "$input" | jq -Rs .
    else
        python -c "import json, sys; print(json.dumps(sys.stdin.read()))" <<< "$input"
    fi
}

# Function to categorize a commit message
categorize_commit() {
    local msg="$1"
    # Convert to lowercase for case-insensitive matching
    local msg_lower=$(echo "$msg" | tr '[:upper:]' '[:lower:]')

    # Check for conventional commit patterns first (highest priority)
    if [[ "$msg" =~ ^(feat|feature|enhancement)[:\ ] ]] || [[ "$msg" =~ ^NEW: ]]; then
        echo "feature"
        return
    elif [[ "$msg" =~ ^(fix|bug|bugfix)[:\ ] ]]; then
        echo "fix"
        return
    elif [[ "$msg" =~ ^(chore|refactor|style|perf)[:\ ] ]]; then
        echo "change"
        return
    elif [[ "$msg" =~ ^(docs|documentation)[:\ ] ]]; then
        echo "docs"
        return
    elif [[ "$msg" =~ ^(breaking|BREAKING)[:\ ] ]]; then
        echo "breaking"
        return
    fi

    # Check for natural language patterns at the start of the message
    # Fix patterns: "Fix", "Fixes", "Fixed", "Fixing"
    if [[ "$msg_lower" =~ ^fix(es|ed|ing)?[[:space:]:\-] ]]; then
        echo "fix"
        return
    fi

    # Feature/Add patterns: "Add", "Adds", "Added", "Adding", "New", "Implement", "Implements"
    if [[ "$msg_lower" =~ ^(add(s|ed|ing)?|new|implement(s|ed|ing)?)[[:space:]:\-] ]]; then
        echo "feature"
        return
    fi

    # Improvement patterns: "Improve", "Improves", "Improved", "Improving", "Enhance", "Enhances", "Update", "Updates"
    if [[ "$msg_lower" =~ ^(improve(s|d|ing)?|enhance(s|d|ing)?|update(s|d|ing)?)[[:space:]:\-] ]]; then
        echo "change"
        return
    fi

    # Refactor patterns: "Refactor", "Refactors", "Refactored", "Refactoring", "Cleanup", "Clean up"
    if [[ "$msg_lower" =~ ^(refactor(s|ed|ing)?|cleanup|clean[[:space:]]up|reorganize(s|d)?|simplif(y|ies|ied))[[:space:]:\-] ]]; then
        echo "change"
        return
    fi

    # Migration patterns: "Migrate", "Migrates", "Migrated", "Move", "Moves", "Moved"
    if [[ "$msg_lower" =~ ^(migrate(s|d)?|move(s|d)?)[[:space:]:\-] ]]; then
        echo "change"
        return
    fi

    # Remove/Delete patterns: "Remove", "Removes", "Removed", "Delete", "Deletes", "Deleted"
    if [[ "$msg_lower" =~ ^(remove(s|d)?|delete(s|d)?)[[:space:]:\-] ]]; then
        echo "change"
        return
    fi

    # Integration patterns: "Integrate", "Integrates", "Integrated"
    if [[ "$msg_lower" =~ ^integrate(s|d)?[[:space:]:\-] ]]; then
        echo "feature"
        return
    fi

    # Monitor/Track patterns: "Monitor", "Track", "Respect"
    if [[ "$msg_lower" =~ ^(monitor|track|respect)[[:space:]:\-] ]]; then
        echo "feature"
        return
    fi

    # Silence/Suppress patterns (usually fixes or improvements)
    if [[ "$msg_lower" =~ ^(silence|suppress)[[:space:]:\-] ]]; then
        echo "fix"
        return
    fi

    # Protect/Ensure/Guard patterns (usually fixes)
    if [[ "$msg_lower" =~ ^(protect(s)?|ensure(s)?|guard(s)?)[[:space:]:\-] ]]; then
        echo "fix"
        return
    fi

    # Register patterns (usually features)
    if [[ "$msg_lower" =~ ^register(s|ed)?[[:space:]:\-] ]]; then
        echo "feature"
        return
    fi

    # Attempt patterns (usually fixes or experimental changes)
    if [[ "$msg_lower" =~ ^attempt[[:space:]:\-] ]]; then
        echo "fix"
        return
    fi

    # Switch/Replace/Bundle patterns (changes)
    if [[ "$msg_lower" =~ ^(switch|replace(s|d)?|bundle(s|d)?)[[:space:]:\-] ]]; then
        echo "change"
        return
    fi

    # Module-prefixed commits (e.g., "Minimap: Add feature", "UnitFrames: Fix bug")
    # These are typically changes/improvements to specific modules
    if [[ "$msg" =~ ^[A-Z][a-zA-Z]+:[[:space:]] ]]; then
        # Extract what comes after the module prefix to determine type
        local after_prefix=$(echo "$msg" | sed -E 's/^[A-Z][a-zA-Z]+:[[:space:]]//')
        local after_lower=$(echo "$after_prefix" | tr '[:upper:]' '[:lower:]')

        if [[ "$after_lower" =~ ^(fix|fixes|fixed|fixing) ]]; then
            echo "fix"
            return
        elif [[ "$after_lower" =~ ^(add|adds|added|adding|new|implement) ]]; then
            echo "feature"
            return
        else
            echo "change"
            return
        fi
    fi

    # "Defines" pattern (usually compatibility/feature additions)
    if [[ "$msg_lower" =~ ^define(s|d)?[[:space:]:\-] ]]; then
        echo "feature"
        return
    fi

    # Default to other
    echo "other"
}

# Function to clean commit message (remove prefixes)
clean_commit_message() {
    local msg="$1"
    # Remove conventional commit prefixes (case-insensitive)
    msg=$(echo "$msg" | sed -E 's/^(feat|feature|fix|bug|bugfix|chore|refactor|style|perf|docs|documentation|breaking|BREAKING|NEW|enhancement|new):[ ]+//i')

    # Remove natural language verb prefixes - order matters: longer forms first!
    # Use word boundary patterns to match whole words only
    msg=$(echo "$msg" | sed -E 's/^(Fixes|Fixed|Fixing)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^Fix[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Adds|Added|Adding)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^Add[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Implements|Implemented|Implementing)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^Implement[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Improves|Improved|Improving)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^Improve[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Enhances|Enhanced|Enhancing)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^Enhance[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Updates|Updated|Updating)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^Update[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Refactors|Refactored|Refactoring)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^Refactor[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Cleanup|Clean up)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Reorganizes|Reorganized|Reorganize)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Simplifies|Simplified|Simplify)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Migrates|Migrated|Migrate)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Moves|Moved|Move)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Removes|Removed|Remove)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Deletes|Deleted|Delete)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Integrates|Integrated|Integrate)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Monitor|Track|Respect)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Silence|Suppress)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Protects|Protect)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Ensures|Ensure)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Guards|Guard)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Registers|Registered|Register)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^Attempt[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Defines|Defined|Define)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Switches|Switched|Switch)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Replaces|Replaced|Replace)[[:space:]:\-]+//i')
    msg=$(echo "$msg" | sed -E 's/^(Bundles|Bundled|Bundle)[[:space:]:\-]+//i')

    # Capitalize first letter
    msg=$(echo "$msg" | sed -E 's/^(.)/\U\1/')
    echo "$msg"
}

# Function to get commit subjects only (for changelog display)
get_commits_subjects() {
    local range="$1"
    local output_file="$2"

    if [ -n "$range" ]; then
        git log "$range" --pretty=format:"%s" --no-merges > "$output_file" 2>/dev/null
    fi
}

# Function to get commits with full body (for AI summary context)
# Outputs formatted text with subject and body for better AI understanding
get_commits_with_body_for_ai() {
    local range="$1"

    # Use a unique delimiter that won't appear in commit messages
    local COMMIT_DELIM="<<<COMMIT_END>>>"
    local BODY_DELIM="<<<BODY>>>"

    if [ -n "$range" ]; then
        git log "$range" --pretty=format:"%s${BODY_DELIM}%b${COMMIT_DELIM}" --no-merges 2>/dev/null | \
        python3 -c "
import sys

COMMIT_DELIM = '<<<COMMIT_END>>>'
BODY_DELIM = '<<<BODY>>>'

content = sys.stdin.read()
commits = content.split(COMMIT_DELIM)

for commit in commits:
    commit = commit.strip()
    if not commit:
        continue

    if BODY_DELIM in commit:
        subject, body = commit.split(BODY_DELIM, 1)
    else:
        subject = commit
        body = ''

    subject = subject.strip()
    body = body.strip()

    if not subject:
        continue

    # Output subject
    print(f'- {subject}')

    # If body exists, include it indented for context
    if body:
        body_lines = [l.strip() for l in body.split('\n') if l.strip()]
        for line in body_lines[:5]:  # Max 5 lines from body
            print(f'  {line}')
        print()  # Empty line between commits
"
    fi
}

# Function to call Gemini Flash API
generate_ai_summary_gemini() {
    local commits_text="$1"
    local prompt_type="$2" # "month" or "release"
    local api_key="$GEMINI_API_KEY"

    if [ -z "$api_key" ]; then
        log_warn "GEMINI_API_KEY not set, skipping AI summary"
        return 1
    fi

    # Build addon context string
    local addon_context="a World of Warcraft addon called $ADDON_NAME"
    if [ -n "$ADDON_DESCRIPTION" ]; then
        addon_context="a World of Warcraft addon called $ADDON_NAME ($ADDON_DESCRIPTION)"
    fi

    # Create prompt based on type
    if [ "$prompt_type" = "month" ]; then
        local prompt="You are writing release notes for $addon_context. Summarize the following changelog from the last month in 2-3 short sentences. Be direct and get straight to the details - no greetings, no filler phrases like 'Hey everyone' or 'This update brings'. Just state what was added, fixed, or changed. Write for a 6th grade reading level.

Changes from last month:
$commits_text"
    else
        local prompt="You are writing release notes for $addon_context. Summarize this specific release in 1-2 short sentences. Be direct and get straight to the details - no greetings, no filler phrases like 'Hey everyone' or 'This update brings'. Just state what was added, fixed, or changed. Write for a 6th grade reading level.

Changes in this release:
$commits_text"
    fi

    prompt=$(json_escape "$prompt")
    local json_request="{\"contents\":[{\"parts\":[{\"text\":$prompt}]}]}"
    local temp_request=$(mktemp)
    echo "$json_request" > "$temp_request"

    log_info "Calling Gemini API for $prompt_type summary..."
    local response=$(curl -s -w "\n%{http_code}" --max-time 30 \
        -H "Content-Type: application/json" \
        -d "@$temp_request" \
        "https://generativelanguage.googleapis.com/v1/models/gemini-2.5-flash:generateContent?key=$api_key")

    rm -f "$temp_request"

    local http_code=$(echo "$response" | tail -n1)
    local response_body=$(echo "$response" | head -n-1)

    if [ "$http_code" != "200" ]; then
        log_error "Gemini API returned HTTP $http_code"
        return 1
    fi

    local summary=$(python -c "
import json, sys
try:
    data = json.loads(sys.stdin.read())
    print(data['candidates'][0]['content']['parts'][0]['text'])
except (KeyError, IndexError, json.JSONDecodeError):
    pass
" <<< "$response_body" 2>/dev/null)

    if [ -z "$summary" ]; then
        log_error "Failed to parse Gemini API response"
        return 1
    fi

    echo "$summary"
    return 0
}

# Function to generate AI summary
generate_ai_summary() {
    local commits_text="$1"
    local prompt_type="$2"

    if [ "$AI_PROVIDER" = "openai" ]; then
        log_error "OpenAI not yet implemented"
        return 1
    else
        generate_ai_summary_gemini "$commits_text" "$prompt_type"
    fi
}

# Function to format categorized commits
format_categorized_commits() {
    local commit_file="$1"

    # Arrays for each category
    local -a features=() fixes=() changes=() docs=() breaking=() others=()

    # Read and categorize commits
    while IFS= read -r line || [ -n "$line" ]; do  # Handle files without trailing newline
        if [ -z "$line" ]; then continue; fi

        local category=$(categorize_commit "$line")
        local clean_msg=$(clean_commit_message "$line")

        case "$category" in
            feature) features+=("$clean_msg") ;;
            fix) fixes+=("$clean_msg") ;;
            change) changes+=("$clean_msg") ;;
            docs) docs+=("$clean_msg") ;;
            breaking) breaking+=("$clean_msg") ;;
            *) others+=("$clean_msg") ;;
        esac
    done < "$commit_file"

    # Output categorized commits directly (not building a string)
    if [ ${#breaking[@]} -gt 0 ]; then
        echo "### ⚠️ Breaking Changes"
        for item in "${breaking[@]}"; do
            echo "- $item"
        done
        echo ""
    fi

    if [ ${#features[@]} -gt 0 ]; then
        echo "### 🚀 Features"
        for item in "${features[@]}"; do
            echo "- $item"
        done
        echo ""
    fi

    if [ ${#fixes[@]} -gt 0 ]; then
        echo "### 🐛 Fixes"
        for item in "${fixes[@]}"; do
            echo "- $item"
        done
        echo ""
    fi

    if [ ${#changes[@]} -gt 0 ]; then
        echo "### 📝 Changes"
        for item in "${changes[@]}"; do
            echo "- $item"
        done
        echo ""
    fi

    if [ ${#docs[@]} -gt 0 ]; then
        echo "### 📚 Documentation"
        for item in "${docs[@]}"; do
            echo "- $item"
        done
        echo ""
    fi

    if [ ${#others[@]} -gt 0 ]; then
        echo "### 🔧 Other"
        for item in "${others[@]}"; do
            echo "- $item"
        done
        echo ""
    fi
}

# Main script execution
log_info "Generating smart changelog for $ADDON_NAME..."
log_info "Output file: $OUTPUT_FILE"

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    log_error "Not in a git repository!"
    exit 1
fi

# Detect if this is a tag release or alpha build
IS_TAG=false
CURRENT_TAG=""
if [[ "$GITHUB_REF" =~ ^refs/tags/ ]]; then
    IS_TAG=true
    CURRENT_TAG=$(echo "$GITHUB_REF" | sed 's|refs/tags/||')
    log_info "Detected tag release: $CURRENT_TAG"
else
    log_info "Detected alpha build (branch push)"
fi

# Get current timestamp
NOW=$(date +%s)
MONTH_AGO=$(($NOW - $MONTH_AGO_SECONDS))

# Initialize changelog file
echo "# $ADDON_NAME Changelog" > "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Placeholders for AI summaries
MONTH_SUMMARY_MARKER="<!-- MONTH_SUMMARY_PLACEHOLDER -->"
RELEASE_SUMMARY_MARKER="<!-- RELEASE_SUMMARY_PLACEHOLDER -->"

# Temp files for collecting commits
TEMP_MONTH_COMMITS=$(mktemp)
TEMP_RELEASE_COMMITS=$(mktemp)
TEMP_ALPHA_COMMITS=$(mktemp)

# Check for alpha build (unreleased commits)
if [ "$IS_TAG" = false ]; then
    # Get latest tag
    LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

    if [ -n "$LATEST_TAG" ]; then
        log_info "Checking for unreleased commits since $LATEST_TAG..."

        # Get commit subjects for changelog display
        get_commits_subjects "$LATEST_TAG..HEAD" "$TEMP_ALPHA_COMMITS"
    else
        log_info "No tags found, collecting all commits as unreleased..."

        # No tags exist yet — treat all commits as unreleased
        git log --pretty=format:"%s" --no-merges > "$TEMP_ALPHA_COMMITS" 2>/dev/null
    fi

    if [ -s "$TEMP_ALPHA_COMMITS" ]; then
        ALPHA_COUNT=$(grep -c "." "$TEMP_ALPHA_COMMITS" 2>/dev/null || echo "0")
        log_info "Found $ALPHA_COUNT unreleased commits"

        echo "## ⚡ Alpha Build - Unreleased Changes" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "_These changes are not yet in a release. This is a development build._" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "$RELEASE_SUMMARY_MARKER" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"

        # Format and add categorized commits
        format_categorized_commits "$TEMP_ALPHA_COMMITS" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"

        # Save for AI summary
        cat "$TEMP_ALPHA_COMMITS" > "$TEMP_RELEASE_COMMITS"
    fi
fi

# Add monthly summary section
echo "## 📅 Last Month Summary" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "$MONTH_SUMMARY_MARKER" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Get all tags from the last month
log_info "Fetching tags from last month..."
ALL_TAGS=$(git tag --sort=-version:refname)

RECENT_TAGS=()
for tag in $ALL_TAGS; do
    TAG_DATE=$(git log -1 --format=%at "$tag" 2>/dev/null)
    if [ -n "$TAG_DATE" ] && [ "$TAG_DATE" -ge "$MONTH_AGO" ]; then
        RECENT_TAGS+=("$tag")
    fi
done

log_info "Found ${#RECENT_TAGS[@]} releases from last month"

# If this is a tag release and it's the latest, add "This Release" section
if [ "$IS_TAG" = true ] && [ "${RECENT_TAGS[0]}" = "$CURRENT_TAG" ]; then
    echo "## 🎯 This Release" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "$RELEASE_SUMMARY_MARKER" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
fi

# Build a full sorted tag list for proper previous tag lookup
ALL_TAGS_ARRAY=()
while IFS= read -r tag; do
    ALL_TAGS_ARRAY+=("$tag")
done <<< "$ALL_TAGS"

# Process each recent tag
for i in "${!RECENT_TAGS[@]}"; do
    TAG="${RECENT_TAGS[$i]}"
    TAG_DATE=$(git log -1 --format=%ai "$TAG" | cut -d' ' -f1)

    log_info "Processing version $TAG ($TAG_DATE)..."

    # Get previous tag by finding position in full sorted tag list
    PREV_TAG=""
    for j in "${!ALL_TAGS_ARRAY[@]}"; do
        if [ "${ALL_TAGS_ARRAY[$j]}" = "$TAG" ]; then
            # Next index in the sorted list is the previous version
            NEXT_IDX=$((j + 1))
            if [ $NEXT_IDX -lt ${#ALL_TAGS_ARRAY[@]} ]; then
                PREV_TAG="${ALL_TAGS_ARRAY[$NEXT_IDX]}"
            fi
            break
        fi
    done

    log_debug "Tag $TAG -> Previous tag: ${PREV_TAG:-NONE}"

    # Get commit subjects for changelog display
    TEMP_TAG_COMMITS=$(mktemp)
    if [ -n "$PREV_TAG" ]; then
        get_commits_subjects "$PREV_TAG..$TAG" "$TEMP_TAG_COMMITS"
    else
        # No previous tag found - this is the first tag ever, skip it to avoid years of history
        log_warn "No previous tag found for $TAG, skipping to avoid full history"
        echo "" > "$TEMP_TAG_COMMITS"
    fi

    # Check commit count (count non-empty lines, handles files without trailing newline)
    COMMIT_COUNT=$(grep -c "." "$TEMP_TAG_COMMITS" 2>/dev/null || echo "0")

    # Add to monthly commits
    cat "$TEMP_TAG_COMMITS" >> "$TEMP_MONTH_COMMITS"

    # If this is the current release tag, save for release summary
    if [ "$IS_TAG" = true ] && [ "$TAG" = "$CURRENT_TAG" ]; then
        cat "$TEMP_TAG_COMMITS" > "$TEMP_RELEASE_COMMITS"
    fi

    # Add version section
    echo "## Version $TAG ($TAG_DATE)" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    if [ -s "$TEMP_TAG_COMMITS" ]; then
        format_categorized_commits "$TEMP_TAG_COMMITS" >> "$OUTPUT_FILE"
    else
        echo "- No changes recorded" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi

    echo "" >> "$OUTPUT_FILE"

    rm -f "$TEMP_TAG_COMMITS"
done

# Generate AI summaries (only for tag releases)
if [ "$IS_TAG" = true ]; then
    log_info "Generating AI summaries for tag release..."

    # Monthly summary - get full commit bodies for AI context
    if [ -s "$TEMP_MONTH_COMMITS" ]; then
        # Build the commit range for all recent tags
        MONTH_RANGE=""
        if [ ${#RECENT_TAGS[@]} -gt 0 ]; then
            OLDEST_TAG="${RECENT_TAGS[-1]}"
            # Find the tag before the oldest recent tag
            for j in "${!ALL_TAGS_ARRAY[@]}"; do
                if [ "${ALL_TAGS_ARRAY[$j]}" = "$OLDEST_TAG" ]; then
                    NEXT_IDX=$((j + 1))
                    if [ $NEXT_IDX -lt ${#ALL_TAGS_ARRAY[@]} ]; then
                        MONTH_RANGE="${ALL_TAGS_ARRAY[$NEXT_IDX]}..${RECENT_TAGS[0]}"
                    fi
                    break
                fi
            done
        fi

        if [ -n "$MONTH_RANGE" ]; then
            MONTH_COMMITS_FULL=$(get_commits_with_body_for_ai "$MONTH_RANGE")
        else
            MONTH_COMMITS_FULL=$(cat "$TEMP_MONTH_COMMITS")
        fi

        MONTH_SUMMARY=$(generate_ai_summary "$MONTH_COMMITS_FULL" "month") || MONTH_SUMMARY=""

        if [ -n "$MONTH_SUMMARY" ]; then
            log_info "Monthly summary generated!"
            sed -i "s|$MONTH_SUMMARY_MARKER|$MONTH_SUMMARY|g" "$OUTPUT_FILE"
        else
            sed -i "/$MONTH_SUMMARY_MARKER/d" "$OUTPUT_FILE"
        fi
    else
        sed -i "/$MONTH_SUMMARY_MARKER/d" "$OUTPUT_FILE"
    fi

    # Release summary (only if there are more than 3 changes)
    if [ -s "$TEMP_RELEASE_COMMITS" ]; then
        RELEASE_COMMIT_COUNT=$(grep -c "." "$TEMP_RELEASE_COMMITS" 2>/dev/null || echo "0")

        if [ "$RELEASE_COMMIT_COUNT" -gt 3 ]; then
            # Get full commit bodies for AI context
            # Find the previous tag for the current release
            RELEASE_PREV_TAG=""
            for j in "${!ALL_TAGS_ARRAY[@]}"; do
                if [ "${ALL_TAGS_ARRAY[$j]}" = "$CURRENT_TAG" ]; then
                    NEXT_IDX=$((j + 1))
                    if [ $NEXT_IDX -lt ${#ALL_TAGS_ARRAY[@]} ]; then
                        RELEASE_PREV_TAG="${ALL_TAGS_ARRAY[$NEXT_IDX]}"
                    fi
                    break
                fi
            done

            if [ -n "$RELEASE_PREV_TAG" ]; then
                RELEASE_COMMITS_FULL=$(get_commits_with_body_for_ai "$RELEASE_PREV_TAG..$CURRENT_TAG")
            else
                RELEASE_COMMITS_FULL=$(cat "$TEMP_RELEASE_COMMITS")
            fi

            RELEASE_SUMMARY=$(generate_ai_summary "$RELEASE_COMMITS_FULL" "release") || RELEASE_SUMMARY=""

            if [ -n "$RELEASE_SUMMARY" ]; then
                log_info "Release summary generated!"
                sed -i "s|$RELEASE_SUMMARY_MARKER|$RELEASE_SUMMARY|g" "$OUTPUT_FILE"
            else
                sed -i "/$RELEASE_SUMMARY_MARKER/d" "$OUTPUT_FILE"
            fi
        else
            log_info "Skipping release summary (only $RELEASE_COMMIT_COUNT changes)"
            sed -i "/$RELEASE_SUMMARY_MARKER/d" "$OUTPUT_FILE"
        fi
    else
        sed -i "/$RELEASE_SUMMARY_MARKER/d" "$OUTPUT_FILE"
    fi
else
    log_info "Skipping AI summaries for alpha build"
    sed -i "/$MONTH_SUMMARY_MARKER/d" "$OUTPUT_FILE"
    sed -i "/$RELEASE_SUMMARY_MARKER/d" "$OUTPUT_FILE"
fi

# Clean up
rm -f "$TEMP_MONTH_COMMITS" "$TEMP_RELEASE_COMMITS" "$TEMP_ALPHA_COMMITS"

# Add footer with support links (only if URLs are configured)
if [ -n "$CF_URL" ] || [ -n "$WAGO_URL" ] || [ -n "$GH_ISSUES_URL" ] || [ -n "$DISCORD_SUPPORT_URL" ]; then
    log_info "Adding support links footer..."
    echo "" >> "$OUTPUT_FILE"
    echo "---" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "## Links" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    # Build download line
    download_parts=""
    [ -n "$CF_URL" ] && download_parts="[CurseForge]($CF_URL)"
    [ -n "$WAGO_URL" ] && { [ -n "$download_parts" ] && download_parts="$download_parts | "; download_parts="${download_parts}[Wago]($WAGO_URL)"; }
    [ -n "$download_parts" ] && echo "- **Download**: $download_parts" >> "$OUTPUT_FILE"

    # Build support line
    support_parts=""
    [ -n "$DISCORD_SUPPORT_URL" ] && support_parts="[Discord]($DISCORD_SUPPORT_URL)"
    [ -n "$GH_ISSUES_URL" ] && { [ -n "$support_parts" ] && support_parts="$support_parts | "; support_parts="${support_parts}[Report Issues]($GH_ISSUES_URL)"; }
    [ -n "$ROADMAP_URL" ] && { [ -n "$support_parts" ] && support_parts="$support_parts | "; support_parts="${support_parts}[Roadmap]($ROADMAP_URL)"; }
    [ -n "$support_parts" ] && echo "- **Support**: $support_parts" >> "$OUTPUT_FILE"
fi

log_info "Smart changelog generated successfully: $OUTPUT_FILE"
log_info "Preview (first 50 lines):"
head -n 50 "$OUTPUT_FILE"

exit 0
