# Baremetal Lab Setup

The Bare Metal Lab needs some special treatment compared to other pipelines
since it does not use VMs for the target cluster. This is taken care of in the
`deploy-lab.yaml` playbook.

## Ansible installation

`sudo pip3 install ansible`

## Running the playbook

* Comment/uncomment the hosts you want to use in the `vars` section of
  `deploy-lab.yaml`
* Set environment variables `BML_ILO_USERNAME` and `BML_ILO_PASSWORD` for the
  login to the bare metal hosts

Then:

`ansible-playbook ./deploy-lab.yaml -u <user> --ask-become-pass`

## Running tests for pull requests on Github

You can trigger builds to run in the bare metal lab by adding the following
line as a comment on the PR:

```text
/test-integration-bml-centos
```

**Note:** Concurrent builds are disabled for the BML, since they would run on
the same host and interfere with each other. This means that if there is already
one build job running in the BML, a new one will not start before the first has
finished. Github won't show the usual *Details* link for this specific run but
build status can be checked from the
[Jenkins dashboard](https://jenkins.nordix.org/job/metal3-bml-integration-test-centos/)
where the build will be scheduled and stay in pending at this time.
Once the build starts, the status will be updated with a link.
