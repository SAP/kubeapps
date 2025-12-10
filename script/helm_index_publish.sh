#!/usr/bin/env bash
set -euo pipefail

# Helm index publisher reusable script
# Usage:
#   helm_index_publish.sh --mode stable|dev
# Optional env vars:
#   FULL_REGEN: true/false (default: false)
#   INPUT_VERSION: single tag to process (default: empty)
# Requirements: gh, helm, jq, yq must be available; GH_TOKEN must be set in the environment.

MODE="stable"
FULL_REGEN="${FULL_REGEN:-false}"
INPUT_VERSION="${INPUT_VERSION:-}"

for arg in "$@"; do
  case "$arg" in
    --mode=dev)
      MODE="dev" ;;
    --mode=stable)
      MODE="stable" ;;
    --mode)
      shift; MODE="${1:-$MODE}" ;;
    dev|stable)
      # Allow positional mode argument without flag
      MODE="$arg" ;;
    *)
      # Ignore unknown arguments rather than failing
      echo "Unknown argument: $arg" >&2 ;;
  esac
done

# Constants derived from environment/repo
REPO_OWNER="${GITHUB_REPOSITORY_OWNER:-SAP}"
REPO_NAME="${GITHUB_REPOSITORY##*/}"
BASE_URL="https://${REPO_OWNER}.github.io/${REPO_NAME}/helm"
if [[ "$MODE" == "dev" ]]; then
  BASE_URL="${BASE_URL}/dev"
fi
CHART_DIR="chart/kubeapps"
CHART_NAME="kubeapps"
OUTPUT_DIR="site/static/helm"
if [[ "$MODE" == "dev" ]]; then
  OUTPUT_DIR="${OUTPUT_DIR}/dev"
fi

# Record original branch/ref to restore later
ORIG_BRANCH=$(git rev-parse --abbrev-ref HEAD || echo HEAD)
if [[ "$ORIG_BRANCH" == "HEAD" ]]; then
  ORIG_BRANCH=$(gh api repos/${GITHUB_REPOSITORY} --jq '.default_branch')
fi

discover_tags() {
  local single="$INPUT_VERSION"
  if [[ -n "$single" ]]; then
    echo "[\"$single\"]"
    return 0
  fi
  if [[ "$MODE" == "stable" ]]; then
    gh api --paginate repos/${GITHUB_REPOSITORY}/releases --jq '[.[] | .tag_name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))]'
  else
    gh api --paginate repos/${GITHUB_REPOSITORY}/releases --jq '[.[] | .tag_name | select(test("^v") and (test("^v[0-9]+\\.[0-9]+\\.[0-9]+$") | not))]'
  fi
}

package_and_upload() {
  local tag=$1
  local outdir="$OUTPUT_DIR/$tag"
  local meta="$outdir/result.json"

  mkdir -p "$outdir"
  if [[ "$FULL_REGEN" != "true" && -f "$meta" ]]; then
    echo "Meta exists for $tag, skipping"
    return 0
  fi

  echo "Packaging chart for $tag"
  git checkout --quiet "$tag"
  local chart_version
  chart_version=$(grep '^version:' "$CHART_DIR/Chart.yaml" | awk '{print $2}')
  helm package "$CHART_DIR" --destination "/tmp"
  local packaged_tgz
  packaged_tgz=$(ls /tmp/${CHART_NAME}-*.tgz | tail -n 1)
  if [[ -z "$packaged_tgz" || ! -f "$packaged_tgz" ]]; then
    echo "Packaged chart not found in /tmp for $tag" >&2
    return 1
  fi
  local sha256
  sha256=$(sha256sum "$packaged_tgz" | awk '{print $1}')

  echo "Uploading chart package to GitHub release assets for $tag"
  gh release upload "$tag" "$packaged_tgz" --clobber
  local asset_name asset_url
  asset_name=$(basename "$packaged_tgz")
  asset_url=$(gh api repos/${GITHUB_REPOSITORY}/releases/tags/${tag} --jq ".assets[] | select(.name == \"${asset_name}\") | .browser_download_url")
  if [[ -z "$asset_url" ]]; then
    echo "Failed to resolve asset URL for $asset_name" >&2
    return 1
  fi
  local created_ts
  created_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq -n --arg tag "$tag" --arg chart_version "$chart_version" --arg asset_url "$asset_url" --arg sha256 "$sha256" --arg created "$created_ts" --arg name "$CHART_NAME" \
    '{tag:$tag, chart_version:$chart_version, asset_url:$asset_url, digest:$sha256, created:$created, name:$name}' > "$meta"
}

generate_index() {
  local index_file="$OUTPUT_DIR/index.yaml"
  mkdir -p "$OUTPUT_DIR"
  echo "entries: {}" > "$index_file"
  yq -i '.entries.kubeapps = []' "$index_file"
  for meta in $(find "$OUTPUT_DIR" -maxdepth 2 -name result.json | sort); do
    local name ver url digest created
    name=$(jq -r '.name' "$meta")
    ver=$(jq -r '.chart_version' "$meta")
    url=$(jq -r '.asset_url' "$meta")
    digest=$(jq -r '.digest' "$meta")
    created=$(jq -r '.created' "$meta")
    yq -i \
      ".entries.kubeapps += [{\"name\": \"${name}\", \"version\": \"${ver}\", \"urls\": [\"${url}\"], \"created\": \"${created}\", \"digest\": \"${digest}\"}]" \
      "$index_file"
  done
}

return_branch_and_commit() {
  local commit_path="$OUTPUT_DIR"
  local message="Helm(${MODE}): refresh index.yaml (asset URLs) and metadata only"
  echo "Switching back to: $ORIG_BRANCH"
  git checkout --quiet "$ORIG_BRANCH"
  # Configure git identity for CI if missing
  if ! git config user.email >/dev/null; then
    git config user.name "${GITHUB_ACTOR:-github-actions}"
    git config user.email "${GITHUB_ACTOR:-github-actions}@users.noreply.github.com"
  fi
  if [[ -n $(git status --porcelain "$commit_path") ]]; then
    git add "$commit_path"
    git commit -m "$message"
    git push
  else
    echo "No changes to commit"
  fi
}

main() {
  # Install yq if missing
  if ! command -v yq >/dev/null 2>&1; then
    curl -sSL https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64 -o /usr/local/bin/yq
    chmod +x /usr/local/bin/yq
  fi
  local tags_json
  tags_json=$(discover_tags)
  echo "Tags: $tags_json"
  # Treat empty array or null as no work
  if [[ -z "$tags_json" || "$tags_json" == "null" || "$tags_json" == "[]" ]]; then
    echo "No tags found"
    exit 0
  fi
  for tag in $(echo "$tags_json" | jq -r '.[]'); do
    package_and_upload "$tag"
  done
  generate_index
  return_branch_and_commit
}

main "$@"
