# Local Charts for e2e Tests

Place charts under `external/charts/<chart-name>/<version>/` so the e2e `pullBitnamiChart` function can package them locally (avoiding remote Bitnami downloads).

Example structure:
```
external/charts/apache/11.4.28/Chart.yaml
external/charts/apache/11.4.28/values.yaml
external/charts/apache/11.4.28/templates/*
external/charts/apache/11.4.29/Chart.yaml
...
```

During tests, the script stages the requested version directory and packages it as `<chart>-<version>.tgz`, updating the version field inside `Chart.yaml` to match the requested version.

If the version-specific directory is missing, the test run aborts with an error showing the expected path.

Notes:
- You can keep multiple versions side-by-side.
- `allowInsecureImages` in values.yaml will be flipped to `true` during packaging if needed.
- Ensure any line `metrics.image.repository=bitnami/apache-exporter` appears exactly for the sed replacement logic in `pushChart`.
