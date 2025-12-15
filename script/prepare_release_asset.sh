#!/usr/bin/env bash

# Copyright 2022 the Kubeapps contributors.
# SPDX-License-Identifier: Apache-2.0

# Prepares a release asset as a Helm package (.tgz) with proper Helm chart structure,
# with appVersion set to the release tag and images retagged to the same release version.
# Usage: prepare_release_asset.sh <tag>
# Example: prepare_release_asset.sh v3.0.0-rc4
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

# Set appVersion to the actual tag version (strip 'v' prefix if present)
APP_VERSION="${TAG#v}"
sed -i.bk "s/^appVersion: .*/appVersion: ${APP_VERSION}/" "${WORKDIR}/kubeapps/Chart.yaml"
rm -f "${WORKDIR}/kubeapps/Chart.yaml.bk"
echo "Set appVersion to: ${APP_VERSION}"

# Retag images in values.yaml to use the release tag
# Current format: registry: ghcr.io, repository: sap/kubeapps/<service>, tag: vX.Y.Z
VALUES_FILE="${WORKDIR}/kubeapps/values.yaml"

retag() {
  local service=$1
  # Replace any existing tag with the new release tag
  # Match pattern: tag: <anything> after repository: sap/kubeapps/<service>
  sed -i.bk "/repository: sap\/kubeapps\/${service}/,/tag:/ s/tag: .*/tag: ${TAG}/" "${VALUES_FILE}"
}

retag dashboard
retag apprepository-controller
retag asset-syncer
retag pinniped-proxy
retag kubeapps-apis
retag oci-catalog
rm -f "${VALUES_FILE}.bk"
echo "Retagged all images to: ${TAG}"

# Copy LICENSE file to the chart directory
if [[ -f "${PROJECT_DIR}/LICENSE" ]]; then
  cp "${PROJECT_DIR}/LICENSE" "${WORKDIR}/kubeapps/LICENSE"
  echo "Added LICENSE file to chart package"
else
  echo "WARNING: LICENSE file not found at ${PROJECT_DIR}/LICENSE" >&2
fi

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
