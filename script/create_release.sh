#!/usr/bin/env bash

# Copyright 2021-2022 the Kubeapps contributors.
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

# Build release asset from the checked-out repository only
ASSET_PATH=$(bash "$(dirname "$0")/prepare_release_asset.sh" "${TAG}")

# Create the release in draft mode and attach the packaged chart asset
 gh release create -R "${KUBEAPPS_REPO}" -d "${TAG}" -t "${TAG}" -F "script/tpl/release_notes.md" "${ASSET_PATH}"
