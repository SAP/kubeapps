# Carvel (kapp-controller) Re-Enablement

## Status: COMPLETED

The Carvel (kapp-controller) plugin has been re-added to Kubeapps. Enable it via `packaging.carvel.enabled=true` in the Helm chart values.

## Dependency Versions

```
carvel.dev/kapp                v0.64.2
carvel.dev/kapp-controller     v0.58.1
carvel.dev/vendir              v0.44.0
```

**Note**: These are the same versions as before the removal. Upgrading to newer versions (e.g., kapp v0.65+, kapp-controller v0.59+) is blocked by k8s client-go version conflicts — our repo pins k8s.io/* to v0.30.1, while newer Carvel versions require v0.35+. This can be revisited when the repo's k8s dependency pin is updated.

## Key Technical Decisions

### Module path conflict workaround

`carvel.dev/kapp v0.64.2` transitively depends on the old `github.com/vmware-tanzu/carvel-kapp-controller v0.51.0`, which registers the same Kubernetes scheme types as our direct dependency `carvel.dev/kapp-controller v0.58.1`. This causes a double-registration panic at test time.

**Fix**: The `carvel.dev/kapp-controller/pkg/packageinstall` import was the only thing pulling in the conflicting `pkg/config` package. We only used `packageinstall.DowngradableAnnKey` (the string `"packaging.carvel.dev/downgradable"`), so we inlined the constant in `server_utils.go` and removed the import entirely.

### Plugin naming

The plugin retains its original name `kapp_controller.packages` (v1alpha1). See "Future Considerations" below for a potential rename to `carvel.packages`.

### go.mod replace directives added

- `github.com/google/gnostic-models => github.com/google/gnostic-models v0.6.9` — prevents `go.yaml.in/yaml/v3` vs `gopkg.in/yaml.v3` type mismatch
- `k8s.io/kube-openapi => k8s.io/kube-openapi v0.0.0-20240228011516-70dd3763d340` — prevents `structured-merge-diff/v6` incompatibility

---

## Background

Carvel support was removed from Kubeapps in Oct–Dec 2025 because the Carvel Go dependencies could not be upgraded. The removal happened across these commits:

| Date       | Commit      | Summary |
|------------|-------------|---------|
| 2025-09-30 | `8134a7ab3` | **migrate carvel-dev to new location** — last state of the plugin before removal |
| 2025-10-02 | `e46f91e06` | **remove carvel support** — main removal commit (43 files) |
| 2025-10-06 | `2b06eeaf9` | **remove kapp-controller reference** — leftover cleanup |
| 2025-10-30 | `a22265d91` | **disable carvel test group** — CI cleanup |
| 2025-11-20 | `9e85d9d7b` | **remove carvel further references** — broad cleanup (41 files) |
| 2025-12-01 | `2bb90e0a1` | **fix operator test after carvel removal** — e2e fix |

---

## Future Considerations

### 1. Plugin rename: `kapp_controller.packages` → `carvel.packages`

The current plugin name `kapp_controller.packages` reflects the underlying Kubernetes controller, but the Carvel project branding has evolved. A rename to `carvel.packages` would be more consistent with how users think about the ecosystem. This would require:
- Renaming the directory `plugins/kapp_controller/` → `plugins/carvel/`
- Updating the proto package name and regenerating gRPC code
- Updating all dashboard references (PluginNames, gRPC client methods, etc.)
- Updating the `.so` plugin filename and Dockerfile
- Migration path for existing deployments

### 2. Upgrade Carvel dependencies to latest

Once the repo's k8s.io/* pin is updated beyond v0.30.1, newer Carvel versions can be used:
- `carvel.dev/kapp-controller v0.59.7` (latest as of 2026-04) — still uses k8s client-go v0.30.1
- `carvel.dev/kapp v0.65+` — requires k8s client-go v0.35+, incompatible with current pin
- When kapp updates its imports from `github.com/vmware-tanzu/carvel-kapp-controller` to `carvel.dev/kapp-controller`, the inlined `downgradableAnnKey` constant can be reverted to use the import

### 3. Restore documentation

The tutorial `managing-carvel-packages.md` and associated screenshots were removed. New documentation and screenshots should be created when the feature is fully validated.
