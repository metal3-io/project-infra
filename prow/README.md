# Prow

Prow dashboard: http://prow.apps.ci.metal3.io

For more info about the CI cluster, see
[project-infra/clusters/ci/README.md](../clusters/ci/README.md).

## Prow Setup

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
