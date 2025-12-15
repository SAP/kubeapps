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
  section "Package and upload tag"
  step "Tag: $1"
  push_indent
  local tag=$1
  local outdir="$OUTPUT_DIR/$tag"
  local meta="$outdir/result.json"

  mkdir -p "$outdir"
  if [[ "$FULL_REGEN" != "true" && -f "$meta" ]]; then
    substep "Meta exists, skipping"
    pop_indent
    return 0
  fi

  # Export chart files from root directory of the specified tag without switching branches
  local tmpdir
  tmpdir=$(mktemp -d)
  substep "Export chart files from ${tag} (root) to ${tmpdir}"
  # Export entire repo at tag and use root as chart source
  git archive --format=tar "$tag" | tar -x -C "$tmpdir"
  local chart_src="$tmpdir"
  if [[ ! -f "$chart_src/Chart.yaml" ]]; then
    substep "ERROR: Chart.yaml not found in root directory of tag ${tag}"
    rm -rf "$tmpdir"
    pop_indent
    return 1
  fi

  local chart_version
  chart_version=$(grep '^version:' "$chart_src/Chart.yaml" | awk '{print $2}')
  substep "Chart version: ${chart_version}"

  substep "helm package ${chart_src}"
  helm package "$chart_src" --destination "/tmp"
  local packaged_tgz
  packaged_tgz=$(ls /tmp/${CHART_NAME}-*.tgz | tail -n 1)
  if [[ -z "$packaged_tgz" || ! -f "$packaged_tgz" ]]; then
    substep "ERROR: packaged chart not found"
    rm -rf "$tmpdir"
    pop_indent
    return 1
  fi
  local sha256
  sha256=$(sha256sum "$packaged_tgz" | awk '{print $1}')

  substep "Upload asset to release: $(basename "$packaged_tgz")"
  gh release upload "$tag" "$packaged_tgz" --clobber
  local asset_name asset_url
  asset_name=$(basename "$packaged_tgz")
  asset_url=$(gh api repos/${REPO_SLUG}/releases/tags/${tag} --jq ".assets[] | select(.name == \"${asset_name}\") | .browser_download_url")
  if [[ -z "$asset_url" ]]; then
    substep "ERROR: failed to resolve asset URL"
    rm -rf "$tmpdir"
    pop_indent
    return 1
  fi
  local created_ts
  created_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq -n --arg tag "$tag" --arg chart_version "$chart_version" --arg asset_url "$asset_url" --arg sha256 "$sha256" --arg created "$created_ts" --arg name "$CHART_NAME" \
    '{tag:$tag, chart_version:$chart_version, asset_url:$asset_url, digest:$sha256, created:$created, name:$name}' > "$meta"
  substep "Wrote metadata: ${meta}"
  rm -rf "$tmpdir"
  pop_indent
}

generate_index() {
  section "Generate index.yaml"
  local index_file="$OUTPUT_DIR/index.yaml"
  mkdir -p "$OUTPUT_DIR"
  echo "entries: {}" > "$index_file"
  yq -i '.entries.kubeapps = []' "$index_file"
  for meta in $(find "$OUTPUT_DIR" -maxdepth 2 -name result.json | sort); do
    push_indent
    substep "Add entry from: ${meta}"
    local name ver url digest created
    name=$(jq -r '.name' "$meta")
    ver=$(jq -r '.chart_version' "$meta")
    url=$(jq -r '.asset_url' "$meta")
    digest=$(jq -r '.digest' "$meta")
    created=$(jq -r '.created' "$meta")
    yq -i \
      ".entries.kubeapps += [{\"name\": \"${name}\", \"version\": \"${ver}\", \"urls\": [\"${url}\"], \"created\": \"${created}\", \"digest\": \"${digest}\"}]" \
      "$index_file"
    pop_indent
  done
  step "Index written: ${index_file}"
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
  if [[ -n $(git status --porcelain "$commit_path") ]]; then
    step "Commit and push changes"
    push_indent
    git add "$commit_path"
    git commit -m "$message"
    git push
    pop_indent
    step "Changes pushed"
  else
    step "No changes to commit"
  fi
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
  if [[ -z "$tags_list" ]]; then
    step "No tags found for mode '${MODE}'. Nothing to do."
    exit 0
  fi
  local processed=0
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
    package_and_upload "$tag"
    pop_indent
    processed=$((processed+1))
  done <<< "$tags_list"
  step "Processed ${processed} tag(s)"

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
