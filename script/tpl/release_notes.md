Kubeapps vX.Y.Z (chart version A.B.C) is a <major|minor|patch> release that... <!-- ADD SUMMARY HERE -->

## Installation

To install this release, ensure you add the [SAP Kubeapps chart repository](https://sap.github.io/kubeapps/helm) to your local Helm cache:

```bash
helm repo add sap-kubeapps https://sap.github.io/kubeapps/helm
helm repo update
```

Install the Kubeapps Helm chart:

```bash
kubectl create namespace kubeapps
helm install kubeapps --namespace kubeapps sap-kubeapps/kubeapps
```

To get started with Kubeapps, check out this [walkthrough](https://sap.github.io/kubeapps/docs/tutorials/getting-started).

<!-- CLICK ON THE "Auto-generate release notes" BUTTON -->
