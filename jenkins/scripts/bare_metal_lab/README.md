# Baremetal Lab Setup

This repo is created to setup the baremetal lab for metal3.

## Ansible installation

`sudo pip3 install ansible`

## Running the playbook

* Set 'bm-m3-lab' to the IP address of the lab in /etc/hosts.
* Fill in the BMH resource definition in templates/
* Set environment variables `BML_ILO_USERNAME` and `BML_ILO_PASSWORD` for the login to the bare metal hosts

Then:

`ansible-playbook ./deploy-lab.yaml -i ./hosts -u <user> --ask-become-pass`

## Running tests for pull requests on Github

You can trigger builds to run in the bare metal lab by adding the following line as a comment on the PR:

```
/test-integration-bml-centos
```

**Note:** Concurrent builds are disabled for the BML, since they would run on the same host and interfere with each other.
This means that if there is already one build job running in the BML, a new one will not start before the first has finished.
Github won't show the usual *Details* link for this specific run but build status can be checked from the [Jenkins dashboard](https://jenkins.nordix.org/job/airship_metal3io_project_infra_bml_integration_tests_centos/) where the build will be scheduled and stay in pending at this time.
Once the build starts, the status will be updated with a link.
