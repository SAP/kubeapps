#!/usr/bin/env bash

# Copyright 2025 the Kubeapps contributors.
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Helm index publisher reusable script
# Usage:
#   helm_index_publish.sh --mode stable|dev
# Optional env vars:
#   FULL_REGEN: true/false (default: false)
#   INPUT_VERSION: single tag to process (default: empty)
#   DEBUG: true to enable bash tracing
# Requirements: gh, helm, jq, yq must be available; GH_TOKEN must be set in the environment.

# Structured logging helpers (define early)
INDENT_LEVEL=0
indent() { printf '%*s' $((INDENT_LEVEL*2)) '' >&2; }
section() { echo >&2; echo "== $* ==" >&2; }
step()    { printf "%s- %s\n" "$(indent)" "$*" >&2; }
substep() { INDENT_LEVEL=$((INDENT_LEVEL+1)); printf "%s> %s\n" "$(indent)" "$*" >&2; INDENT_LEVEL=$((INDENT_LEVEL-1)); }
push_indent() { INDENT_LEVEL=$((INDENT_LEVEL+1)); }
pop_indent()  { if [[ $INDENT_LEVEL -gt 0 ]]; then INDENT_LEVEL=$((INDENT_LEVEL-1)); fi }

# Simple logger with timestamp
log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" >&2
}

[[ "${DEBUG:-false}" == "true" ]] && set -x

MODE="stable"
FULL_REGEN="${FULL_REGEN:-false}"
INPUT_VERSION="${INPUT_VERSION:-}"

# Parse arguments first so MODE reflects actual input
for arg in "$@"; do
  case "$arg" in
    --mode=dev)
      MODE="dev" ;;
    --mode=stable)
      MODE="stable" ;;
    --mode)
      shift; MODE="${1:-$MODE}" ;;
    dev|stable)
      MODE="$arg" ;;
    *)
      step "Ignoring unknown argument: $arg" ;;
  esac
done

# Constants derived from environment/repo
REPO_OWNER="${GITHUB_REPOSITORY_OWNER:-SAP}"
REPO_NAME="${GITHUB_REPOSITORY##*/}"
REPO_SLUG="${GITHUB_REPOSITORY:-${REPO_OWNER}/${REPO_NAME}}"
BASE_URL="https://${REPO_OWNER}.github.io/${REPO_NAME}/helm"
[[ "$MODE" == "dev" ]] && BASE_URL="${BASE_URL}/dev"
CHART_NAME="kubeapps"
OUTPUT_DIR="site/static/helm"
[[ "$MODE" == "dev" ]] && OUTPUT_DIR="${OUTPUT_DIR}/dev"

# Now log environment and inputs with the correct MODE
log "Starting helm index publish script"
section "Environment and Inputs"
step "Mode: ${MODE}"
step "Full regen: ${FULL_REGEN}"
step "Input version: ${INPUT_VERSION:-<none>}"
step "Repo: ${GITHUB_REPOSITORY:-${REPO_OWNER}/${REPO_NAME}}"

# Verify required tools and auth
require_tool() { command -v "$1" >/dev/null 2>&1 || { log "ERROR: Required tool '$1' not found"; return 1; }; }

check_env_and_tools() {
  local ok=true
  section "Check tools and authentication"
  step "Checking required tools (git, jq, helm, gh)"
  push_indent
  require_tool git || ok=false
  require_tool jq || { log "ERROR: 'jq' missing. On ubuntu-latest: sudo apt-get update && sudo apt-get install -y jq"; ok=false; }
  require_tool helm || { log "ERROR: 'helm' missing. Install Helm before running this script."; ok=false; }
  require_tool gh || { log "ERROR: 'gh' missing. Install GitHub CLI (gh)."; ok=false; }
  pop_indent
  step "GH_TOKEN present: $([[ -n "${GH_TOKEN:-}" ]] && echo yes || echo no)"
  if [[ -n "${GH_TOKEN:-}" ]]; then
    push_indent
    if ! gh auth status >/dev/null 2>&1; then
      step "Authenticating gh via token"
      echo "$GH_TOKEN" | gh auth login --with-token >/dev/null 2>&1 || step "WARN: gh auth login failed, continuing unauthenticated"
    else
      step "gh already authenticated"
    fi
    pop_indent
  fi
  $ok
}

