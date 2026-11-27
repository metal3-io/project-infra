<!-- cSpell:ignore CAPOCI capoci ocicluster kubeconfig kustomize onepassword -->
<!-- cSpell:ignore clusterctl externalsecret coreprovider bootstrapprovider -->
<!-- cSpell:ignore controlplaneprovider infrastructureprovider kubeadm calico -->
<!-- cSpell:ignore serverside prowjobs configmap NSG VCN eu-paris -->
<!-- cSpell:ignore OCIDs bringup OCID VXLAN vcn SIGSEGVs crictl -->
<!-- cSpell:ignore prowjob customresourcedefinition -->
<!-- cSpell:ignore statusreconciler oraclecloud appid Prow's -->
<!-- cSpell:ignore horologium cherrypicker ghproxy untaint Untaint untaints -->
<!-- cSpell:ignore periodics -->

# Prow OCI - Deploy Runbook

Copy-paste sequence to deploy the OCI Prow cluster from zero. Terse on purpose;
see `README.md` for the architecture overview and the gotcha list. Run every
command from `prow-oci/`; kustomize paths are bare and relative to it.

## Prerequisites

- `kubectl`, `kind`, `clusterctl`, `helm`, `oci` CLI installed.
- OCI account with the `prow` compartment, node image, and the `prow-ci` user
  API key.
- 1Password `Prow_GitOps` vault populated: `prow-oci-credentials`,
  `prow-cloud-provider`, `s3-credentials-oci`, `prow-github-app`, and a
  service-account token.
- Account-specific OCIDs already set in `prow-oci/cluster/` manifests.
- A GitHub App created and installed on the org (see Step 6 - GitHub App auth).
  Store its private key (PEM) and numeric App ID in the 1Password `prow-github-app`
  item as fields `private-key` and `app-id`.

## Step 0 - management VM (runs kind, also the bastion)

The workload API endpoint is private (a `10.0.x.x` address on the
`prow-apiserver` NLB; the exact IP is assigned per cluster, e.g. `10.0.0.12`).
An outside machine cannot reach it. So kind must run on a VM inside the VCN. This
VM is also the
bastion: you SSH to it on its public IP. You do not need the OCI Bastion service
in the normal flow. The OCI Bastion service is an optional alternative (see
Step 7).

The VM is temporary. You create it to provision the cluster, then you pivot to
the cluster (Step 5) and delete the VM. For teardown you create it again, pivot
back to kind, delete the cluster, then delete the VM.

Place the VM in the public `service-lb` subnet (the only public subnet) and
attach the existing `service-lb` NSG. Do not create a new NSG.

```sh
# Path to your oci CLI. If `oci` is on PATH, use: export OCI=oci
# Otherwise point to your install (venv, pipx, Homebrew, etc.), e.g.
#   export OCI=~/oci-cli-venv/bin/oci
export OCI=oci
C=ocid1.compartment.oc1..aaaaaaaarfgj34vubf272dhpvnklt63gr5xsxk5ajvjxurialhzduzcexevq
AD="SdxX:EU-PARIS-1-AD-1"
IMAGE=ocid1.image.oc1.eu-paris-1.aaaaaaaaizryoy4oobrq667xspcmbzsp5hvsndalclg4yapuhnckqleh6x5a

# public service-lb subnet and NSG (stable, BYO network - from ocicluster.yaml)
SUBNET_LB=ocid1.subnet.oc1.eu-paris-1.aaaaaaaag5env2g5m3snkhzwwmw4rr4baotldfmbislootpv5tx4lzvdy6va
NSG_LB=ocid1.networksecuritygroup.oc1.eu-paris-1.aaaaaaaaowd3u6bpjxhgwjoewndomekzmfcllwdghl3boajola4vf3tnkana

# launch the VM: public IP, service-lb subnet, service-lb NSG
"$OCI" compute instance launch \
  -c "$C" \
  --availability-domain "$AD" \
  --display-name prow-mgmt \
  --shape VM.Standard.E4.Flex \
  --shape-config '{"ocpus":4,"memoryInGBs":8}' \
  --image-id "$IMAGE" \
  --subnet-id "$SUBNET_LB" \
  --nsg-ids "[\"$NSG_LB\"]" \
  --assign-public-ip true \
  --ssh-authorized-keys-file ~/.ssh/id_ed25519.pub \
  --wait-for-state RUNNING

# read the instance id, then the public IP (two steps - simpler quoting)
INST="$("$OCI" compute instance list -c "$C" \
  --query "data[?\"display-name\"=='prow-mgmt'].id | [0]" --raw-output)"
"$OCI" compute instance list-vnics -c "$C" --instance-id "$INST" \
  --query 'data[0]."public-ip"' --raw-output
```

