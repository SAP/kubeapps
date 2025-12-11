# CI configuration

This document describes the CI configuration for the Kubeapps project. The [Understanding CI configuration](#understanding-ci-configuration) section provides a high-level overview of the CI configuration, while the [Credentials](#credentials) section describes how to configure the credentials needed to run the CI.

## Understanding CI configuration

Kubeapps leverages GitHub Actions (GHA) for its CI processes: running the tests (both unit and integration tests), building and pushing the images,
and syncing the Helm chart with the official [Bitnami chart](https://github.com/bitnami/charts/tree/main/bitnami/kubeapps).
The following image depicts how a successful workflow looks like after pushing a commit to the main branch.

![CI workflow after pushing to the main branch](/img/ci-workflow-main.png "CI workflow after pushing to the main branch")

The different parts involved in the GHA configuration are:

* **Workflows:** these are what we commonly call `pipelines`. A workflow is a directed acyclic graph composed of several jobs, and it can be automatically
triggered under different events and conditions (for example, upon a commit in the main branch, when a new PR is filed, etc). Some workflows can also run
on-demand or on-schedule, and can be called from another top-level workflows, so they can be reused to avoid code duplication.
* **Job:** a logical unit consisting on a series of steps that are executed in sequence to perform a specific task (for example, run the unit tests).
Each job runs in a isolated environment, usually a virtual machine or a container.
* **Step:** the minimal unit of execution in GHA. An step can consist of a call to an action or the execution of one or
multiple shell commands (including the execution of script files).
* **Action:** a reusable piece of code in charge of executing a specific task. It is usually composed by multiple steps,
and there are mainly two types of actions:
  * **Publicly available:** those actions usually developed by a third party, that are publicly available on the internet
  and usually published in the [GitHub Marketplace](https://github.com/marketplace?type=actions), so can just call and run them
  (for example, `actions/checkout`).
  * **Custom actions:** actions we can create to define reusable tasks avoiding code duplication. They are defined in
  yaml files located in `/.github/actions/action-name/action.yml` (see the [srp-source-provenance action](https://github.com/vmware-tanzu/kubeapps/blob/main/.github/actions/srp-source-provenance/action.yml).

### Workflows

Currently, you can find the following top-level workflows:

* **[Main Pipeline](https://github.com/vmware-tanzu/kubeapps/blob/main/.github/workflows/kubeapps-main.yaml):** it runs automatically when a new PR is filed and when a new commit is pushed to the `main` branch.
Internally calls the `Kubeapps general` reusable workflow.
* **[Release Pipeline](https://github.com/vmware-tanzu/kubeapps/blob/main/.github/workflows/kubeapps-release.yml):** it runs automatically when a new tag matching the version pattern `vX.Y.Z` is pushed to the repository.
Internally calls the `Kubeapps general` reusable workflow.
* **[CodeQL Analysis](https://github.com/vmware-tanzu/kubeapps/blob/main/.github/workflows/codeql-analysis.yml):** it executes the CodeQL security analysis, runs automatically depending on several conditions/events,
and is not part of the `Kubeapps General` workflow due to the big amount of time it takes to complete.
* **[Kubeapps Custodian Rules](https://github.com/vmware-tanzu/kubeapps/blob/main/.github/workflows/ci-custodian-rules.yaml):** it executes some custodian rules for the project, runs automatically on-schedule.
* **[Project automation](https://github.com/vmware-tanzu/kubeapps/blob/main/.github/workflows/add-issues-to-project.yaml):** it runs automatically when new issues are created in the Kubeapps repository and adds them to the Kubeapps project.

Besides that, you have the following reusable workflows:

* **[Kubeapps General](https://github.com/vmware-tanzu/kubeapps/blob/main/.github/workflows/kubeapps-general.yaml):** it contains the definition of the whole pipeline, containing multiple jobs that run depending on different conditions (like the event that triggered the workflow, or the repository or branch from which it was triggered), so it supports multiple flows/scenarios. It receives some input parameters that allow you to tune its behavior (for example, whether e2e tests should be run or not).
* **[Linters](https://github.com/vmware-tanzu/kubeapps/blob/main/.github/workflows/linters.yml):** it contains the definition of the jobs that execute multiple linters for the project.

### Custom Actions

Currently, we only have a custom action: [srp-source-provenance](https://github.com/vmware-tanzu/kubeapps/blob/main/.github/actions/srp-source-provenance/action.yml). This action contains the logic required for
generating and submitting the source provenance, so we comply with VMware SRP (Secure Release Pipeline) requirements.

### Jobs

The jobs you can find in the `Kubeapps General` workflow are mainly:

* `setup`: we perform some setup logic in this job and generate some output data that is consumed by other dependant jobs.
The reason why you need this job is that GHA doesn't allow to directly use environment variables in some contexts, for example,
you cannot directly pass an environment variable in the `with` block of an action call, so we use this workaround to overcome
that situation. Also, you cannot dynamically set the value of an environment variable declared in an `env` block, so we generate
output variables for those cases.
* `linters`: it simply calls the reusable workflow where all linters are declared ([linters.yml](https://github.com/vmware-tanzu/kubeapps/blob/main/.github/workflows/linters.yml)).
* `linters_result`: even though all the linter jobs are defined in the [linters.yml](https://github.com/vmware-tanzu/kubeapps/blob/main/.github/workflows/linters.yml)
  file, it is not practical to set each of them as a compulsory status check in the branch protection rules, so this job is
  intended to serve as a global status check for all linters.
* `test_go`: it runs every unit test for those projects written in Golang (that is, it runs `make test`) as well as it runs some DB-dependent tests.
* `test_dashboard`: it runs the dashboard linter and unit tests (`yarn lint` and `yarn test`)
* `test_pinniped_proxy`: it runs the Rust unit tests of the pinniped-proxy project (`cargo test`).
* `test_chart_render`: it tests that the Helm chart is properly rendered.
* `build_docker_images`: it builds the docker images for several services/components.
* `build_dashboard_image`: it builds the docker image for `dashboard`.
* `build_e2e_runner_image`: it builds the docker image we use to run the integration/e2e tests.
* `push_dev_images`: it pushes the development images to Dockerhub. In this context, we call development images to those
images generated from whatever commit from a feature branch. To avoid polluting the images with all the tags generated
from every single commit, we add the suffix `-ci` to the corresponding image, for example, `kubeapps/dashboard-ci`.
* `local_e2e_tests`: it runs locally (that is, inside the GHA environment) the e2e tests. Please refer to the [e2e tests documentation](./end-to-end-tests.md)
for further information. In this job, before running the script [e2e-test.sh](https://github.com/vmware-tanzu/kubeapps/blob/main/script/e2e-test.sh),
the proper environment is created. Namely:
  * Install the required binaries (kind, kubectl, mkcert, helm).
  * Spin up two Kind clusters.
  * Load the CI images into the cluster.
  * Run the integration tests.
* `local_e2e_tests_result`: it serves as a global status check for the `local_e2e_tests` job. It is needed because the `local_e2e_tests`
job uses a matrix to parameterize and parallelize the `local_e2e_tests` job, so each test group is run in parallel and isolation
(flux, main, etc), and we would need to configure a status check in the branch protections rules for every item in the matrix.
* `push_images`: each time a new commit is pushed to the main branch or a new version tag is created, the CI images
(which have already been built) get re-tagged and pushed to the `kubeapps` account in Dockerhub.
* `release`: every time a new version tag is pushed to the repository, it creates a GitHub release based on the current
tag by running the script [create_release.sh](https://github.com/SAP/kubeapps/blob/main/script/create_release.sh).

Note that this process is independent of the release of the official Bitnami images and chart. These Bitnami images will
be created according to their internal process (so the Golang, Node or Rust versions we define here are not used by them.
Manual coordination is expected here if a major version bump happens to occur).

Also, note it is the Kubeapps team that is responsible for sending a PR to the [chart repository](https://github.com/bitnami/charts/tree/main/bitnami/kubeapps)
each time a new chart version is to be released. Even this process is automatic (using the `sync_chart_to_bitnami` workflow),
Kubeapps maintainers must manually review the draft PR and convert it into a normal one once it is ready for review.

## Credentials

Besides other usual credentials or secrets passed via the GHA user interface, it is important to highlight how we grant
commit and PR access to our robot account `kubeapps-bot <tanzu-kubeapps-team@vmware.com>`. The process is threefold:

* Create a [personal access token](https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token)
with the robot account, granted, at least, with: `repo:status`, `public_repo` and `read:org`. This token must be stored
as the secret `GITHUB_TOKEN` in the `Security > Secrets > Actions` configuration section of the repo.
  * That will allow the GitHub CLI to create PRs from the command line on behalf of our robot account.
  * Also, this token will be used for performing authenticated GitHub API calls.
* Add deployment keys to the repositories to which the CI will commit. Currently, they are `vmware-tanzu/kubeapps` and `kubeapps-bot/charts`.
  * This step allows the robot account to push branches remotely. However, the CI will never push to the `main` branch as
  it always tries to create a pull request.
* Add the robot account GPG key pair in the `GPG_KEY_PUBLIC` and `GPG_KEY_PRIVATE` secrets of the `Security > Secrets > Actions` section of the repo.
  * The public key must be also uploaded in the robot account GPG settings in GitHub. It will be used for signing the commits and tags created by this account.

Besides that, you need to add the secrets `DOCKER_PASSWORD` and `DOCKER_USERNAME` to `Security > Secrets > Dependabot` section of the repo.
You need to add those secrets there to make them available for the workflows triggered from PRs filed by `Dependabot`.
Otherwise, the secrets won't be available and GHA won't be able to push the Docker images to Dockerhub.

### Generating and configuring the deployment keys

This step is only run once, and it is very unlikely to change. However, it is important to know it in case of secret rotations
or further events.

```bash
# COPY THIS CONTENT TO GITHUB (with write access):
## https://github.com/vmware-tanzu/kubeapps/settings/keys
ssh-keygen -t ed25519 -C "tanzu-kubeapps-team@vmware.com" -q -N "" -f kubeapps-deploymentkey
echo "Kubeapps deployment key (public)"
cat kubeapps-deploymentkey.pub

# COPY THIS CONTENT TO GITHUB (with write access):
## https://github.com/kubeapps-bot/charts/settings/keys
ssh-keygen -t ed25519 -C "tanzu-kubeapps-team@vmware.com" -q -N "" -f charts-deploymentkey
echo "Charts deployment key (public)"
cat charts-deploymentkey.pub

# COPY THIS CONTENT TO THE SECRET `SSH_KEY_KUBEAPPS_DEPLOY` IN THE `Security > Secrets > Actions` SECTION OF THE KUBEAPPS REPO:
## https://github.com/vmware-tanzu/kubeapps/settings/secrets/actions
echo "Kubeapps deployment key (private)"
cat kubeapps-deploymentkey

# COPY THIS CONTENT TO THE SECRET `SSH_KEY_FORKED_CHARTS_DEPLOY` IN THE `Security > Secrets > Actions` SECTION OF THE KUBEAPPS REPO:
## https://github.com/vmware-tanzu/kubeapps/settings/secrets/actions
echo "Charts deployment key (private)"
cat charts-deploymentkey
```

### Debugging the CI errors

One of the best ways to troubleshoot problems is to SSH into a job and inspect things like log files, running processes,
and directory paths. Unfortunately, GHA doesn't provide a well known/official way that, but you can use any of the available
actions out there, for example, the [lhotari/action-upterm](https://github.com/lhotari/action-upterm).
For doing so, you have to:

* Add a new step with `uses: lhotari/action-upterm@v1` in the job you want to debug.
* Trigger the workflow (via a commit or whatever) and wait until the execution flow reaches the previous step. It will
block the execution, waiting for incoming `ssh` connections.
  * To see the connection details, look at the output of the `lhotari/action-upterm` job.
  * The job will block the job execution at this step until you exit the `ssh` session or create a file called `continue`
  in the home directory of the runner.
