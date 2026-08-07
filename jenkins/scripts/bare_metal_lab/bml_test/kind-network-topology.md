# Kind Networking Topology for BML

This diagram visualizes the kind-based networking used by the BML flow.

Current model: Docker networks + Linux bridges only. This path does not use
libvirt network definitions.

External uplink behavior is now explicit:

- by default, `external` bridge uses `EXTERNAL_IFACE` (default `bmext`)

Host egress for the external subnet is also enforced by the host setup script:

- validates `192.168.111.1/24` is bound on bridge `external`
- requires `net.ipv4.ip_forward=1` on the host
- installs idempotent `iptables` NAT/FORWARD rules for `192.168.111.0/24`

```mermaid
flowchart LR
  subgraph HOST[Host Linux]
    ENO1[eno1]
    EXT_UPLINK[external uplink<br/>bmext]

    subgraph BR_PROV[Bridge: provisioning 172.22.0.0/24]
      PROV_GW[Host gateway 172.22.0.1<br/>interface ironicendpoint]
      IRONIC_PEER[ironic-peer veth]
    end

    subgraph BR_EXT[Bridge: external 192.168.111.0/24]
      EXT_GW[Host gateway 192.168.111.1]
    end

    ENO1 --- BR_PROV
    EXT_UPLINK --- BR_EXT
    IRONIC_EP[ironicendpoint veth]
    IRONIC_EP --- IRONIC_PEER

    HTTPD[httpd-infra container<br/>host network mode]
    HTTPD --- PROV_GW
  end

  subgraph DOCKER[Docker Networks]
    DPROV[bml-provisioning<br/>bridge name: provisioning]
    DEXT[bml-external<br/>bridge name: external]
  end

  BR_PROV --- DPROV
  BR_EXT --- DEXT

  subgraph KIND[Kind Cluster]
    NODE[bml-control-plane node container]
    NPROV[node NIC 172.22.0.9]
    NEXT[node NIC 192.168.111.9]
    NODE --- NPROV
    NODE --- NEXT

    subgraph K8S[Kubernetes]
      BMO[BMO and CAPM3]
      IRONIC[Ironic service endpoint 172.22.0.2]
    end

    BMO --> IRONIC
  end

  DPROV --- NPROV
  DEXT --- NEXT

  NPROV --> IRONIC
  PROV_GW --> IRONIC
```

## Connectivity Summary

- Provisioning plane:
   - kind node NIC 172.22.0.9 is attached to the provisioning bridge domain.
   - Ironic endpoint 172.22.0.2 is reachable from cluster components over
     this network.
- External plane:
   - kind node NIC 192.168.111.9 is attached to the external bridge domain.
   - provisioned bare-metal hosts use 192.168.111.1 as their external
     gateway.
   - by default, external traffic uses uplink `bmext`.
- Image serving:
   - httpd-infra serves deployment images through the provisioning side.
   - the local bootstrap registry is published on host port 5000 and is
     reachable as 192.168.111.1:5000 from the external subnet.
- DNS for provisioned nodes:
   - manifests use `${EXTERNAL_DNS_V4}` (rendered in `run-test.yaml`) instead
     of a fixed resolver.

## Topology Including Real Bare Metal Hosts