# Record original branch/ref to restore later
ORIG_BRANCH=$(git rev-parse --abbrev-ref HEAD || echo HEAD)
if [[ "$ORIG_BRANCH" == "HEAD" ]]; then
  ORIG_BRANCH=$(gh api repos/${REPO_SLUG} --jq '.default_branch' 2>/dev/null || echo main)
fi
log "Detected repository: ${REPO_SLUG}, original branch: ${ORIG_BRANCH}"

discover_tags() {
  section "Discover tags (${MODE})"
  local single="$INPUT_VERSION"
  if [[ -n "$single" ]]; then
    step "Using single tag from INPUT_VERSION: $single"
    echo "$single"
    return 0
  fi

  # Define tag classification
  local stable_re='^v[0-9]+\.[0-9]+\.[0-9]+$'
  local dev_re='^v[0-9]+\.[0-9]+\.[0-9]+-.+'

  # 1) Try GitHub releases
  step "GitHub releases"
  push_indent
  local releases
  releases=$(gh api --paginate repos/${REPO_SLUG}/releases --jq '.[].tag_name' 2>/dev/null || true)
  local rel_count=0
  [[ -n "$releases" ]] && rel_count=$(echo "$releases" | wc -l | awk '{print $1}')
  substep "Found: ${rel_count}"
  pop_indent

  # 2) Fallback to GitHub tags
  local gh_tags=""
  local ght_count=0
  if [[ -z "$releases" ]]; then
    step "GitHub repo tags (fallback)"
    push_indent
    gh_tags=$(gh api --paginate repos/${REPO_SLUG}/tags --jq '.[].name' 2>/dev/null || true)
    [[ -n "$gh_tags" ]] && ght_count=$(echo "$gh_tags" | wc -l | awk '{print $1}')
    substep "Found: ${ght_count}"
    pop_indent
  fi

  # 3) Fallback to local git tags
  local git_tags=""
  local local_count=0
  if [[ -z "$releases" && -z "$gh_tags" ]]; then
    step "Local git tags (fallback)"
    push_indent
    git_tags=$(git tag --list || true)
    [[ -n "$git_tags" ]] && local_count=$(echo "$git_tags" | wc -l | awk '{print $1}')
    substep "Found: ${local_count}"
    pop_indent
  fi

  # Build candidate list
  local source=""
  local candidates=""
  if [[ -n "$releases" ]]; then
    source="releases"; candidates="$releases"
  elif [[ -n "$gh_tags" ]]; then
    source="repo-tags"; candidates="$gh_tags"
  else
    source="local-tags"; candidates="$git_tags"
  fi
  step "Using tag source: ${source}"

  # Filter per mode
  local filtered=""
  if [[ -n "$candidates" ]]; then
    step "Filtering candidates for mode ${MODE}"
    push_indent
    if [[ "$MODE" == "stable" ]]; then
      filtered=$(echo "$candidates" | grep -E "$stable_re" || true)
      substep "Stable regex: ${stable_re} (eg: v3.0.0)"
    else
      filtered=$(echo "$candidates" | grep -E "$dev_re" || true)
      substep "Dev regex: ${dev_re} (eg: v3.0.0-rc1, v3.0.0-rc1-rc4)"
    fi
    pop_indent
  fi

  local filt_count=0
  [[ -n "$filtered" ]] && filt_count=$(echo "$filtered" | wc -l | awk '{print $1}')
  step "Filtered tag count: ${filt_count}"

  # Return filtered tags as newline-separated list
  if [[ -z "$filtered" ]]; then
    echo ""
  else
    echo "$filtered" | sort -u
  fi
}

