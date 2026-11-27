# Metal3 project infrastructure

CI for all Metal3 repositories: Prow configuration and jobs, the Prow
cluster itself, Jenkins pipelines for the heavier E2E jobs, and CI
images. Overview: [README.md](README.md), [prow/README.md](prow/README.md),
[jenkins/README.md](jenkins/README.md). Contribution rules: the
[Metal3 community guide](https://github.com/metal3-io/community/blob/main/CONTRIBUTING.md).

This file holds only what you cannot cheaply infer from the code. Where it
disagrees with the code or the configs, trust those and report the
mismatch.

## AI-assisted contributions

Metal3 follows the CNCF and
[Linux Foundation generative AI policy](https://www.linuxfoundation.org/legal/generative-ai).

- AI is a tool. The human who opens a PR is its author and is responsible
  for every line of it, including licensing and third-party content.
- Review is a conversation between humans. A PR where an agent or bot
  answers reviewers will be closed. Agents may draft changes; the
  contributor reads them, understands them, and replies personally.

- Keep changes surgical. The smallest complete change that solves the
  stated problem wins. Every added file, function, flag, dependency or
  test helper must trace to that problem; anything that does not is
  bloat and gets removed. Prefer reusing existing code over new code.
  Report unrelated findings instead of fixing them in the same PR.

## Repository map

- `prow/config/`: Prow config and jobs, one file per repository and
  release branch under `jobs/<org>/`.
- Other `prow/` directories: the Prow cluster
  ([prow/README.md](prow/README.md)). `prow/container-images/` builds
  the `basic-checks` image that most repositories' lint and unit jobs
  run in.
- `jenkins/`: pipelines (`jobs/`), what they run (`scripts/`), and node
  and CI image builds (`image_building/`). Job definitions (JJB) live in
  the Nordix Gerrit `infra/cicd` repository under `jjb/metal3/`.
- `jenkins/tofu/`, `jenkins/ansible/`: deploy the OCI-hosted Jenkins,
  including the `infra/cicd` jobs
  ([jenkins/ansible/README.md](jenkins/ansible/README.md)). Prow sends
  jobs labeled `jenkins_operator: oci` there, the rest to Nordix Jenkins.

## Testing

- Checks: the presubmits in
  `prow/config/jobs/metal3-io/project-infra.yaml` and
  `.github/workflows/`, most with a matching `hack/*.sh`. Nothing beyond
  yamllint checks `jenkins/ansible/` or `jenkins/tofu/`.
- Conventions are whatever the existing configs, pipelines and scripts
  do. Read neighboring files before writing new ones. New words that
  spellcheck rejects go in `.cspell-config.json`.
- Before finishing, run `cd prow && make validate` (the
  `check-prow-config` job) for any `prow/config/` change and the `hack/`
  checks for the file types you touched. All must pass.
- Jenkins pipelines run only in CI. On a project-infra PR they check out
  the PR commit, so trigger the affected job with `/test <job>`.
- Do not run anything against real infrastructure unless the user asks:
  `kubectl`, `clusterctl`, `openstack` or `s3cmd` against the Prow
  cluster or clouds, anything under `jenkins/`, or
  `hack/clean_artifactory.sh`. They need production credentials and
  change shared infrastructure. `hack/ipa_debug_tools.sh` runs `sudo` on
  the host.

## Invariants

These apply to writing and to reviewing changes.

- **Merge is deploy.** On merge to `main`, `config-updater` pushes the
  files mapped under `config_updater` in `prow/config/plugins.yaml` into
  the live Prow, Flux syncs `prow/flux` (including `prow/capi`), and
  Jenkins pipelines use the new `main` for every repository except
  project-infra PRs. Other `prow/` manifests, `jenkins/ansible/` and
  `jenkins/tofu/` are applied by hand by maintainers.
- **Blast radius.** A change here can break CI or merging for every
  repository. Presubmits without `optional: true` are required merge
  checks once they run. When changing a job on `main`, check whether the
  release-branch files need the same change.
- **Security.** Never weaken security to make something work: no secrets
  in git or logs (watch `set -x`), no disabled TLS verification, no
  broadened token scopes or workflow `permissions:`. Secrets reach the
  Prow cluster only through External Secrets (`*externalsecret*.yaml`)
  and the OCI Jenkins only through 1Password lookups in tasks with
  `no_log: true`. Call out any change to triggers, OWNERS, tokens,
  Secrets, workflow permissions or `pull_request_target` in the PR
  description.
- **Trust and isolation.** Review these areas with extra care:
   - Untrusted code. Presubmits and pull request workflows run PR code,
     from outside contributors after `/ok-to-test`. Never mount Secrets
     into Prow presubmits (only `jobs/periodics.yaml` does), and never
     bind credentials with `withCredentials` in Jenkins jobs that PRs
     trigger: the PR code can read them.
   - Shared namespace. Job pods run in `test-pods`, Prow components in
     `prow`. Any job can mount a Secret in `test-pods`.
   - Merge rights. `OWNERS`, `plugins.yaml` and `config.yaml` decide who
     can merge or run CI.
- **Pinning.** Pin new container images by digest and GitHub Actions by
  commit SHA, except images under the prefixes in
  `prow/config/generic-autobumper-config.yaml`, which stay tag-pinned for
  the `autobump-prow-images` periodic. Before merging a Renovate bump of
  Jenkins core or the forked OCI compute plugin, follow its rule
  description in `renovate.json`.

## External references

- [Metal3 Prow dashboard](https://prow.apps.test.metal3.io)
- [Metal3 Jenkins view](https://jenkins.nordix.org/view/Metal3/)
- [Nordix Gerrit infra/cicd (JJB job definitions)](https://gerrit.nordix.org/admin/repos/infra/cicd)
