#!/usr/bin/env bash
# Copyright 2024 the Kubeapps contributors.
# SPDX-License-Identifier: Apache-2.0
# Enhanced diagnostics for failed E2E runs.
# Usage: diagnose-e2e-failure.sh [namespace] [release]
set -euo pipefail
NS=${1:-kubeapps}
RELEASE=${2:-kubeapps-ci}
RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

section() { echo -e "\n==================== $1 ===================="; }
warn() { echo -e "${YELLOW}WARN:${NC} $*"; }
error() { echo -e "${RED}ERROR:${NC} $*"; }

section "Basic cluster info"
kubectl version --short || true
kubectl get nodes -o wide || true

section "Namespace ${NS} summary"
kubectl get all -n "${NS}" || true
kubectl get pods -n "${NS}" -o wide || true

section "Kubeapps Deployments"
kubectl get deploy -n "${NS}" -l app.kubernetes.io/instance="${RELEASE}" -o wide || true

section "KubeappsAPIs pods logs (last 300 lines each)"
for p in $(kubectl get pods -n "${NS}" -l app.kubernetes.io/component=kubeappsapis -o name 2>/dev/null); do
  echo "--- Logs for $p ---"
  kubectl logs -n "${NS}" "$p" --tail=300 || true
  echo
  echo "--- Previous logs for $p (if any) ---"
  kubectl logs -n "${NS}" "$p" -p --tail=100 || true
  echo
  kubectl describe "$p" -n "${NS}" | sed -n '/Events:/,$p' || true
  echo
 done

section "PostgreSQL pods"
POSTGRES_LABEL="app.kubernetes.io/name=postgresql"
PSQL_PODS=$(kubectl get pods -n "${NS}" -l ${POSTGRES_LABEL} -o name 2>/dev/null || true)
if [[ -z "${PSQL_PODS}" ]]; then
  warn "No PostgreSQL pods found with label ${POSTGRES_LABEL} in namespace ${NS}";
else
  kubectl get pods -n "${NS}" -l ${POSTGRES_LABEL} -o wide || true
  echo
  kubectl get sts -n "${NS}" -l ${POSTGRES_LABEL} || true
  for p in ${PSQL_PODS}; do
    echo "--- Describe for $p ---"
    kubectl describe "$p" -n "${NS}" | sed -n '/Containers:/,$p' || true
    echo "--- Recent events for $p ---"
    kubectl describe "$p" -n "${NS}" | sed -n '/Events:/,$p' || true
    echo "--- Logs (tail 200) for $p ---"
    kubectl logs -n "${NS}" "$p" --tail=200 || true
    echo "--- Previous logs (tail 50) for $p ---"
    kubectl logs -n "${NS}" "$p" -p --tail=50 || true
    echo "--- pg_isready inside $p ---"
    kubectl exec -n "${NS}" "$p" -- bash -c 'pg_isready -U postgres || pg_isready' 2>&1 || true
  done
  echo
  section "PostgreSQL container images"
  kubectl get pods -n "${NS}" -l ${POSTGRES_LABEL} -o jsonpath='{range .items[*]}{.metadata.name} {.spec.containers[0].image}{"\n"}{end}' 2>/dev/null || true
fi

section "Services & Endpoints"
{ kubectl get svc -n "${NS}"; echo; kubectl get ep -n "${NS}"; } || true

section "Network Policies"
kubectl get networkpolicy -n "${NS}" || true

section "PVC/PV"
kubectl get pvc -n "${NS}" || true
kubectl get pv | grep "${RELEASE}" || true

section "Recent namespace events (last 200)"
# Sort by lastTimestamp if available
kubectl get events -n "${NS}" --sort-by=.lastTimestamp 2>/dev/null | tail -n 200 || true

section "PostgreSQL readiness inference"
if [[ -n "${PSQL_PODS}" ]]; then
  for p in ${PSQL_PODS}; do
    phase=$(kubectl get "$p" -n "${NS}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "?")
    readyCond=$(kubectl get "$p" -n "${NS}" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null || echo "?")
    if [[ "$phase" != "Running" || "$readyCond" != "True" ]]; then
      warn "Pod $p not ready (phase=$phase ready=$readyCond)"
    fi
  done
fi

section "Suggest remediation"
if [[ -n "${PSQL_PODS}" ]]; then
  IMG=$(kubectl get pods -n "${NS}" -l ${POSTGRES_LABEL} -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null || echo "")
  if [[ "$IMG" == docker.io/bitnami/postgresql:* || "$IMG" == bitnami/postgresql:* ]]; then
    warn "PostgreSQL image is from docker.io/bitnami. Consider switching to the internal deprecated mirror by setting --set postgresql.image.registry=ghcr.io --set postgresql.image.repository=sap/kubeapps/bitnami-deprecated-postgresql --set postgresql.image.tag=$POSTGRESQL_VERSION (if env var exported)."
  fi
fi

section "Done diagnostics"