package_and_upload() {
  section "Download and process release asset"
  step "Tag: $1"
  push_indent
  local tag=$1
  local outdir="$OUTPUT_DIR/$tag"
  local meta="$outdir/result.json"

  mkdir -p "$outdir"

  # Skip if metadata exists and FULL_REGEN is not set
  # We'll also verify the digest hasn't changed below
  if [[ "$FULL_REGEN" != "true" && -f "$meta" ]]; then
    substep "Meta exists, will verify digest hasn't changed"
  fi

  # Download the release asset that was created by prepare_release_asset.sh
  substep "Fetching release assets for ${tag}"
  local asset_name asset_url

  # Get all assets for this release (handle errors gracefully)
  local assets_json
  if ! assets_json=$(gh api repos/${REPO_SLUG}/releases/tags/${tag} --jq '.assets' 2>/dev/null); then
    substep "WARNING: Failed to fetch release ${tag} from GitHub API"
    pop_indent
    return 1
  fi

  # Handle case where assets_json is empty or null
  if [[ -z "$assets_json" || "$assets_json" == "null" ]]; then
    assets_json="[]"
  fi

  # Find the kubeapps chart asset (should be kubeapps-*.tgz)
  asset_name=$(echo "$assets_json" | jq -r '.[] | select(.name | test("^kubeapps-.*\\.tgz$")) | .name' | head -1)
  asset_url=$(echo "$assets_json" | jq -r '.[] | select(.name | test("^kubeapps-.*\\.tgz$")) | .browser_download_url' | head -1)

  if [[ -z "$asset_name" || -z "$asset_url" ]]; then
    substep "WARNING: No Helm chart asset found for release ${tag}"
    substep "Expected asset name pattern: kubeapps-*.tgz"
    pop_indent
    return 1
  fi

  substep "Found asset: ${asset_name}"
  substep "Downloading from: ${asset_url}"

  # Download the asset
  local tmpdir
  tmpdir=$(mktemp -d)
  local downloaded_tgz="${tmpdir}/${asset_name}"

  if ! curl -fsSL -o "${downloaded_tgz}" "${asset_url}"; then
    substep "WARNING: Failed to download asset from ${asset_url}"
    rm -rf "$tmpdir"
    pop_indent
    return 1
  fi

  # Extract Chart.yaml to read metadata
  local extract_dir="${tmpdir}/extracted"
  mkdir -p "${extract_dir}"

  if ! tar -xzf "${downloaded_tgz}" -C "${extract_dir}" 2>/dev/null; then
    substep "WARNING: Failed to extract tarball (corrupted or invalid format)"
    rm -rf "$tmpdir"
    pop_indent
    return 1
  fi

  # Find Chart.yaml (should be in kubeapps/Chart.yaml based on package structure)
  local chart_yaml
  chart_yaml=$(find "${extract_dir}" -name "Chart.yaml" | head -1)

  if [[ -z "$chart_yaml" || ! -f "$chart_yaml" ]]; then
    substep "WARNING: Chart.yaml not found in downloaded package"
    rm -rf "$tmpdir"
    pop_indent
    return 1
  fi

  local chart_version
  chart_version=$(grep '^version:' "$chart_yaml" | awk '{print $2}')

  if [[ -z "$chart_version" ]]; then
    substep "WARNING: Could not extract version from Chart.yaml"
    rm -rf "$tmpdir"
    pop_indent
    return 1
  fi

  substep "Chart version: ${chart_version}"

  # Calculate SHA256 of the downloaded asset
  local sha256
  if command -v sha256sum &>/dev/null; then
    sha256=$(sha256sum "$downloaded_tgz" | awk '{print $1}')
  else
    # macOS fallback
    sha256=$(shasum -a 256 "$downloaded_tgz" | awk '{print $1}')
  fi

  # Check if digest has changed (skip regeneration if unchanged)
  if [[ "$FULL_REGEN" != "true" && -f "$meta" ]]; then
    local existing_digest
    existing_digest=$(jq -r '.digest // ""' "$meta")
    if [[ "$existing_digest" == "$sha256" ]]; then
      substep "Digest unchanged, skipping regeneration"
      rm -rf "$tmpdir"
      pop_indent
      return 0
    else
      substep "Digest changed: ${existing_digest:0:12}... -> ${sha256:0:12}..."
    fi
  fi

  local created_ts
  created_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Extract additional metadata from Chart.yaml
  local chart_api_version chart_app_version chart_description chart_home chart_kube_version
  chart_api_version=$(grep '^apiVersion:' "$chart_yaml" | awk '{print $2}' || echo "v2")
  chart_app_version=$(grep '^appVersion:' "$chart_yaml" | sed 's/^appVersion: *//' | tr -d "'" || echo "")
  chart_description=$(grep '^description:' "$chart_yaml" | sed 's/^description: *//' || echo "")
  chart_home=$(grep '^home:' "$chart_yaml" | awk '{print $2}' || echo "")
  chart_kube_version=$(grep '^kubeVersion:' "$chart_yaml" | sed 's/^kubeVersion: *//' | tr -d "'" || echo "")

  # Extract sources as JSON array
  local chart_sources
  chart_sources=$(awk '/^sources:/,/^[a-zA-Z]/ {if ($0 ~ /^- /) print $2}' "$chart_yaml" | jq -R -s -c 'split("\n") | map(select(length > 0))' || echo "[]")

  substep "appVersion: ${chart_app_version}"
  substep "description: ${chart_description:0:100}..."

  # Write metadata for index generation
  jq -n --arg tag "$tag" \
        --arg chart_version "$chart_version" \
        --arg asset_url "$asset_url" \
        --arg sha256 "$sha256" \
        --arg created "$created_ts" \
        --arg name "$CHART_NAME" \
        --arg api_version "$chart_api_version" \
        --arg app_version "$chart_app_version" \
        --arg description "$chart_description" \
        --arg home "$chart_home" \
        --arg kube_version "$chart_kube_version" \
        --argjson sources "$chart_sources" \
    '{tag:$tag, chart_version:$chart_version, asset_url:$asset_url, digest:$sha256, created:$created, name:$name, apiVersion:$api_version, appVersion:$app_version, description:$description, home:$home, kubeVersion:$kube_version, sources:$sources}' > "$meta"

  substep "Wrote metadata: ${meta}"
  rm -rf "$tmpdir"
  pop_indent
}

