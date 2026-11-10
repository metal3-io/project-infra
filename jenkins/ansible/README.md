# Metal³ CI infrastructure-as-code: Ansible

## Prerequisites (external to this repository)

- the 1password CLI ("op") as well as an appropriate service
  account token
- OpenTofu
- cloud credentials and client configuration
- object store bucket ("tofu")
- object store credentials
- a Netlify API token
- SSH client configuration
   - access to the CI jumphost
   - private half of the configured key pair
    ("metal3ci-keypair") used for the network address range
    ("metal3-ci-net")
- GitHub [application](https://plugins.jenkins.io/github-oauth/#plugin-content-setup)
   - authz callback URL domain must match config.traefik.host\_fqdn

## Credentials (see vault)

- Cloud
- _Netlify_ (_exception_!)
- GPG

## Usage

- export environment variables
   - OP\_SERVICE\_ACCOUNT\_TOKEN (see vault)
   - NETLIFY\_API\_TOKEN (at present the service account - or
    vault - has _no_ token, you **need** your own!)
- `ansible-playbook site.yaml`

### Variables of note

(and their _defaults_; refer to [configuration](./vars/test.yaml) and role
defaults [[host](./roles/host/defaults/main.yaml),
[application](./roles/application/defaults/main.yaml)] for the complete list)

- config.onepassword.vault (_Jenkins-OCI_)
- config.cloud.type (_unset_)
- config.cloud.workspace (_unset_)
- config.cloud.instance\_name (_unset_)
- config.cloud.jumphost\_name (_unset_)
- config.cloud.access\_networks (_unset_)
- config.cloud.ensure\_access\(_false_)
- config.os.update (_yes_)
- config.gpg.cache\_ttl\_seconds (_600_)
- config.images.\* (_component image digests_)
- config.grafana.protect (_no_)
- config.traefik.host\_fqdn (_jenkins.apps.test.metal3.io_)

### Tags

- "_tf_" or "_cloud_" wraps OpenTofu to provision cloud
  infrastructure (can be run separately as well as omitted)
- per-service tags i.e. "_socket-proxy_", "_traefik_" and "_jenkins_"
   - the "jenkins" task also recognizes "_plugins_" and "_jobs_"
