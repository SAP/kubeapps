#!/usr/bin/env bash
# Prepares a release asset as a Helm package (.tgz) with proper Helm chart structure,
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

# Check if helm is available
if ! command -v helm &> /dev/null; then
  echo "ERROR: helm command not found. Please install Helm to package charts." >&2
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

# Package the chart using helm package to create a proper Helm chart tarball
# The packaged file will be named according to the chart name and version in Chart.yaml
PACKAGE_OUTPUT=$(helm package "${WORKDIR}/kubeapps" -d "${PROJECT_DIR}" 2>&1)
PACKAGE_FILE=$(echo "${PACKAGE_OUTPUT}" | grep -oP 'Successfully packaged chart and saved it to: \K.*' || true)

if [[ -z "${PACKAGE_FILE}" ]]; then
  # Fallback: find the most recently created .tgz in the project directory
  PACKAGE_FILE=$(find "${PROJECT_DIR}" -maxdepth 1 -name "kubeapps-*.tgz" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)
fi

if [[ ! -f "${PACKAGE_FILE}" ]]; then
  echo "ERROR: Failed to create Helm package" >&2
  exit 1
fi

# Output the path to the packaged chart
echo "${PACKAGE_FILE}"
