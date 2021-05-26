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
