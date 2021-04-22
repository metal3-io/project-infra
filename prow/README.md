# Prow

Prow dashboard: http://prow.apps.ci.metal3.io

## Access Controls

* To merge, patches must have `/approve` and `/lgtm`, which apply the `approved` and `lgtm` labels

* Only members of the `metal3-io` github org can use `/lgtm`.

* The use of `/approve` is controlled by the `OWNERS` file in each repository.
  See the [OWNERS spec](https://go.k8s.io/owners) for more details about how
  to manage access to all or part of a repo with this file.

* Tests will run automatically for PRs authored by **public** members of the
  `metal3-io` github organization.  Members of the github org can run
  `/ok-to-test` for PRs authored by those not in the github org.

See the [Prow command help](https://prow.apps.ci.metal3.io/command-help) for
more information about who can run each prow command.

## Prow Setup

For more info about the CI cluster, see
[project-infra/clusters/ci/README.md](../clusters/ci/README.md).

Prow was set up by following these instructions: https://github.com/kubernetes/test-infra/blob/master/prow/getting_started_deploy.md

```
go get -u k8s.io/test-infra/prow/cmd/tackle
tackle
```

After running tackle, it will do most of the setup but hang waiting for an
Ingress resource to get initialized.  I killed tackle at that point.

```
oc delete ingress ing
oc expose service hook --hostname=prow.apps.ci.metal3.io --path="/hook"
oc expose service deck --hostname=prow.apps.ci.metal3.io
```

This just exposes the routes on http.  Edit each route and add the following
yaml snippet to the spec to turn on https.

```
oc edit route hook
oc edit route deck
```

```
  tls:
    insecureEdgeTerminationPolicy: Redirect
    termination: edge
```

GCS cloud storage is required to store job artificates.  Follow the docs to set
up GCS, and then create a secret with the credentials.

```
kubectl create secret generic gcs-credentials --from-file=service-account.json
```

The job artifacts viewer is called Spyglass and is not enabled by default.  To
enable it, you add `--spyglass` as an additional argument to `deck`.

https://github.com/kubernetes/test-infra/tree/master/prow/spyglass#enabling-spyglass

```
oc edit deployment deck
```