SSH to the VM:

```sh
ssh metal3ci@<public-ip>
```

On the VM, install the tools - `docker`, `kind`, `kubectl`, `clusterctl`,
`helm`, and the `oci` CLI - then clone the repo. (NOTE: this image already ships
Docker; do not install the Ubuntu `docker.io` package, it conflicts with the
installed `containerd.io`.)

```sh
git clone https://github.com/metal3-io/project-infra.git
```

Also copy your `~/.oci` config and API key to the VM, so the oci CLI and CAPOCI
can authenticate.

NOTE on SSH: the VM uses the `service-lb` NSG. If SSH is blocked, that NSG has no
port 22 ingress rule. Add one ingress rule for TCP 22 from your IP to that NSG.
Do not create a new NSG.

Delete the VM after the pivot (Step 5), or after teardown:

```sh
INST="$("$OCI" compute instance list -c "$C" \
  --query "data[?\"display-name\"=='prow-mgmt'].id | [0]" --raw-output)"
"$OCI" compute instance terminate --instance-id "$INST" --force
```

## Step 1 - kind bootstrap cluster + shared bootstrap (ESO, Calico)

```sh
kind create cluster

# ESO / cert-manager / capi-operator are pinned to infra nodes. Label the node.
kubectl label node "$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')" \
  node-role.kubernetes.io/infra="" --overwrite
```

Install `bootstrap` (External Secrets Operator + Calico + `onepassword`
ClusterSecretStore). Run all commands from inside the `prow-oci/` directory. The
ESO chart is a Helm generator (needs `--enable-helm`), its CRDs are large (need
server-side apply), and the ClusterSecretStore ships with its own CRD (needs a
second pass). Run twice:

```sh
cd project-infra/prow-oci
kubectl kustomize --enable-helm bootstrap \
  | kubectl apply --server-side --force-conflicts -f -
kubectl kustomize --enable-helm bootstrap \
  | kubectl apply --server-side --force-conflicts -f -
```

The FIRST pass prints
`clustersecretstores.external-secrets.io "onepassword" not found`. This is
expected, not a failure. The first pass installs the ESO CRDs, but the
`onepassword` ClusterSecretStore object is applied before its CRD is ready. The
SECOND pass applies the object cleanly. If the second pass still errors, wait for
the CRD (`kubectl get crd clustersecretstores.external-secrets.io`), then run the
apply again.

Seed the ONLY manual secret - the 1Password service-account token. Every other
credential (including the OCI API key) then flows from the vault via ESO:

```sh
kubectl -n external-secrets create secret generic onepassword-prow-service-account \
  --from-literal=token=<1PASSWORD_SERVICE_ACCOUNT_TOKEN>
```

Verify:

```sh
kubectl -n external-secrets get pods           # 3 pods Running
kubectl get clustersecretstore onepassword     # STATUS Valid, READY True
```

## Step 2 - CAPI + CAPOCI providers

```sh
kubectl apply --server-side --force-conflicts -k capi
```

If cert-manager / capi-operator webhooks are not ready yet, some objects error
on the first pass. Wait and re-apply:

```sh
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s
kubectl apply --server-side --force-conflicts -k capi

kubectl -n capi-operator-system rollout status \
  deploy/capi-operator-controller-manager --timeout=180s
kubectl apply --server-side --force-conflicts -k capi
```