generate_index() {
  section "Generate index.yaml"
  local index_file="$OUTPUT_DIR/index.yaml"
  local index_file_tmp="${index_file}.tmp"
  mkdir -p "$OUTPUT_DIR"

  # Initialize index with apiVersion
  cat > "$index_file_tmp" << 'EOF'
apiVersion: v1
entries: {}
EOF
  yq -i '.entries.kubeapps = []' "$index_file_tmp"

  for meta in $(find "$OUTPUT_DIR" -maxdepth 2 -name result.json | sort); do
    push_indent
    substep "Add entry from: ${meta}"
    local name ver url digest created api_version app_version description home kube_version
    name=$(jq -r '.name' "$meta")
    ver=$(jq -r '.chart_version' "$meta")
    url=$(jq -r '.asset_url' "$meta")
    digest=$(jq -r '.digest' "$meta")
    created=$(jq -r '.created' "$meta")
    api_version=$(jq -r '.apiVersion // "v2"' "$meta")
    app_version=$(jq -r '.appVersion // ""' "$meta")
    description=$(jq -r '.description // ""' "$meta")
    home=$(jq -r '.home // ""' "$meta")
    kube_version=$(jq -r '.kubeVersion // ""' "$meta")

    # Extract sources array
    local sources_json
    sources_json=$(jq -c '.sources // []' "$meta")

    # Build entry with all required fields
    local entry
    entry=$(jq -n \
      --arg name "$name" \
      --arg version "$ver" \
      --arg url "$url" \
      --arg digest "$digest" \
      --arg created "$created" \
      --arg api_version "$api_version" \
      --arg app_version "$app_version" \
      --arg description "$description" \
      --arg home "$home" \
      --arg kube_version "$kube_version" \
      --argjson sources "$sources_json" \
      '{
        name: $name,
        version: "\($version)",
        apiVersion: $api_version,
        appVersion: $app_version,
        description: $description,
        home: $home,
        kubeVersion: $kube_version,
        sources: $sources,
        urls: [$url],
        created: $created,
        digest: $digest
      }')

    # Add entry to index
    local tmp_entry
    tmp_entry=$(mktemp)
    echo "$entry" > "$tmp_entry"
    yq -i ".entries.kubeapps += [$(cat "$tmp_entry")]" "$index_file_tmp"
    rm -f "$tmp_entry"
    pop_indent
  done

  # Only replace if content has changed or file doesn't exist
  if [[ ! -f "$index_file" ]]; then
    mv "$index_file_tmp" "$index_file"
    step "Index created: ${index_file}"
  elif ! diff -q "$index_file" "$index_file_tmp" >/dev/null 2>&1; then
    mv "$index_file_tmp" "$index_file"
    step "Index updated: ${index_file}"
  else
    rm -f "$index_file_tmp"
    step "Index unchanged: ${index_file}"
  fi
}

