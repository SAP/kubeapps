<!--
Copyright 2026 the Kubeapps contributors.
SPDX-License-Identifier: Apache-2.0
-->

# Carvel (kapp-controller) Re-enablement — Findings & Plan

This document records why Carvel/kapp-controller support was removed from this SAP fork of
Kubeapps, how it was brought back, and how to verify it. It supersedes the older
`CARVEL_RE-ENABLEMENT.md` (which was left in place for historical reference but is
inaccurate — it was marked "COMPLETED" while the restore was in fact incomplete and
non-building).

> **Goal of this pass:** restore Carvel with the **smallest possible diff versus the
> pre-removal state** (baseline commit `8134a7ab3`) so the old and new implementations can be
> compared line-for-line and correctness verified. Enhancements are deliberately deferred to a
> later, separate phase.

---

## 1. Why Carvel was removed

Carvel support was removed from this fork in Oct–Dec 2025 because the Carvel Go dependencies
could not be upgraded alongside the Kubernetes client libraries.

The root cause was a **transitive dependency problem**: `carvel.dev/kapp` (and friends) still
pulled in the old `github.com/vmware-tanzu/carvel-kapp-controller` module. That legacy module
transparently forwarded to `carvel.dev`, so both the old and new import paths ended up in the
build. This produced version conflicts and a Kubernetes scheme **double-registration panic**
(the same types registered twice under two module paths), which blocked upgrading `k8s.io/*`
and `controller-runtime`.

Rather than freeze the whole repo's k8s deps, Carvel was excised (backend plugin, dashboard
consumers, Helm chart config, build wiring, CI, and e2e scripts) so the rest of Kubeapps could
move forward.

**Removal commits (source of truth for reverse-applying diffs):**

| Commit       | Scope                                             |
| ------------ | ------------------------------------------------- |
| `e46f91e06`  | Main removal (plugin, build wiring, dashboard)    |
| `2b06eeaf9`  | Follow-up cleanup                                 |
| `a22265d91`  | CI matrix comment-out                             |
| `9e85d9d7b`  | Broad cleanup (chart, dashboard, e2e-test.sh)     |
| `2bb90e0a1`  | Operator e2e packaging-flag flip                  |

Pre-removal baseline: **`8134a7ab3`**.

---

## 2. The upstream fix (the crux)

The maintainer contributed fixes upstream to Carvel so the offending libraries migrated off
`github.com/vmware-tanzu/carvel-kapp-controller` onto `carvel.dev`. The fix for `kapp` landed
on the **`devel` branch** but has **no tagged release yet**.

We therefore pin `kapp` to the **devel commit** carrying the fix
(`c789392c86cc9c3a1c5cb7d3d7add05a8cb15443`), which Go records as a pseudo-version:

```
carvel.dev/kapp            v0.66.1-0.20260817015257-c789392c86cc   // devel fix pin
carvel.dev/kapp-controller v0.59.7
carvel.dev/vendir          v0.45.2
```
(`carvel.dev/ytt` comes in indirectly.)

### Verification that the fix works

The whole point of the devel bump is that `kapp` no longer drags in the legacy
`vmware-tanzu` module. Confirmed:

```console
$ go mod graph | grep 'vmware-tanzu/carvel-kapp-controller'
(no output)

$ go list -deps ./cmd/kubeapps-apis/plugins/kapp_controller/... | grep 'vmware-tanzu/carvel-kapp-controller'
(NOT in build deps)
```

The legacy module is gone from both the module graph and the actual build closure — the
scheme double-registration issue is resolved **properly** (at the dependency level), not
worked around.

---

## 3. Kubernetes 1.35 / controller-runtime migration

With the `vmware-tanzu` conflict removed, the repo now pins:

```
k8s.io/api / apimachinery / client-go   v0.35.1   (also via replace directives)
k8s.io/apiextensions-apiserver          v0.35.1
k8s.io/apiserver                        v0.35.1
sigs.k8s.io/controller-runtime          v0.23.3
```

No `gnostic-models` / `kube-openapi` replace directives were needed — they were only added
speculatively in the old notes; the build is clean without them.

Two `controller-runtime` v0.23 API changes required source fixes:

### 3a. Namespaced-client scope resolution (fluxv2 test)

In controller-runtime v0.23 the namespaced client resolves an object's scope via
`IsObjectNamespaced` → `IsGVKNamespaced`, which does a `RESTMapping` on the **complete GVK,
including the `List` suffix**. The fluxv2 test's fake `RESTMapper` only registered the
singular kinds, so list operations failed with `no matches for kind "HelmRepositoryList"`.

Fix in `cmd/kubeapps-apis/plugins/fluxv2/packages/v1alpha1/test_util_test.go`: register the
`*List` kinds too (`HelmRepositoryKind + "List"`, `HelmChartKind + "List"`,
`HelmReleaseKind + "List"`), all with `apimeta.RESTScopeNamespace`.

### 3b. Inlined `downgradableAnnKey` constant (kapp plugin)

`cmd/kubeapps-apis/plugins/kapp_controller/packages/v1alpha1/server_utils.go` inlines:

```go
const downgradableAnnKey = "packaging.carvel.dev/downgradable"
```

instead of importing `carvel.dev/kapp-controller/pkg/packageinstall.DowngradableAnnKey`.