The CAPOCI (`oci`) provider reads its credentials from the `oci-variables`
ExternalSecret (synced from the `prow-oci-credentials` 1Password item into the
`cluster-api-provider-oci-system` namespace). Verify all four report READY True:

```sh
kubectl get coreprovider,bootstrapprovider,controlplaneprovider,infrastructureprovider -A
```

The `oci` provider may show `READY False` for a minute while it installs - wait
and re-check before continuing.

## Architecture note - in-VCN management host + private endpoint

The Kubernetes API endpoint is **private** (`control-plane-endpoint` subnet
`type: private` in `ocicluster.yaml` -> the API-server NLB gets a `10.0.x.x` IP,
no public IP). A private endpoint is only reachable from inside the VCN, so the
**management cluster (kind) must run on a VM inside the VCN** (the `prow-mgmt`
host). An external/laptop kind cannot provision or reach a private-endpoint
cluster. All the steps below run on that in-VCN VM.

The network is **BYO / maintainer-managed** (`skipNetworkManagement: true`):
CAPOCI adopts the existing VCN/subnets/NSGs by OCID and never creates, deletes,
or reconciles them (or their NSG rules). NSG rules are owned by maintainers
directly in OCI. `kubectl delete cluster` leaves the VCN intact (only the
API-server NLB is CAPOCI-managed).

The kind cluster on the VM is a **temporary bootstrap** management plane. Once
the workload cluster is provisioned and healthy it is pivoted to
**self-managed** (`clusterctl move`, Step 5): CAPI/CAPOCI then run inside the
workload cluster and manage its own machines. The bootstrap VM is afterwards
decommissioned, and maintainers reach the private endpoint through the OCI
Bastion service (Step 7) - so there is no standing management VM to secure.

## Step 3 - Provision the workload cluster

```sh
kubectl apply -k cluster
clusterctl describe cluster prow
kubectl get machine -A
# endpoint is private (10.0.x.x):
kubectl get ocicluster prow -o jsonpath='{.spec.controlPlaneEndpoint.host}{"\n"}'
```

Wait until the control-plane Machine reaches `Running`. The workers reach the
private endpoint in-VCN directly (source `10.0.x.x`), so the
control-plane-endpoint NSG only needs 6443 open from `10.0.0.0/16` - no public
allowlist or NAT-gateway rule is needed for a private endpoint.

## Step 4 - Workload networking + cloud provider

Pull the kubeconfig (its server is the private `10.0.x.x` endpoint - reachable
from this in-VCN VM, not from a laptop). Write it OUTSIDE the repo
(`~/wl.kubeconfig`), NOT into `cluster/`. An `rsync --delete` of the repo onto
the VM can wipe or overwrite an in-repo kubeconfig; keeping it outside the tree
avoids that:

```sh
clusterctl get kubeconfig prow > ~/wl.kubeconfig
export KUBECONFIG_WL=~/wl.kubeconfig
kubectl --kubeconfig "$KUBECONFIG_WL" get nodes    # NotReady until CNI
```

RECOVERY: if the workload kubeconfig is lost, regenerate it. If kind still owns
the cluster (pre-pivot), re-run `clusterctl get kubeconfig prow` above. If the
cluster is self-managed (post-pivot) and kind is gone, SSH to the control-plane
node and copy `/etc/kubernetes/admin.conf`, then fix its `server:` line to the
private endpoint:

`admin.conf` already points at the control-plane node IP, which the VM can
reach, so it works as-is from the VM. You do NOT have to rewrite the server to
the NLB VIP (and the VIP IP is dynamic anyway - look it up with
`oci nlb network-load-balancer list` if you need it).

```sh
# on the control-plane node:
sudo cat /etc/kubernetes/admin.conf
# on the VM: paste into ~/wl.kubeconfig and use it as-is
```

Apply Calico (VXLAN), then install ESO on the WORKLOAD cluster (the CCM/CSI
credentials are synced from 1Password there):

Install Calico ONLY from `prow-oci/calico` (VXLAN), never the raw upstream
`calico.yaml`: the
 upstream default is BGP + IP-in-IP with a `-bird-ready`