return_branch_and_commit() {
  section "Commit and push changes"
  local commit_path="$OUTPUT_DIR"
  local message="Helm(${MODE}): refresh index.yaml (asset URLs) and metadata only"

  # We are already on ${ORIG_BRANCH}; do not checkout again to avoid overwriting local changes
  if ! git config user.email >/dev/null; then
    step "Configure git identity"
    push_indent
    git config user.name "${GITHUB_ACTOR:-github-actions[bot]}"
    git config user.email "${GITHUB_ACTOR:-41898282+github-actions[bot]@users.noreply.github.com}"
    pop_indent
  fi

  # Check if there are any changes to commit
  local changes
  changes=$(git status --porcelain "$commit_path" 2>/dev/null || echo "")

  if [[ -z "$changes" ]]; then
    step "No changes to commit - index.yaml is up to date"
    return 0
  fi

  step "Detected changes in: ${commit_path}"
  push_indent
  echo "$changes" | while read -r line; do
    substep "$line"
  done
  pop_indent

  step "Commit and push changes"
  push_indent
  git add "$commit_path"

  # Double check there are staged changes before committing
  if git diff --cached --quiet; then
    substep "No staged changes after git add, skipping commit"
    pop_indent
    return 0
  fi

  git commit -m "$message"
  git push
  pop_indent
  step "Changes pushed successfully"
}

main() {
  section "Initialize"
  check_env_and_tools || { log "ERROR: Environment/tool checks failed"; exit 1; }

  # Install yq if missing
  if ! command -v yq >/dev/null 2>&1; then
    step "Install yq"
    curl -sSL https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64 -o /usr/local/bin/yq
    chmod +x /usr/local/bin/yq
  fi

  section "Discover and process tags"
  local tags_list
  tags_list=$(discover_tags)
  step "Tags (newline-separated):"
  push_indent
  echo "$tags_list"
  pop_indent

  local processed=0
  local failed=0

  if [[ -z "$tags_list" ]]; then
    step "No tags found for mode '${MODE}'. Will generate empty index.yaml."
  else
    # Mode-specific tag regex for validation
    local stable_re='^v[0-9]+\.[0-9]+\.[0-9]+$'
    local dev_re='^v[0-9]+\.[0-9]+\.[0-9]+-.+'
    while IFS= read -r tag; do
      # Trim whitespace
      tag=${tag%%[[:space:]]*}
      [[ -z "$tag" ]] && continue
      # Validate tag according to mode
      if [[ "$MODE" == "stable" ]]; then
        [[ "$tag" =~ $stable_re ]] || { substep "Skip non-stable line: $tag"; continue; }
      else
        [[ "$tag" =~ $dev_re ]] || { substep "Skip non-dev line: $tag"; continue; }
      fi
      step "Process tag: ${tag}"
      push_indent
      # Wrap in error handling to continue processing other tags if one fails
      if package_and_upload "$tag"; then
        processed=$((processed+1))
      else
        substep "WARNING: Failed to process tag ${tag}, continuing with next tag"
        failed=$((failed+1))
      fi
      pop_indent
    done <<< "$tags_list"
    step "Processed ${processed} tag(s), ${failed} failed"
  fi

  # Switch back to original branch before generating index to avoid checkout conflicts
  section "Switch back to original branch before index"
  step "Checkout: ${ORIG_BRANCH}"
  git checkout --quiet "$ORIG_BRANCH"

  generate_index
  return_branch_and_commit
  section "Done"
  step "Script completed successfully"
}

main "$@"
