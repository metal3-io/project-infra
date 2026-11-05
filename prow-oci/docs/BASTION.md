<!-- cSpell:ignore kubeconfig OCID OCIDs capoci eu-paris kubectl -->

# Maintainer access - OCI Bastion

After the pivot the workload cluster is self-managed. The kind VM is no longer
needed as a management plane. A maintainer reaches the private API endpoint
through the OCI Bastion service. The Bastion gives a short per-session tunnel.
There is no standing VM to patch and secure.

This doc also covers decommissioning the bootstrap VM: once bastion access is
proven (step 6), the VM has no further role and can be removed.

Do the steps in order. The OCIDs below are for this deployment (eu-paris-1).

## 1. Set the inputs

```sh
# Path to your oci CLI. If `oci` is on PATH, use: export OCI=oci
# Otherwise point to your install (venv, pipx, Homebrew, etc.), e.g.
#   export OCI=~/oci-cli-venv/bin/oci
export OCI=oci
C=ocid1.compartment.oc1..aaaaaaaarfgj34vubf272dhpvnklt63gr5xsxk5ajvjxurialhzduzcexevq
# a subnet in the VCN that can reach the control-plane. Use the control-plane
# subnet (10.0.0.0/29). The bastion lives here.
SUBNET_CP=ocid1.subnet.oc1.eu-paris-1.aaaaaaaanernef6ab2xwjl3aguhozucqdqmtoch5ayrjivjlwsrgj4peekla
```

## 2. Create the bastion (once)

The create returns a WORK REQUEST, not the bastion. `--wait-for-state` takes a
work-request state (`SUCCEEDED`), not a lifecycle state (`ACTIVE`). The bastion
OCID is in `resources[].identifier` of the output.

```sh
"$OCI" bastion bastion create \
  --bastion-type standard \
  -c "$C" \
  --target-subnet-id "$SUBNET_CP" \
  --name prow-maintainer \
  --client-cidr-list '["0.0.0.0/0"]' \
  --wait-for-state SUCCEEDED
# copy the bastion OCID from resources[].identifier, then:
BASTION=<bastion-ocid>
```

Tighten `--client-cidr-list` to the maintainer IP in production. `0.0.0.0/0`
allows any source to reach the bastion host (the SSH key still gates access).

## 3. Get the control-plane node IP

Target the control-plane NODE IP, not the API-server NLB VIP. A port-forward to
the VIP did not pass traffic in testing; a port-forward to the node works. (The
NLB VIP is also dynamic per cluster, which makes it a poor fixed target.)

```sh
kubectl --kubeconfig "$KUBECONFIG_WL" get nodes -o wide | grep control-plane
# take the INTERNAL-IP, e.g. 10.0.0.4
CP_IP=<control-plane-node-ip>
```

## 4. Create a port-forwarding session

```sh
"$OCI" bastion session create-port-forwarding \
  --bastion-id "$BASTION" \
  --target-private-ip "$CP_IP" --target-port 6443 \
  --session-ttl 10800 --key-type PUB \
  --ssh-public-key-file ~/.ssh/id_ed25519.pub \
  --display-name prow-kubectl \
  --wait-for-state SUCCEEDED
# copy the session OCID from resources[].identifier, then:
SESSION=<bastionsession-ocid>

# read the ready-made ssh command
"$OCI" bastion session get --session-id "$SESSION" \
  --query 'data."ssh-metadata".command' --raw-output
```

## 5. Open the tunnel

Fill the key and a local port into the printed command. Forward the local port
to the SAME `CP_IP:6443`. Leave it running; open a second shell for kubectl.

```sh
ssh -i ~/.ssh/id_ed25519 -N -L 6444:"$CP_IP":6443 -p 22 \
  "$SESSION"@host.bastion.eu-paris-1.oci.oraclecloud.com
```

## 6. Use kubectl through the tunnel

The API cert lists the node IPs, not the NLB VIP. So set `--tls-server-name` to
the node IP you forwarded to. This keeps TLS verification.

```sh
kubectl --kubeconfig "$KUBECONFIG_WL" \
  --server https://127.0.0.1:6444 \
  --tls-server-name "$CP_IP" get nodes
```

Expect the node list. That proves bastion access without the VM.

## 7. When the control-plane node is replaced - re-look up its IP

Always target the control-plane NODE IP. Do NOT use the NLB VIP: it did not pass
a port-forward in testing and it is dynamic (it was `10.0.0.10` on one build and
`10.0.0.12` on the next).

The node IP is also dynamic. A new control-plane machine (a roll, a rebuild, or
a repair) gets a new IP. So the target is not fixed. When kubectl stops working
after a control-plane change, redo the flow with the new IP:

1. Read the current node IP again (section 3): `kubectl get nodes -o wide |
   grep control-plane`, take the new `INTERNAL-IP`, set `CP_IP`.
1. Create a new port-forwarding session to the new `CP_IP` (section 4).
1. Open the tunnel to the new `CP_IP` (section 5).
1. Run kubectl with `--tls-server-name "$CP_IP"` (section 6).

No cluster change is needed. CAPOCI adds the control-plane node IP to the API
cert SANs on its own, so `--tls-server-name "$CP_IP"` keeps TLS verification for
whatever the current node IP is. There is nothing to pin and no `certSANs` edit
to make.

## 8. Clean up the bastion

Delete the session and the bastion when you are done. Do this before any
cluster or VCN teardown: a leftover bastion or orphan NLB in a managed subnet
can block network teardown.

```sh
"$OCI" bastion session delete --session-id "$SESSION" --force
"$OCI" bastion bastion delete --bastion-id "$BASTION" --force
"$OCI" bastion bastion list -c "$C" \
  --query 'data[].{name:name,state:"lifecycle-state"}' --output table   # empty
```