readiness probe, which leaves nodes stuck `0/1 NotReady`
(`BIRD is not ready ... BGP not established`) on our VXLAN-only NSGs. If a node
is `NotReady` on `bird-ready`, check `calico-config` `calico_backend` (must be
`vxlan`, not `bird`) - if it drifted, `kubectl delete -k calico` then
re-apply from our yaml so the default IPPool is created as VXLAN
(`vxlanMode: Always`, `ipipMode: Never`).

```sh
kubectl --kubeconfig "$KUBECONFIG_WL" apply -k calico

# ESO + ClusterSecretStore on the workload cluster (same helm/server-side/twice
# dance as Step 1). Re-run if the ESO webhook is not up yet.
kubectl kustomize --enable-helm bootstrap \
  | kubectl --kubeconfig "$KUBECONFIG_WL" apply --server-side --force-conflicts -f -
kubectl --kubeconfig "$KUBECONFIG_WL" -n external-secrets \
  rollout status deploy/external-secrets-webhook --timeout=180s
kubectl kustomize --enable-helm bootstrap \
  | kubectl --kubeconfig "$KUBECONFIG_WL" apply --server-side --force-conflicts -f -

# seed the 1Password token on the workload cluster too
kubectl --kubeconfig "$KUBECONFIG_WL" -n external-secrets create secret generic \
  onepassword-prow-service-account --from-literal=token=<1PASSWORD_SERVICE_ACCOUNT_TOKEN>
kubectl --kubeconfig "$KUBECONFIG_WL" get clustersecretstore onepassword  # Valid/Ready
```

If the store reports a `wazero`/`authenticate_session` WASM stack trace, read the
FIRST line, not the WASM frames: it is almost always a transient DNS failure
(`dial tcp: lookup metal3-io.1password.com on 10.96.0.10:53 ... connection
refused`), typically while kube-proxy reprograms Service rules after a node
taint change. Confirm DNS is healthy from that node
(`kubectl -n kube-system run t --image=busybox:1.36 --restart=Never
--overrides='{"spec":{"nodeName":"<node>"}}' -- sleep 300` then
`kubectl -n kube-system exec t -- nslookup metal3-io.1password.com 10.96.0.10`),
then clear ESO's cached failure with
`kubectl -n external-secrets rollout restart deploy/external-secrets`.

### GOTCHA: the cloud-provider `uninitialized` taint deadlock

With `cloud-provider: external`, every node boots tainted
`node.cloudprovider.kubernetes.io/uninitialized:NoSchedule`. The
cloud-controller-manager (CCM) removes it once it initializes each node - but the
CCM needs its credentials from ESO. So the CCM cannot start until ESO works, and
the taint does not clear until the CCM starts - a deadlock.

The deadlock has TWO blocked pieces, not one:

1. **ESO** is pinned to the infra node, which carries the taint, so ESO stays
   `Pending` (`untolerated taint`).
1. **CoreDNS** has no toleration for the taint either, so BOTH CoreDNS pods stay
   `Pending` - the cluster has NO DNS. ESO then cannot resolve
   `metal3-io.1password.com`, so the `onepassword` ClusterSecretStore reports
   `InvalidProviderConfig` even though the token is valid.

So you must untaint enough nodes for BOTH ESO and CoreDNS, not just the infra
node. Untaint the infra node (for ESO) plus the control-plane node and one worker
(so the two CoreDNS replicas can schedule):

```sh
# untaint the infra node + all control-plane + worker nodes so ESO AND CoreDNS
# can schedule. The CCM re-stamps and re-clears correctly once it starts.
for n in $(kubectl --kubeconfig "$KUBECONFIG_WL" get nodes \
    -o jsonpath='{.items[*].metadata.name}'); do
  kubectl --kubeconfig "$KUBECONFIG_WL" taint node "$n" \
    node.cloudprovider.kubernetes.io/uninitialized:NoSchedule- 2>/dev/null || true
done

# wait for CoreDNS to schedule and go Ready - without DNS, ESO cannot validate
kubectl --kubeconfig "$KUBECONFIG_WL" -n kube-system \
  rollout status deploy/coredns --timeout=180s

# clear ESO's cached InvalidProviderConfig now that DNS works
kubectl --kubeconfig "$KUBECONFIG_WL" -n external-secrets \
  rollout restart deploy/external-secrets
kubectl --kubeconfig "$KUBECONFIG_WL" get clustersecretstore onepassword  # Valid/Ready
```

