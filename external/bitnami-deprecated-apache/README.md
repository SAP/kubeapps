# Bitnami Deprecated Apache

This directory contains the deprecated Bitnami Apache HTTP Server container image that is no longer available in the public Bitnami catalog.

## Purpose

This deprecated image is maintained to support Kubeapps e2e tests that depend on the Apache chart, which references Docker images that Bitnami has removed from their public catalog.

## Structure

```
bitnami-deprecated-apache/
├── README.md
└── apache/
    ├── README.md
    ├── docker-compose.yml
    └── 2.4/
        └── debian-12/
            ├── Dockerfile          # ← You need to copy the original here
            ├── docker-compose.yml
            ├── prebuildfs/         # ← Copy original prebuildfs content here
            └── rootfs/             # ← Copy original rootfs content here
```

## Next Steps

1. Copy the original Dockerfile from: https://github.com/bitnami/containers/tree/main/bitnami/apache/2.4/debian-12/
2. Copy the prebuildfs and rootfs directories from the same location
3. Build and push the image to the GitHub Container Registry as `ghcr.io/sap/kubeapps/bitnami-deprecated-apache:2.4`

## Usage

The e2e tests have been updated to automatically use this deprecated image instead of the unavailable public Bitnami image.
