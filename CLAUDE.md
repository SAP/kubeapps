# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kubeapps is a web-based UI for deploying and managing applications on Kubernetes clusters. It supports Helm charts and Flux-managed Helm releases. This is a SAP-maintained fork of the archived VMware Tanzu Kubeapps project (maintenance focus: security fixes, compatibility updates, critical bugs).

## Build Commands

```bash
# Build all Docker images
make all

# Build specific component
make kubeapps/dashboard
make kubeapps/apprepository-controller
make kubeapps/asset-syncer
make kubeapps/pinniped-proxy
make kubeapps/kubeapps-apis
make kubeapps/oci-catalog

# Custom image tag
make IMAGE_TAG=v1.0.0 kubeapps/dashboard
```

## Testing Commands

```bash
# Go unit tests
make test

# Database integration tests (requires PostgreSQL)
ENABLE_PG_INTEGRATION_TESTS=1 make test-db

# Dashboard tests
make test-dashboard
# Or directly:
cd dashboard && yarn test           # Watch mode
cd dashboard && CI=true yarn test   # CI mode (no watch)

# E2E tests (Playwright)
cd integration && yarn test
```

## Linting Commands

```bash
# All linters
make lint

# Individual linters
./script/linters/license-linter.sh   # Apache-2.0 headers
./script/linters/yaml-linter.sh
./script/linters/golang-linter.sh

# Dashboard linting
cd dashboard && yarn lint            # ESLint + StyleLint
cd dashboard && yarn prettier        # Format code
```

## Protobuf Generation

```bash
make buf-generate      # Generate Go/TS code from protos
make buf-mod-update    # Update buf dependencies
```

## Local Development

```bash
# Create local Kind cluster with OIDC
make multi-cluster-kind

# Deploy Kubeapps with Dex
make deploy-dev

# Dashboard development
cd dashboard
yarn install
yarn start    # Dev server with hot reload
```

## Architecture

### Microservices (in `/cmd`)
- **kubeapps-apis** - Central gRPC API gateway (Go), uses plugin system for Helm/Flux support
- **apprepository-controller** - Kubernetes controller for app repositories (Go)
- **asset-syncer** - Scans Helm repos, populates metadata in PostgreSQL (Go)
- **pinniped-proxy** - Optional OIDC proxy (Rust)
- **oci-catalog** - Optional OCI registry catalog service (Rust)

### Frontend (`/dashboard`)
- React 17 with TypeScript
- Redux for state management
- Clarity Design System for UI components
- Connect (gRPC-web) for API communication
- Generated gRPC clients in `/dashboard/src/gen` (do not edit)

### Shared Libraries (`/pkg`)
Common Go packages for chart utilities, database, Helm integration, Kubernetes client, HTTP client

### Plugin System
`kubeapps-apis` uses a pluggable architecture with plugins in `/cmd/kubeapps-apis/plugins`:
- `helm/packages/v1alpha1` - Helm packages
- `fluxv2/packages/v1alpha1` - Flux v2 packages
- `resources/v1alpha1` - Kubernetes resources

## Key Patterns

**gRPC/Protobuf API**: Proto files in `/cmd/kubeapps-apis/proto` and `/cmd/oci-catalog/proto`. Always run `make buf-generate` after modifying `.proto` files.

**Database**: PostgreSQL for Helm metadata, Redis for Flux. DB tests run sequentially due to shared schema.

**License Headers**: Required on all source files (Apache-2.0). Format:
```
Copyright YYYY-YYYY the Kubeapps contributors.
SPDX-License-Identifier: Apache-2.0
```

## Commit Requirements

- GPG-signed commits required
- Include `Signed-off-by: <Name> <email>` line
- Run linters before committing