If the store still shows `InvalidProviderConfig`, DNS is still the cause. Confirm
CoreDNS is `Running` (not `Pending`) and that a debug pod can resolve
`metal3-io.1password.com` via `10.96.0.10`. `kubectl logs`/`exec` fail with
`lookup <node> ... no such host` while the CCM is down - that is expected; use
the control-plane node's `/etc/kubernetes/admin.conf` locally if you must read a
pod log before the CCM is up.

(Alternative permanent fix: add a toleration for
`node.cloudprovider.kubernetes.io/uninitialized` to ESO and CoreDNS - but ESO is
in the shared bootstrap used by the OpenStack instance too, and CoreDNS is a
kubeadm addon.)

Then apply the cloud provider + CSI:

```sh
kubectl --kubeconfig "$KUBECONFIG_WL" apply -k cluster-resources
kubectl --kubeconfig "$KUBECONFIG_WL" -n kube-system get externalsecret   # SecretSynced
kubectl --kubeconfig "$KUBECONFIG_WL" -n kube-system get pods \
  | grep -E 'cloud-controller|csi-oci'
# CCM clears the uninitialized taint on all nodes; they go Ready:
kubectl --kubeconfig "$KUBECONFIG_WL" get nodes
```

### GOTCHA: the bulk untaint drops zone labels - re-taint to fix CSI

Removing the `uninitialized` taint by hand has a side effect. The CCM stamps a
node's cloud metadata - including `topology.kubernetes.io/zone` - only while that
node still carries the taint. If you remove the taint before the CCM has
initialized the node, the CCM skips it and the node ends with NO zone label. The
OCI CSI node-driver-registrar then crash-loops on that node
(`csi-oci-node` stuck `1/3`, `Error`/`CrashLoopBackOff`), because it needs the
node's availability domain from the zone label.

Because the deadlock fix above untaints several nodes at once, several nodes can
lose their zone label. After the CCM is up, check which nodes have no zone:

```sh
kubectl --kubeconfig "$KUBECONFIG_WL" get nodes -L topology.kubernetes.io/zone
```

For EACH node with an empty `ZONE`, re-add the taint so the CCM re-initializes it
(stamps the zone label, then clears the taint itself):

```sh
kubectl --kubeconfig "$KUBECONFIG_WL" taint node <node-name> \
  node.cloudprovider.kubernetes.io/uninitialized=true:NoSchedule --overwrite
```

`NoSchedule` does not evict the running ESO/CoreDNS pods, so this is safe. Wait
about a minute for the CCM to re-stamp and re-clear, confirm every node now shows
a zone, then restart the crashing CSI node pods so they pick up the label:

```sh
kubectl --kubeconfig "$KUBECONFIG_WL" -n kube-system delete pod -l app=csi-oci-node
kubectl --kubeconfig "$KUBECONFIG_WL" -n kube-system get pods | grep csi-oci-node
```

All `csi-oci-node` pods should go `3/3 Running`.

### GOTCHA: cluster-autoscaler crash-loops before the pivot

The cluster-autoscaler (in `cluster-resources`) needs the CAPI CRDs
(`cluster.x-k8s.io`) in the cluster it runs in. Before the pivot (Step 5) those
CRDs live on the kind host, not here, so the autoscaler crash-loops. Scale it to
0 until the pivot is done, then scale it back up:

```sh
kubectl --kubeconfig "$KUBECONFIG_WL" -n kube-system \
  scale deploy/cluster-autoscaler --replicas=0
```

### GOTCHA: CCM crashes if `cloud-provider.yaml` lacks a `loadBalancer` block