**Why:** the `packageinstall` package transitively pulls in
`carvel.dev/kapp-controller/pkg/reconciler`, which does **not** compile against
controller-runtime v0.23 — its `handler.TypedEventHandler` now requires two type arguments.
The constant's value is part of kapp-controller's public API and is stable across versions,
so inlining is safe. This is the **one intentional source deviation** from the pre-removal
code and is annotated with a rationale comment in place.

> Note: this differs from the original (pre-removal) reason for concern about
> `packageinstall`, which was the double-registration conflict. That conflict is now gone;
> the remaining blocker is purely the `reconciler` package's incompatibility with
> controller-runtime v0.23. If a future kapp-controller release fixes `reconciler`, this
> inline can be reverted to the upstream import for an exact match.

---

## 4. What was restored

Restored by **reverse-applying the removal-commit diffs** (byte-identical to baseline
wherever the content was a pure deletion), so the new diff is maximally comparable:

- **Go deps** — `go.mod` / `go.sum`: kapp (devel pin) + kapp-controller + vendir.
- **Backend plugin** — `cmd/kubeapps-apis/plugins/kapp_controller/packages/v1alpha1/*.go`
  (+ tests), proto `cmd/kubeapps-apis/proto/.../kapp_controller/...`, generated Go
  `cmd/kubeapps-apis/gen/.../kapp_controller/...`.
- **Build wiring** — `cmd/kubeapps-apis/Dockerfile` (kapp `-buildmode=plugin` stanza + COPY
  of `kapp-controller-packages-v1alpha1-plugin.so`), `cmd/kubeapps-apis/Makefile`
  (`build-plugins` line).
- **Dashboard** — generated TS client `dashboard/src/gen/.../kapp_controller/...` plus all
  hand-written consumers (29 files: `types.ts`, `utils.ts`, `KubeappsGrpcClient.ts`,
  `PackageRepositoriesService.ts`, `Config.ts`, reducers, actions, `Catalog`,
  `PkgRepo*` components, `SelectRepoForm`, `mountWrapper`, `public/config.json`) and their
  tests. `dashboard/src/icons/carvel.svg`.
- **Helm chart** — `values.yaml` (`packaging.carvel.enabled` + the
  `kubeappsapis.pluginConfig.kappController.packages.v1alpha1` block), `_helpers.tpl`
  (carvel → `kapp-controller-packages` enabled-plugin branch),
  `dashboard/configmap.yaml` (`carvelGlobalNamespace`), and the `README.md` param rows
  (added surgically to avoid reverting unrelated SAP↔bitnami rebranding).
- **CI + scripts** — `.github/workflows/kubeapps-general.yaml` (`KAPP_CONTROLLER_VERSION`
  env + `- carvel` in the `tests_group` matrix), `script/e2e-test.sh`
  (`installKappController()`, Carvel tests group, operator-group flag reconciliation),
  `script/makefiles/deploy-dev.mk` (`deploy-kapp-controller[-additional]`),
  `script/run_e2e_tests.sh` (`KAPP_CONTROLLER_VERSION` passthrough).

**No work needed (verified):** plugin loading is fully dynamic (`core/plugins/v1alpha1`
globs `*.so` and calls `RegisterWithGRPCServer`); `plugins_test.go` was never edited and
still expects `kapp_controller.packages`; `make buf-generate` discovers the restored proto
automatically.

---

## 5. What was deferred / out of scope

- **`.github/workflows/gke_e2e_tests.yaml`** — referenced by the old cleanup but the reusable
  GKE workflow was removed separately and **no longer exists** in `HEAD`. Not restored; the
  corresponding GKE version-output passthrough hunks in `kubeapps-general.yaml` were
  intentionally skipped because those jobs are gone.
- **Docs / screenshots** — `managing-carvel-packages.md` and associated images were not
  restored in this pass (documentation-only; no effect on build or tests).
- **Plugin directory rename** (`kapp_controller` → `carvel`) — deliberately *not* done; a
  rename would defeat the "smallest diff / easy comparison" goal. Candidate for the later
  enhancement phase.
- **Newer kapp release** — once the upstream `kapp` fix ships in a tagged release, replace
  the devel pseudo-version pin with the release tag, and consider reverting the inlined
  `downgradableAnnKey` if `pkg/reconciler` becomes v0.23-compatible.

---

## 6. How to verify

```bash
# 1. Plugin compiles + unit tests (incl. plugins_test expecting the kapp plugin)
go test ./cmd/kubeapps-apis/plugins/kapp_controller/... ./cmd/kubeapps-apis/core/plugins/...

# 2. Legacy module is gone (validates the upstream devel fix)
go mod graph | grep 'vmware-tanzu/carvel-kapp-controller'          # -> no output
go list -deps ./cmd/kubeapps-apis/plugins/kapp_controller/... \
  | grep 'vmware-tanzu/carvel-kapp-controller'                     # -> no output

# 3. The .so plugin builds
cd cmd/kubeapps-apis && make build-plugins                          # or: make kubeapps/kubeapps-apis

# 4. Generated code is stable against the restored proto
make buf-generate                                                   # -> no diff

# 5. Frontend restored & green
cd dashboard && CI=true yarn test && yarn lint

# 6. (Optional, needs a cluster) Carvel e2e group
make deploy-dev && make deploy-kapp-controller
TESTS_GROUP=carvel script/e2e-test.sh
```

Current status: steps 1–2 pass; the kapp plugin builds as a ~84 MB `.so`; all plugin and
core tests are green.
