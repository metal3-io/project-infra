# Flux for GitOps

This folder contains resources for managing Prow through Flux. The `kustomization.yaml` enumerates what is currently synchronized and will grow as more of the stack becomes GitOps managed.

## Components

- `flux.yaml` – defines the `FluxInstance` (operator version, tolerations, sync source).
- `../capi` – installs the supporting Cluster API bits needed for the management cluster.
- `externalsecret-github-dispatch.yaml` – pulls the GitHub PAT (`flux-github-dispatch-token/password` in 1Password) into `flux-system` using External Secrets.
- `provider-github-dispatch.yaml` – configures a `githubdispatch` Provider pointing at `https://github.com/metal3-io/project-infra`.
- `alert-github-dispatch.yaml` – wires all `flux-system` `Kustomization` events to the Provider so reconciliations emit repository_dispatch events.

## GitHub workflow dispatch notifications

Flux now raises GitHub `repository_dispatch` events whenever a managed `Kustomization` finishes reconciling. The dispatch payload (passed as `client_payload`) includes the Flux event data, enabling a workflow such as `.github/workflows/flux-reconcile-commenter.yaml` to:

1. Resolve the commit referenced in the event and locate any merged PRs.
2. Comment on the originating PR with success/failure details.
3. Skip duplicates by checking for an existing comment referencing the same event ID.

Only merged PRs are annotated, ensuring clear confirmation when Flux actually applies a change (or surfaces the failure context).

## Secrets

The GitHub PAT used by the Provider is sourced from the shared ClusterSecretStore (`onepassword`) and exposed in-cluster as `Secret/flux-github-dispatch-token` within `flux-system`. Rotate the 1Password entry and re-sync Flux to refresh the credential.