The OCI cloud-controller-manager SIGSEGVs on startup
(`nil pointer ... NewCloudProvider`) if its config is missing the
`loadBalancer`/`vcn` section. And because a down CCM leaves nodes without an
`InternalIP`, the API server can't reach kubelet by hostname - so
`kubectl logs`/`exec` fail cluster-wide (`... no such host`), hiding the cause.
The
`prow-cloud-provider/cloud-provider.yaml` 1Password item MUST include, at top
level (BYO network: copy these fixed OCIDs from `cluster/ocicluster.yaml` - they
are stable across rebuilds):

```yaml
vcn: <vcn-ocid>
loadBalancer:
  subnet1: <service-lb-subnet-ocid>
  securityListManagementMode: None
```

To read a crashing CCM's log while `kubectl logs` is broken, SSH from this VM to
the node's private IP (temporarily open 22 on the node NSG) and
`sudo crictl logs <ccm-container>`.

## Step 5 - Pivot to self-managed (`clusterctl move`)

The in-VCN kind host is only a **bootstrap** management cluster. Once the
workload cluster is up and healthy, move CAPI/CAPOCI onto it so it manages its
own `Cluster`/`Machine` objects. `clusterctl move` needs the providers installed
on BOTH ends, so install `prow-oci/capi` on the workload first, then move.

cert-manager is bundled with `prow-oci/capi`, so this step also installs
cert-manager on the workload - which `prow-oci/infra` (Step 6) needs. No
standalone cert-manager install is required.

```sh
K="kubectl --kubeconfig $KUBECONFIG_WL"

# 1. install CAPI/CAPOCI (+ cert-manager) on the workload - same apply-dance as
#    Step 2: the first pass errors on the provider CRs until cert-manager and the
#    capi-operator webhooks are Ready, so wait and re-apply.
$K apply -k capi
$K -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s
$K apply -k capi
$K -n capi-operator-system rollout status \
  deploy/capi-operator-controller-manager --timeout=180s
$K apply -k capi

# all four providers READY=True, and CAPOCI creds synced from 1Password:
$K get coreprovider,bootstrapprovider,controlplaneprovider,infrastructureprovider -A
$K -n cluster-api-provider-oci-system get externalsecret oci-variables   # SecretSynced

# 2. move CAPI resources from the kind host into the workload (run on the VM;
#    source = kind context, target = workload). Use the Cluster's namespace.
clusterctl move --to-kubeconfig="$KUBECONFIG_WL" -n <cluster-namespace>

# 3. verify the workload owns its CAPI objects and stayed healthy
$K get nodes -o wide
```

The cluster-autoscaler (in `prow-oci/cluster-resources`) crash-loops until this
pivot is done - it needs the CAPI CRDs (`cluster.x-k8s.io`) in-cluster. Keep it
at 0 replicas until now, then scale it up:

```sh
kubectl --kubeconfig "$KUBECONFIG_WL" -n kube-system \
  scale deploy/cluster-autoscaler --replicas=1
```

Do NOT delete the kind host until the move is verified - it is the only fallback
management plane. Maintainer access to the private endpoint after the VM is gone
is Step 7.

## Step 6 - infra + Prow application

cert-manager is already on the workload (installed with `prow-oci/capi` in
Step 5), so `prow-oci/infra`'s `ClusterIssuer` + `Certificate` resolve without a
standalone cert-manager install.

### Prerequisite: the `prow` namespace must exist before infra

`prow-oci/infra` places the `metal3-io-tls` Certificate (and a ReferenceGrant) in
the `prow` namespace, but that namespace is normally created by the Prow app
overlay. Applying infra first fails with `namespaces "prow" not found`. Create
the app namespaces up front:

```sh
for ns in prow test-pods; do
  kubectl --kubeconfig "$KUBECONFIG_WL" create ns "$ns" \
    --dry-run=client -o yaml | kubectl --kubeconfig "$KUBECONFIG_WL" apply -f -
done
```

### infra

