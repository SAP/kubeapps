#!/usr/bin/env bash
# Prepares a release asset containing only the Helm chart under a top-level 'kubeapps' folder,
# with appVersion set to DEVEL and images retagged to kubeapps/*:latest.
# Usage: prepare_release_asset.sh <tag>
set -o errexit
set -o nounset
set -o pipefail

TAG=${1:?Missing tag}
PROJECT_DIR=$(cd "$(dirname "$0")/.." >/dev/null && pwd)
CHART_SRC_DIR="${PROJECT_DIR}/chart/kubeapps"

if [[ ! -d "${CHART_SRC_DIR}" ]]; then
  echo "Expected chart directory '${CHART_SRC_DIR}' not found" >&2
  exit 1
fi

WORKDIR=$(mktemp -d)
cp -R "${CHART_SRC_DIR}" "${WORKDIR}/kubeapps"

# Set appVersion: DEVEL in Chart.yaml
sed -i.bk 's/^appVersion: .*/appVersion: DEVEL/' "${WORKDIR}/kubeapps/Chart.yaml"
rm -f "${WORKDIR}/kubeapps/Chart.yaml.bk"

# Retag images in values.yaml to development (kubeapps/* repository, tag: latest)
VALUES_FILE="${WORKDIR}/kubeapps/values.yaml"

retag() {
  local service=$1
  local currentImageEscaped="bitnami\\/kubeapps-${service}"
  # Special case for kubeapps-apis which may appear as bitnami/kubeapps-apis
  if [[ "${currentImageEscaped}" == "bitnami\\/kubeapps-kubeapps-apis" ]]; then
    currentImageEscaped="bitnami\\/kubeapps-apis"
  fi
  local targetImageEscaped="kubeapps\\/${service}"
  sed -i.bk -e '1h;2,$H;$!d;g' -re \
    's/repository:\s+'"${currentImageEscaped}"'\r?\n\s{4}tag:\s+\S*/repository: '"${targetImageEscaped}"'\n    tag: latest/g' \
    "${VALUES_FILE}"
}

retag dashboard
retag apprepository-controller
retag asset-syncer
retag pinniped-proxy
retag kubeapps-apis
retag oci-catalog
rm -f "${VALUES_FILE}.bk"

ASSET_NAME="kubeapps-${TAG}.tar.gz"
 tar -C "${WORKDIR}" -czf "${ASSET_NAME}" kubeapps

# Output the path to the asset so the caller can upload it
echo "${ASSET_NAME}"
