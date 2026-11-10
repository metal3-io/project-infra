# OpenTofu

## Configuration content

### Data sources (queried in run-time)

- data.openstack\_compute\_instance\_v2.jumphost
- data.openstack\_images\_image\_v2.boot\_image
- data.openstack\_networking\_network\_v2.private
- data.openstack\_networking\_port\_v2.private
- data.netlify\_dns\_zone.domain
- data.http.myip

### Resources (managed)

- openstack\_blockstorage\_volume\_v3.boot
- openstack\_compute\_instance\_v2.server
- openstack\_networking\_floatingip\_v2.external
- openstack\_networking\_floatingip\_associate\_v2.access
- openstack\_networking\_secgroup\_v2.access
- openstack\_networking\_secgroup\_rule\_v2.https["0.0.0.0/0"]
- openstack\_networking\_secgroup\_rule\_v2.ssh
- netlify\_dns\_record.host\_fqdn

### Prerequisites (unmanaged resources external to this configuration)

- Netlify DNS zone
- OpenStack:
   - project, user, role
   - container ("tofu"), EC2 credential
   - volume type
   - flavor, keypair, jumphost instance
   - networks, subnets, router

### Credentials

- Cloud
- Netlify

### Variables (and their _default values_)

- host\_fqdn (_ci.apps.test.metal3.io_)
- instance\_name (_jenkins-poc_)
- image\_id (_empty_, discovered by tags: rocky, v10, latest)
- volume\_size (_10_)
- volume\_type (_performance_)
- flavor (_c4m16-est_)
- external\_network (_internet_)
- key (_metal3ci-keypair_)
- private\_network (_metal3-ci-net_)
- jumphost\_id (_empty_, passed by Ansible)
- web\_access\_networks (_[0.0.0.0/0]_)
- ensure\_access (_false_)

## Usage

- export environment variables (see vault for credentials)
   - AWS\_ACCESS\_KEY\_ID
   - AWS\_SECRET\_ACCESS\_KEY
   - NETLIFY\_API\_TOKEN
   - TF\_WORKSPACE=test
- `tofu plan`