Infra (traefik on an OCI LoadBalancer, cert-manager ClusterIssuers, StorageClass,
namespaces) has no 1Password dependency, so it can go up before the app secrets:

```sh

# re-apply once (Gateway API / traefik CRDs land first, then the Gateway/HTTPRoute)
kubectl --kubeconfig "$KUBECONFIG_WL" apply -k infra
kubectl --kubeconfig "$KUBECONFIG_WL" -n traefik get svc traefik   # gets an OCI LB IP
```

Note: traefik's service-lb stays public (Prow ingress on 80/443) even though the
API endpoint is private. The Let's Encrypt HTTP-01 cert stays pending until the
`prow-oci.apps.test.metal3.io` DNS record points at the traefik LB IP.

Prow application (dark standby: tide + jenkins-operators omitted, `prow-oci`
hostname, s3 from `s3-credentials-oci`). The ProwJob CRD and config ConfigMaps
are bootstrapped out-of-band (see Gotchas in `README.md`).

### GitHub App auth (core components)

The core Prow components (hook, deck, crier, statusreconciler, needs-rebase,
prow-controller-manager) authenticate to GitHub with a **GitHub App**, not a
personal token. The `github-token` ExternalSecret
(`manifests/overlays/prow-oci/prow-externalsecrets.yaml`) syncs two keys from the
1Password `prow-github-app` item into the in-cluster `github-token` Secret:

- `appkey` (from `prow-github-app/private-key`) - the App private key PEM,
  mounted at `/etc/github/appkey` and read via `--github-app-private-key-path`.
- `appid` (from `prow-github-app/app-id`) - the numeric App ID (not secret),
  injected into each component as the `GITHUB_APP_ID` env var and referenced by
  `--github-app-id=$(GITHUB_APP_ID)`.

The two external plugins that post as their own bot identities (cherrypicker,
copilot-review) keep their dedicated token secrets and are NOT part of the App
switch. tide is deleted in this overlay (dark standby).

Before deploying, confirm the App exists and is installed on the org, and the
`prow-github-app` 1Password item has both fields. After deploy, verify the Secret
materialized with both keys:

```sh
kubectl --kubeconfig "$KUBECONFIG_WL" -n prow get externalsecret github-token   # SecretSynced
kubectl --kubeconfig "$KUBECONFIG_WL" -n prow get secret github-token \
  -o jsonpath='{.data}' | tr ',' '\n'    # expect appkey and appid
```

### Bootstrap CRD + overlay

```sh
# ProwJob CRD (deck/controllers crash without it). Fetched from upstream, same as
# the OpenStack instance (prow/README.md) - it is not vendored in-repo.
kubectl --kubeconfig "$KUBECONFIG_WL" apply --server-side -f \
  https://github.com/kubernetes-sigs/prow/raw/main/config/prow/cluster/prowjob-crd/prowjob_customresourcedefinition.yaml

# the app overlay (creates prow + test-pods namespaces, Deployments, ExternalSecrets)
kubectl --kubeconfig "$KUBECONFIG_WL" apply -k manifests/overlays/prow-oci

# seed config/plugins/label-config/job-config ConfigMaps in the prow namespace
kubectl --kubeconfig "$KUBECONFIG_WL" -n prow create configmap config \
  --from-file=config.yaml=config/config.yaml --dry-run=client -o yaml \
  | kubectl --kubeconfig "$KUBECONFIG_WL" -n prow apply -f -
kubectl --kubeconfig "$KUBECONFIG_WL" -n prow create configmap plugins \
  --from-file=plugins.yaml=config/plugins.yaml --dry-run=client -o yaml \
  | kubectl --kubeconfig "$KUBECONFIG_WL" -n prow apply -f -
kubectl --kubeconfig "$KUBECONFIG_WL" -n prow create configmap label-config \
  --from-file=labels.yaml=config/labels.yaml --dry-run=client -o yaml \
  | kubectl --kubeconfig "$KUBECONFIG_WL" -n prow apply -f -
# NON-AUTHORITATIVE deploy: EXCLUDE the mutating periodics. periodics run on a
# timer - they do NOT need a webhook, and tide being off does NOT stop them. The
# metal3-io stale jobs run with --confirm and will comment on and CLOSE real
# metal3-io issues within the hour, colliding with the live instance. So drop
# periodics.yaml from the seed until go-live (Step 8).
args=""
for f in $(find config/jobs -name '*.yaml'); do
  case "$f" in
    */periodics.yaml) continue ;;   # skip mutating periodics (stale, autobump, ...)
  esac
  args="$args --from-file=$(basename "$f")=$f"
done
kubectl --kubeconfig "$KUBECONFIG_WL" -n prow create configmap job-config $args \
  --dry-run=client -o yaml | kubectl --kubeconfig "$KUBECONFIG_WL" -n prow apply -f -
```

