# OpenTofu

## Configuration content

### Data sources (queried in run-time)

- data.oci\_core\_images.rocky
- data.oci\_core\_vcns.private
- data.oci\_core\_subnets.private
- data.netlify\_dns\_zone.domain
- data.http.myip

### Resources (managed)

- oci\_core\_instance.server
- oci\_core\_network\_security\_group.access
- oci\_core\_network\_security\_group\_security\_rule.https["0.0.0.0/0"]
- oci\_core\_network\_security\_group\_security\_rule.ssh
- netlify\_dns\_record.host\_fqdn

### Prerequisites (unmanaged resources external to this configuration)

- Netlify DNS zone
- Oracle Cloud Infrastructure:
   - tenancy, compartment, user, key
   - container ("tofu"), policy, AK/SK
   - VCN, subnet

### Credentials

- Cloud
- Netlify

### Variables (and their _default values_)

- compartment\_id (_empty_)
- availability\_domain (_SdxX:EU-PARIS-1-AD-1_)
- host\_fqdn (_ci.apps.test.metal3.io_)
- instance\_name (_jenkins-poc_)
- image\_id (_empty_, discovered by name: "Rocky-10-\*")
- shape (_VM.Standard.E4.Flex_)
- ocpus (_2_)
- memory\_gb (_16_)
- ssh\_public\_key\_file (_unset_)
- private\_network (_metal3ci-network_)
- web\_access\_networks (_[0.0.0.0/0]_)
- ensure\_access (_false_)

## Usage

- export environment variables (see vault for credentials)
   - AWS\_ACCESS\_KEY\_ID
   - AWS\_SECRET\_ACCESS\_KEY
   - NETLIFY\_API\_TOKEN
   - TF\_WORKSPACE=test
- `tofu plan`
