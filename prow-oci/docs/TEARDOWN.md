<!-- cSpell:ignore clusterctl kubeconfig kubeconfigs CAPOCI traefik -->
<!-- cSpell:ignore skipNetworkManagement NLBs NLB eu-paris OCIDs -->

# Prow OCI - Teardown

The cluster is self-managed after the pivot (CAPI runs inside it). You cannot
delete a self-managed cluster from itself. So re-pivot first: move CAPI back to
a kind host, then delete the cluster from kind.

## Step 0 - recreate the in-VCN management VM

After the deploy pivot the cluster is self-managed (CAPI runs inside it) and the
bootstrap VM is destroyed, so there is no management cluster left to delete the
workload from. You must bring one back. It has to sit inside the same BYO VCN.

Recreate the `prow-mgmt` VM and bring up kind with CAPI/CAPOCI on it by following
[`DEPLOY.md`](./DEPLOY.md) Steps 0-2.

## Step 1 - re-pivot and delete

Before deleting the cluster, delete the traefik `LoadBalancer` Service. The CCM
owns that OCI load balancer, and CAPI does not. If that load balancer is still
attached, deleting the cluster hangs on `SubnetReconciliationFailed`, and the
load balancer is orphaned.

With `skipNetworkManagement: true`, CAPOCI does NOT delete the VCN, subnets, or
NSGs. It deletes only what it created: the machines and the API-server NLB. The
BYO VCN stays.

```sh
# 1. re-pivot: move CAPI from the self-managed workload BACK to kind.
#    Run on the VM; it reaches both clusters.
clusterctl move --kubeconfig "$KUBECONFIG_WL" --to-kubeconfig "$KUBECONFIG_KIND"

# 2. remove the CCM-managed load balancer, on the workload cluster
kubectl --kubeconfig "$KUBECONFIG_WL" -n traefik delete service traefik
#    wait until the OCI load balancer is gone (check the OCI console or CLI)

# 3. delete the cluster, from kind - CAPOCI removes the machines and the API NLB
kubectl --kubeconfig "$KUBECONFIG_KIND" delete cluster prow
```

Also delete any debug **bastion** before step 3. After deletion, verify no
`prow` NLBs or running instances remain in the `prow` compartment. The VCN
stays, by design.
