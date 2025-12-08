# Bare Metal Lab (BML) Test Overview

The BML test deploys and validates Metal3 on real bare metal servers. It
automates the full lifecycle: bootstrapping a management cluster
(using Minikube), provisioning bare metal hosts, deploying a CNI,
verifying node readiness, and then deprovisioning and cleaning up all
resources.

**Test Environment:**

- Tests are executed on Server 2 in the bare metal lab, configured as a Jenkins
    worker.

## Pipeline Stages

The BML test pipeline consists of the following stages:

1. **Lab Cleanup (Pre-Test):**
    - Removes any leftover bootstrap clusters from previous runs.
1. **Management Cluster Setup:**
    - Deploys the bootstrap (management) cluster.
1. **Target Cluster Provisioning:**
    - Applies BareMetalHost (BMH) YAMLs, provisions hosts, installs CNI, and
    waits for nodes to reach the running state.
1. **Teardown (Post-Test):**
    - Deprovisions the target cluster and waits for BMHs to return to the
        available state.
1. **Final Cleanup:**
    - Removes the bootstrap cluster if the test completes successfully.

## Test Execution

All actions are orchestrated by the `bml_test.sh` script, which dispatches
Ansible playbooks based on the action argument(`clean`, `deploy`, `run-test`,
`teardown`).

### Ansible Playbook Actions

- **clean:** Cleans the management cluster, network configuration, and images.
- **deploy:** Runs setup scripts (02, 03, 04), applies BMH YAMLs, and waits for
    hosts to become available.
- **run-test:** Applies cluster, control plane, and worker YAMLs; waits for
    node provisioning; installs Calico on the target cluster; and ensures nodes
    are ready.
- **teardown:** Deprovisions the target cluster and waits for BMHs to become
    available.

### Deploy Stage Scripts

- `02_configure_host.sh`: Installs Minikube, configures networking, and
    generates Ironic certificates.
- `03_launch_bootstrap_cluster.sh`: Launches the bootstrap cluster and deploys
    CAPM3, CAPI, IRSO, IPAM, and BMO.
- `04_verify.sh`: Verifies that all pods are running.

## Additional Notes

- The BML test currently cannot be triggered by pull requests. It always tests
    the main branches of CAPM3, IPAM, BMO, and IRSO.
- Due to networking limitations, container and OS images are not downloaded
    from upstream during the test. Instead, pre-downloaded images are used. The
    `preload_images_minikube.sh` script loads container images from the host
    into Minikube.
- The `clean` script does **not** remove container or OS images.
