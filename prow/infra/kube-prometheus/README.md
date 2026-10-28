# Kube-prometheus for Metal3 Prow

This monitoring stack is based on
[kube-prometheus](https://github.com/prometheus-operator/kube-prometheus/tree/main).
We also took inspiration from how [k8s.io is monitoring
ProwJobs](https://github.com/kubernetes/k8s.io/pull/5355).

This is how you apply it in the cluster. The CRDs are too large for client-side
apply, so use server-side apply:

```bash
kubectl apply --server-side --force-conflicts -f manifests/setup
kubectl apply --server-side --force-conflicts -f manifests
kubectl apply --server-side --force-conflicts -f prow-rules.yaml
```

The `manifests` are rendered using jsonnet based on
`metal3-kube-prometheus.jsonnet`. Use the build script to render them after
making changes:

```bash
make build
```

The jsonnet dependencies are pinned in `jsonnetfile.lock.json` and installed to
`vendor/` (not committed) by the build. To update to a new kube-prometheus
release, change the version in `jsonnetfile.json`, run `jb update` to refresh
the lock file and then `make build`. Check the [compatibility
matrix](https://github.com/prometheus-operator/kube-prometheus#compatibility)
against the Kubernetes version of the cluster first.

## How to access?

For now, we have not exposed grafana or any other component. You can access them
by using port-forward like this (after setting up access to the cluster itself):

```bash
kubectl -n monitoring port-forward svc/grafana 3000
```

Then go to <localhost:3000>.
