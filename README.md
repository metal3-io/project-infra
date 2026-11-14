# metal3.io Project Infrastructure

We operate a CI Cluster which runs [Prow](prow/README.md) to provide CI and
some GitHub automation.

We also run a [Jenkins](jenkins/README.md) server for some additional CI jobs.

## CI architecture overview

Our CI is split across two systems, each suited to a different kind of job:

- **Prow** coordinates all jobs and directly executes the lightweight ones
  (lint, unit tests, builds, manifest checks) as pods inside its own
  Kubernetes cluster.
- **Jenkins** ([jenkins.nordix.org](https://jenkins.nordix.org)) executes the
  heavier jobs that Prow triggers but doesn't run itself — e2e, integration,
  conformance, and upgrade test suites. Jenkins provisions either a cloud VM
  or, for bare-metal-lab jobs, dispatches to persistent physical hardware.

Prow also runs **Tide**, which automatically merges PRs once they pass
required checks and carry the necessary labels (`lgtm`, `approved`).

Job definitions for the Jenkins side live in this repo's
[`jenkins/jobs/jjb/`](jenkins/jobs/jjb/) directory (JJB YAML format) and
reference pipeline scripts in the [`jenkins/jobs/`](jenkins/jobs/) directory.
See [`jenkins/jobs/jjb/defaults.yml`](jenkins/jobs/jjb/defaults.yml) for the
exact pipeline-to-script mapping.
