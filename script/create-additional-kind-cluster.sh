#!/usr/bin/env bash

# Copyright 2022 the Kubeapps contributors.
# SPDX-License-Identifier: Apache-2.0

set -uo pipefail
IFS=$'\t\n'

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null && pwd)"
K8S_KIND_VERSION=${K8S_KIND_VERSION:?"not provided"}
DEFAULT_DEX_IP=${DEFAULT_DEX_IP:-"172.18.0.2"}
CLUSTER_CONFIG_FILE=${CLUSTER_CONFIG_FILE:-"${ROOT_DIR}/site/content/docs/latest/reference/manifests/kubeapps-local-dev-additional-apiserver-config.yaml"}
CLUSTER_NAME=${CLUSTER_NAME:-"kubeapps-ci-additional"}
KUBECONFIG=${KUBECONFIG:-"${HOME}/.kube/kind-config-kubeapps-ci-additional"}
CONTEXT=${CONTEXT:-"kind-kubeapps-ci-additional"}

. "${ROOT_DIR}/script/lib/liblog.sh"

info "K8S_KIND_VERSION: ${K8S_KIND_VERSION}"
info "DEFAULT_DEX_IP: ${DEFAULT_DEX_IP}"
info "CLUSTER_CONFIG_FILE: ${CLUSTER_CONFIG_FILE}"
info "CLUSTER_NAME: ${CLUSTER_NAME}"
info "KUBECONFIG: ${KUBECONFIG}"
info "CONTEXT: ${CONTEXT}"

function createAdditionalKindCluster() {
  kind create cluster --image "kindest/node:${K8S_KIND_VERSION}" --name "${CLUSTER_NAME}" --config="${CLUSTER_CONFIG_FILE}" --kubeconfig "${KUBECONFIG}" --retain --wait 120s &&
  kubectl apply --context "${CONTEXT}" --kubeconfig "${KUBECONFIG}" --kubeconfig "${KUBECONFIG}" -f "${ROOT_DIR}/site/content/docs/latest/reference/manifests/kubeapps-local-dev-users-rbac.yaml" &&
  kubectl apply --context "${CONTEXT}" --kubeconfig "${KUBECONFIG}" --kubeconfig "${KUBECONFIG}" -f "${ROOT_DIR}/site/content/docs/latest/reference/manifests/kubeapps-local-dev-namespace-discovery-rbac.yaml" &&
  # Install MetalLB for LoadBalancer support
  kubectl --context "${CONTEXT}" --kubeconfig "${KUBECONFIG}" apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml &&
  kubectl wait --context "${CONTEXT}" --kubeconfig "${KUBECONFIG}" --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=120s &&
  # Configure MetalLB IP address pool (different range for additional cluster)
  cat <<EOF | kubectl --context "${CONTEXT}" --kubeconfig "${KUBECONFIG}" apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: example
  namespace: metallb-system
spec:
  addresses:
  - 172.19.255.200-172.19.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: empty
  namespace: metallb-system
EOF
  sleep 5 &&
  kubectl create rolebinding kubeapps-view-secret-oidc --context "${CONTEXT}" --kubeconfig "${KUBECONFIG}" --role view-secrets --user oidc:kubeapps-user@example.com &&
  kubectl create clusterrolebinding kubeapps-view-oidc --context "${CONTEXT}" --kubeconfig "${KUBECONFIG}" --clusterrole=view --user oidc:kubeapps-user@example.com &&
  echo "Additional cluster created"
}

sed -i "s/172.18.0.2/$DEFAULT_DEX_IP/g" "${CLUSTER_CONFIG_FILE}"
{
  echo "Creating additional cluster..."
  createAdditionalKindCluster
} || {
  echo "Additional cluster creation failed, retrying..."
  kind delete clusters kubeapps-ci-additional || true
  createAdditionalKindCluster
} || {
  echo "Error while creating the additional cluster after retry"
  exit 1
}