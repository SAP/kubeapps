---
title: Kubeapps Helm Repository (Pre-release / Dev)
description: How to add the Kubeapps pre-release Helm repository and what it contains.
---

# Kubeapps Helm Repository (Pre-release / Dev)

This page documents the pre-release Helm repository for Kubeapps. It includes an `index.yaml` with chart packages built from non-stable tags (e.g., `v3.0.0-rc1`).

- Dev index: [index.yaml](https://sap.github.io/kubeapps/helm/dev/index.yaml)
- Repo URL for Helm: `https://sap.github.io/kubeapps/helm/dev`

## Add the dev repository

```bash
helm repo add sap-kubeapps-dev https://sap.github.io/kubeapps/helm/dev
helm repo update
helm search repo sap-kubeapps-dev
```

## Install a pre-release chart

```bash
# Replace VERSION with the desired pre-release version
helm install my-kubeapps sap-kubeapps-dev/kubeapps --namespace kubeapps --create-namespace --version VERSION
```

## Contents

The dev repository contains:

- **index.yaml**: Helm repository index for pre-releases (tags starting with `v` but not matching strict `vX.Y.Z`).
- **Chart packages (.tgz)**: Kubeapps chart archives produced from pre-release tags (e.g., rc, beta).

> Note: The dev index and packages are refreshed by a GitHub Actions workflow when a pre-release is published, and can also be rebuilt manually.

## Troubleshooting

- If `helm repo add` fails, ensure you can access [index.yaml](/helm/dev/index.yaml) in your browser.
- Run `helm repo update` to refresh local cache.
- Pin a specific pre-release with `--version` to avoid surprises.
