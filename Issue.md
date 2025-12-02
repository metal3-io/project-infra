###Fix redirect links in prow/README.md #1183
The link checker found URLs that redirect to new locations. These should be updated to point directly to the correct URLs:
Redirects in prow/README.md
Current URL 	Redirects To
https://cncfservicedesk.atlassian.net/servicedesk/customer/portals 	https://cncfservicedesk.atlassian.net/servicedesk/customer/user/login?destination=portals
https://github.com/organizations/metal3-io/settings/hooks 	https://github.com/login?return_to=https%3A%2F%2Fgithub.com%2Forganizations%2Fmetal3-io%2Fsettings%2Fhooks
https://github.com/settings/tokens 	https://github.com/login?return_to=https%3A%2F%2Fgithub.com%2Fsettings%2Ftokens
https://go.k8s.io/owners 	https://www.kubernetes.dev/docs/guide/owners/

Related to #1175
https://github.com/metal3-io/project-infra/issues/1183#issue-3685407327