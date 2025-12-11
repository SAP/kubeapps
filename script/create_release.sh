#!/usr/bin/env bash

# Copyright 2021-2025 the Kubeapps contributors.
# SPDX-License-Identifier: Apache-2.0

set -o errexit
set -o nounset
set -o pipefail

TAG=${1:?Missing tag}
KUBEAPPS_REPO=${2:?Missing kubeapps repo}
GH_TOKEN=${GH_TOKEN:?Missing GitHub token}

if [[ -z "${TAG}" ]]; then
  echo "A git tag is required for creating a release"
  exit 1
fi

echo "Building release asset for tag ${TAG}..."
# Build release asset from the checked-out repository using helm package
ASSET_PATH=$(bash "$(dirname "$0")/prepare_release_asset.sh" "${TAG}")

if [[ ! -f "${ASSET_PATH}" ]]; then
  echo "ERROR: Asset file not found at ${ASSET_PATH}" >&2
  exit 1
fi

echo "Asset created at: ${ASSET_PATH}"

# Check if release already exists (e.g., manually created)
if gh release view "${TAG}" -R "${KUBEAPPS_REPO}" &>/dev/null; then
  echo "Release ${TAG} already exists, uploading asset..."
  gh release upload "${TAG}" "${ASSET_PATH}" -R "${KUBEAPPS_REPO}" --clobber
else
  echo "Creating new release ${TAG} in draft mode..."
  # Create the release in draft mode and attach the packaged chart asset
  RELEASE_NOTES="script/tpl/release_notes.md"
  if [[ -f "${RELEASE_NOTES}" ]]; then
    gh release create -R "${KUBEAPPS_REPO}" -d "${TAG}" -t "${TAG}" -F "${RELEASE_NOTES}" "${ASSET_PATH}"
  else
    gh release create -R "${KUBEAPPS_REPO}" -d "${TAG}" -t "${TAG}" "${ASSET_PATH}"
  fi
fi

echo "Release asset uploaded successfully!"
