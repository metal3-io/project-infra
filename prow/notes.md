# Notes for setting up a CAPO cluster and deploying Prow in it

TODO:

- [x] Switch to OpenStack remote builder and json file with variables!
- [x] Setup S3 storage in Cleura
- [x] Requirements: clusterctl, s3cmd, kubectl, kind, openstack
- [x] Cloud controller and CSI plugin
- [x] Kustomization for the cloud controller stuff
- [x] Ingress for hook.apps.test.metal3.io removed since it is not used.
- [x] Switch from host path PersistentVolume to CSI Cinder plugin
- [x] Limit access to Kubernetes API.
- [x] List variables needed for creating the secret files
- [x] Document access to k8s API through bastion
- [x] Update paths in `config.yaml` and `plugins.yaml` to match changes.
- [x] Set images through kustomization.yaml
- [x] Check ghproxy pushgateway. The push-gateway is not deployed by default,
      but ghproxy is still configured for it.
- [x] prow-controller-manager needs to `get` pods:
      <https://github.com/kubernetes/test-infra/issues/29286>
- [ ] Investigate why need-rebase is using a NodePort service...
- [ ] Monitoring, efficiency and robustness. See the
      [test-infra repo](https://github.com/kubernetes/test-infra/tree/master/config/prow/cluster/monitoring)
      for an example.
  - [x] Add LimitRange with default request, see
        <https://github.com/kubernetes/test-infra/blob/master/config/prow/cluster/build/mem-limit-range_limitrange.yaml>
  - [ ] Add monitoring solution (prometheus + grafana?). Note that we need to
        track the specific prow jobs (not the pod names).
        [This could be of interest](https://github.com/loodse/prow-dashboards/tree/master).
  - [ ] Set resource requests for all prow jobs
  - [ ] Set resource requests for other components
  - [ ] Optimize resource usage and enable auto scaling
  - [ ] Configure alerts and/or ops routines for keeping the resource requests
        up to date.
- [ ] Split out the jobs from the rest of the config.
  - [ ] Use config updater configured
        [like this](https://github.com/kubernetes/test-infra/blob/5c1e343a49703ebd0a545e3fb9b5c28d814c1b6a/config/prow/plugins.yaml#LL623C1-L628C20)
  - [ ] Use the
        [job-config flag](https://github.com/kubernetes/test-infra/blob/5c1e343a49703ebd0a545e3fb9b5c28d814c1b6a/config/prow/cluster/tide_deployment.yaml#L44)
- [ ] ClusterResourceSets for clouds controller and CSI plugin
- [ ] Webhook timeouts during KCP rollout?

## Ops

TODO:

- Update infra components
- Update CAPI/CAPO
- Update prow and plugins

## Metrics

```console
❯ k top nodes
NAME                       CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
prow-control-plane-kdqx4   293m         7%     2772Mi          72%
prow-md-0-xx8k7            7773m        97%    11212Mi         70%

❯ k top pods -A
NAMESPACE                           NAME                                                             CPU(cores)   MEMORY(bytes)
capi-kubeadm-bootstrap-system       capi-kubeadm-bootstrap-controller-manager-6589bbf55c-dslmd       2m           23Mi
capi-kubeadm-control-plane-system   capi-kubeadm-control-plane-controller-manager-7bbcfcb758-br649   65m          39Mi
capi-system                         capi-controller-manager-5c7545785f-2gnvv                         4m           34Mi
capo-system                         capo-controller-manager-6dc6bdccf5-98txt                         3m           24Mi
cert-manager                        cert-manager-6ffb79dfdb-cftns                                    1m           33Mi
cert-manager                        cert-manager-cainjector-5fcd49c96-jhqb7                          4m           63Mi
cert-manager                        cert-manager-webhook-796ff7697b-l2p7d                            1m           14Mi
ingress-nginx                       ingress-nginx-controller-6bdb654777-xtwkm                        3m           156Mi
kube-system                         calico-kube-controllers-5f94594857-9v4cj                         2m           44Mi
kube-system                         calico-node-tfhwb                                                29m          130Mi
kube-system                         calico-node-wjptj                                                25m          148Mi
kube-system                         coredns-787d4945fb-wg8ms                                         3m           17Mi
kube-system                         coredns-787d4945fb-z6898                                         3m           20Mi
kube-system                         csi-cinder-controllerplugin-8658656f6b-4twzx                     4m           77Mi
kube-system                         csi-cinder-nodeplugin-fnrm7                                      1m           26Mi
kube-system                         csi-cinder-nodeplugin-hmzdw                                      1m           26Mi
kube-system                         etcd-prow-control-plane-kdqx4                                    58m          91Mi
kube-system                         kube-apiserver-prow-control-plane-kdqx4                          100m         814Mi
kube-system                         kube-controller-manager-prow-control-plane-kdqx4                 25m          77Mi
kube-system                         kube-proxy-nz482                                                 1m           20Mi
kube-system                         kube-proxy-tbmqp                                                 1m           19Mi
kube-system                         kube-scheduler-prow-control-plane-kdqx4                          4m           35Mi
kube-system                         metrics-server-6b6f9ccc7-jk2ck                                   3m           20Mi
kube-system                         openstack-cloud-controller-manager-vmf82                         3m           25Mi
prow                                cherrypicker-6f88fc569d-np7mw                                    1m           12Mi
prow                                crier-84d95f9cfc-qtt4h                                           1m           33Mi
prow                                deck-69dc9f8756-9sj2j                                            10m          72Mi
prow                                deck-69dc9f8756-znwzq                                            7m           61Mi
prow                                ghproxy-79f7d7c4b8-mslvv                                         1m           22Mi
prow                                hook-65bbf9cdfc-nxkwq                                            1m           39Mi
prow                                hook-65bbf9cdfc-rccbq                                            1m           30Mi
prow                                horologium-55c4d4bf97-tpnxh                                      1m           22Mi
prow                                needs-rebase-5656cfcb87-4mkmq                                    1m           16Mi
prow                                prow-controller-manager-56f94b9c46-l9jmb                         2m           32Mi
prow                                sinker-768647d76-22skf                                           1m           34Mi
prow                                statusreconciler-6f76cd8b54-lj6t8                                1m           38Mi
prow                                tide-747d944d8b-hmxkf                                            7m           88Mi
test-pods                           63340055-ed75-11ed-b05d-7a6b49b20484                             2516m        3702Mi
test-pods                           6335fce9-ed75-11ed-b05d-7a6b49b20484                             1242m        657Mi
test-pods                           6338e7cf-ed75-11ed-b05d-7a6b49b20484                             1054m        604Mi
test-pods                           6341fee4-ed75-11ed-b05d-7a6b49b20484                             395m         633Mi
test-pods                           6344d293-ed75-11ed-b05d-7a6b49b20484                             1142m        671Mi
test-pods                           634a0f1f-ed75-11ed-b05d-7a6b49b20484                             1034m        484Mi

❯ k -n test-pods get pods -o custom-columns=NAME:.metadata.name,JOB:".metadata.labels.prow\.k8s\.io/job"
NAME                                   JOB
a4fe43f5-ed73-11ed-8afd-a694b4914209   periodic-stale
a7ef2ded-ed77-11ed-9a97-2ea4f6a8787a   markdownlint
ac067001-ed79-11ed-b05d-7a6b49b20484   markdownlint
c6f64847-ed78-11ed-b05d-7a6b49b20484   markdownlint
c8c19d9e-ed73-11ed-8afd-a694b4914209   periodic-stale-close
cc4a4b6e-ed78-11ed-b05d-7a6b49b20484   markdownlint
d09fde36-ed78-11ed-b05d-7a6b49b20484   markdownlint

❯ k -n test-pods get pods -o jsonpath="{.items[*].metadata.labels['prow\.k8s\.io/job']}"
periodic-stale markdownlint markdownlint markdownlint periodic-stale-close markdownlint markdownlint
```

| pod name                             | job           | CPU(cores) | MEMORY(bytes) |
| ------------------------------------ | ------------- | ---------- | ------------- |
| 9b46af1c-f3b3-11ed-a905-aa6fde54911b | gosec         | 811m       | 1649Mi        |
| a0d8f817-f3b3-11ed-b8dc-c208e9e19f04 | gosec         | 881m       | 1803Mi        |
| fc4401f0-f3b3-11ed-b8dc-c208e9e19f04 | gosec         | 767m       | 1203Mi        |
| 9b495266-f3b3-11ed-a905-aa6fde54911b | golangci-lint | 474m       | 603Mi         |
| a0dc3c76-f3b3-11ed-b8dc-c208e9e19f04 | golangci-lint | 394m       | 468Mi         |
| fc49e849-f3b3-11ed-b8dc-c208e9e19f04 | golangci-lint | 373m       | 285Mi         |
| 9b4b88d9-f3b3-11ed-a905-aa6fde54911b | govet         | 376m       | 449Mi         |
| a0e24a66-f3b3-11ed-b8dc-c208e9e19f04 | govet         | 370m       | 334Mi         |
| fc4deb44-f3b3-11ed-b8dc-c208e9e19f04 | govet         | 397m       | 326Mi         |
| 9b4ed0cd-f3b3-11ed-a905-aa6fde54911b | generate      | 175m       | 500Mi         |
| a0e627c3-f3b3-11ed-b8dc-c208e9e19f04 | generate      | 218m       | 370Mi         |
| fc60aa25-f3b3-11ed-b8dc-c208e9e19f04 | generate      | 242m       | 164Mi         |
| 9b5259ca-f3b3-11ed-a905-aa6fde54911b | unit          | 401m       | 375Mi         |
| a0eac066-f3b3-11ed-b8dc-c208e9e19f04 | unit          | 421m       | 592Mi         |
| fc65dcbf-f3b3-11ed-b8dc-c208e9e19f04 | unit          | 183m       | 123Mi         |
| fc358cf3-f3b3-11ed-b8dc-c208e9e19f04 | gomod         | 162m       | 222Mi         |
| fc7269b9-f3b3-11ed-b8dc-c208e9e19f04 | build         | 377m       | 364Mi         |

Prow resources:

```console
❯ k -n prow top pods
NAME                                       CPU(cores)   MEMORY(bytes)
cherrypicker-6f88fc569d-m2pzb              3m           20Mi
crier-84d95f9cfc-7474n                     34m          54Mi
deck-69dc9f8756-6pmtq                      26m          76Mi
deck-69dc9f8756-ffrwz                      25m          60Mi
ghproxy-79f7d7c4b8-qnd89                   13m          19Mi
hook-65bbf9cdfc-7lgxk                      11m          35Mi
hook-65bbf9cdfc-qpkwh                      15m          36Mi
horologium-55c4d4bf97-fkjtw                5m           23Mi
needs-rebase-5656cfcb87-zpph7              6m           16Mi
prow-controller-manager-56f94b9c46-7hdtj   23m          41Mi
sinker-768647d76-ww94j                     16m          39Mi
statusreconciler-6f76cd8b54-jpqkh          1m           19Mi
tide-747d944d8b-7zw7t                      18m          113Mi
```