**COLLISION WARNING.** The OCI instance is non-authoritative by three means:
tide is deleted, no GitHub webhook points at it, and its hostname differs. But
those do NOT stop **periodics** or the **GitHub App identity** from acting on
real repos:

- `config/jobs/periodics.yaml` contains `periodic-stale` and
  `periodic-stale-close` (`interval: 1h`, `--query=org:metal3-io`, `--confirm`).
  If seeded, horologium fires them on a timer and they comment on and CLOSE real
  metal3-io issues - a direct collision with the live instance. The seed loop
  above excludes `periodics.yaml` for this reason.
- The GitHub App must be scoped so it cannot write to production repos during
  validation (install it only on a throwaway test repo, or confirm it has no
  merge/write on real repos). Add the real periodics and widen the App only at
  go-live (Step 8), after the OpenStack instance is disabled.

The config/plugins/label-config/job-config ConfigMaps are NOT part of the
kustomize overlay - they are seeded from `config/` by the commands above. Until
they exist, every component that mounts them (sinker, horologium, hook, deck,
...) stays pending with `MountVolume.SetUp failed ... configmap "config" not
found` / `"job-config" not found`. Seed them, and the mounts clear. Prow's
`config_updater` plugin keeps them current from the main branch after go-live.

The Prow app ExternalSecrets (github-token, hmac-token, s3-credentials, ...)
require the WORKLOAD-cluster ESO to reach 1Password. If that path is not yet
working, the app pods stay pending on their secrets - resolve workload ESO first.

## Step 7 - Maintainer access (OCI Bastion) + decommission the bootstrap VM

After the pivot the workload cluster is self-managed. The kind VM is no longer
needed as a management plane. A maintainer reaches the private API endpoint
through the OCI Bastion service, then the bootstrap VM is decommissioned.

The full bastion runbook (create the bastion, port-forward, tunnel, kubectl,
re-look up the node IP after a control-plane roll, and cleanup) is in its own
doc: [`BASTION.md`](./BASTION.md).

## Step 8 - Optional: GitOps with Flux

The OCI tree ships a Flux setup mirroring the OpenStack `prow/flux`, in
`prow-oci/flux`. It installs the flux-operator + a `FluxInstance` that syncs the
`prow-oci/flux` path from `main` (which pulls in `prow-oci/capi`). This is
optional - the steps above deploy everything imperatively without it. Applying it
makes Flux continuously reconcile CAPI/CAPOCI from git.

```sh
# note: ../capi is referenced with a relative path, so the default load
# restrictor must be relaxed (same as the OpenStack prow/flux).
kubectl --kubeconfig "$KUBECONFIG_WL" kustomize --load-restrictor=LoadRestrictionsNone \
  prow-oci/flux | kubectl --kubeconfig "$KUBECONFIG_WL" apply --server-side -f -
```

Flux syncs `prow-oci/flux` (-> `prow-oci/capi`), NOT the Prow application
manifests under `prow-oci/manifests`. The Prow app stays a manual
`kubectl apply -k` (Step 6).

## Cleanup reminders

- Remove any temporary SSH ingress rule added to a node NSG for debugging.
- Delete orphaned instances from earlier cluster builds (e.g. a stray
  `prow-control-plane-*`) in the `prow` compartment.