```mermaid
flowchart LR
  subgraph HOST[Host Linux]
    ENO1[eno1]
    EXT_UPLINK[external uplink<br/>bmext]

    subgraph BR_PROV[Bridge: provisioning 172.22.0.0/24]
      PROV_HOST[Host IP 172.22.0.1<br/>interface ironicendpoint]
      IRONIC_PEER[ironic-peer]
    end

    subgraph BR_EXT[Bridge: external 192.168.111.0/24]
      EXT_HOST[Host IP 192.168.111.1]
    end

    ENO1 --- BR_PROV
    EXT_UPLINK --- BR_EXT

    HTTPD[httpd-infra<br/>host network mode]
    HTTPD --- PROV_HOST
  end

  subgraph DOCKER[Docker Networks]
    DPROV[bml-provisioning]
    DEXT[bml-external]
  end

  BR_PROV --- DPROV
  BR_EXT --- DEXT

  subgraph KIND[Kind Cluster]
    NODE[bml-control-plane]
    NPROV[Node NIC 172.22.0.9]
    NEXT[Node NIC 192.168.111.9]
    NODE --- NPROV
    NODE --- NEXT

    subgraph K8S[Kubernetes Components]
      BMO[BMO and CAPM3]
      IRONIC[Ironic API 172.22.0.2]
    end

    BMO --> IRONIC
  end

  DPROV --- NPROV
  DEXT --- NEXT

  subgraph BAREMETAL[Real Bare Metal Servers]
    BM1[baremetal-host-1]
    BM2[baremetal-host-2]
    BMN[baremetal-host-n]
  end

  BM1 --- BR_PROV
  BM2 --- BR_PROV
  BMN --- BR_PROV

  BM1 ---|data plane| BR_EXT
  BM2 ---|data plane| BR_EXT
  BMN ---|data plane| BR_EXT

  BM1 -->|DHCP PXE iPXE| IRONIC
  BM2 -->|DHCP PXE iPXE| IRONIC
  BMN -->|DHCP PXE iPXE| IRONIC

  BM1 -->|Fetch deploy image| HTTPD
  BM2 -->|Fetch deploy image| HTTPD
  BMN -->|Fetch deploy image| HTTPD
```

### Bare Metal Flow Notes

- Provisioning traffic (DHCP, iPXE, IPA image fetch) stays on
  `provisioning` bridge.
- Real hosts download deploy artifacts from `httpd-infra` via `172.22.0.1`.
- Ironic API and provisioning services are reached through the same
  provisioning domain.

## Interface-Level Communication Paths

```mermaid
flowchart LR
  subgraph HOST[Host]
    ENO1[eno1]
    EXT_UPLINK[external uplink]
    BRPROV[bridge provisioning]
    BREXT[bridge external]
    IEP[ironicendpoint]
    IPR[ironic-peer]
    HTTPD[httpd-infra]
    REG[registry]
  end

  subgraph DOCKER[Docker]
    DPROV[bml-provisioning]
    DEXT[bml-external]
  end

  subgraph KIND[Kind node bml-control-plane]
    KPROV[kind iface on 172.22.0.0/24]
    KEXT[kind iface on 192.168.111.0/24]
    IRONIC[Ironic]
  end

  subgraph BM[Real bare metal host]
    BMPROV[provisioning NIC]
    BMEXTIF[external NIC]
  end

  ENO1 -->|member| BRPROV
  EXT_UPLINK -->|member| BREXT
  IEP -->|veth pair| IPR
  IPR -->|member| BRPROV
  HTTPD -->|PROVISIONING_INTERFACE=ironicendpoint| IEP
  REG -->|host port 5000| BREXT

  BRPROV --> DPROV
  BREXT --> DEXT

  DPROV --> KPROV
  DEXT --> KEXT

  KPROV -->|detected in 03 script by 172.22.0.x| IRONIC
  BMPROV -->|DHCP PXE iPXE image fetch| BRPROV
  BMEXTIF -->|default route and registry access| BREXT
```

### Interface Mapping

- Host to provisioning plane:
   - `eno1` is attached to `provisioning` bridge.
   - `ironicendpoint` and `ironic-peer` connect the host network stack to the
     same provisioning bridge.
- Host image serving:
   - `httpd-infra` uses host networking and serves images via
     `ironicendpoint`.
- Host local registry:
   - `registry` is exposed on host port `5000` and is reachable from the
     external subnet via `192.168.111.1:5000`.
- Host external uplink:
   - `external` bridge member is selected by `resolve_external_iface`.
   - default path is `EXTERNAL_IFACE` (default `bmext`).
- Host egress enforcement:
   - host setup enables IPv4 forwarding and adds NAT/FORWARD rules for
     `192.168.111.0/24` toward the host default route interface.
- Kind node to provisioning plane:
   - the node interface on `172.22.0.0/24` is discovered dynamically and used
     as the Ironic provisioning interface.
- Kind node to external plane:
   - the node interface on `192.168.111.0/24` carries external network access.
- Bare metal host paths:
   - the provisioning NIC reaches DHCP, iPXE, Ironic, and image-serving over
     the `provisioning` bridge.
   - the external NIC carries the default route and access toward
     `192.168.111.1:5000`.
