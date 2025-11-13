---
sidebar_position: 1
title: Intro
---

# Introduction to Kubeapps

Welcome to **Kubeapps** - a web-based application dashboard for Kubernetes clusters that makes it easy to deploy, manage, and upgrade applications on your Kubernetes environment.

## What is Kubeapps?

Kubeapps is an open-source project that provides a simple, web-based UI for deploying and managing applications on Kubernetes clusters. It acts as a central hub for discovering, installing, and managing Helm charts and other Kubernetes applications.

## Key Features

- **Application Catalog**: Browse and deploy applications from Helm repositories
- **Easy Installation**: One-click deployment of complex applications
- **Application Management**: Upgrade, rollback, and delete applications through a web interface
- **Multi-Cluster Support**: Manage applications across multiple Kubernetes clusters
- **RBAC Integration**: Role-based access control for secure multi-user environments
- **Custom App Repositories**: Add your own Helm repositories and application sources

## Getting Started

To get started with Kubeapps, you'll need:

- A running Kubernetes cluster
- `kubectl` configured to access your cluster
- Helm 3.x installed (optional, for advanced usage)

Check out our [Installation Guide](./tutorials/getting-started.md) to deploy Kubeapps on your cluster in minutes.

## Use Cases

Kubeapps is perfect for:

- **Development Teams**: Quickly spin up databases, monitoring tools, and development environments
- **Platform Engineers**: Provide self-service application deployment capabilities
- **Operations Teams**: Centralized application lifecycle management
- **Learning**: Explore the Kubernetes ecosystem through a user-friendly interface

## Architecture

Kubeapps consists of several components working together:

- **Dashboard**: React-based web UI
- **API Service**: Backend API for application management
- **Helm Integration**: Direct integration with Helm for package management
- **Authentication**: Support for OIDC and other authentication methods

Ready to dive in? Start with our [Kubeapps Background](./background/) or explore the [Reference Documentation](./reference/) for detailed configuration options.
