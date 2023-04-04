# SSL certificates

Managed by [cert-manager](https://cert-manager.io).

## Installation Process

```bash
oc create namespace cert-manager
oc apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v0.12.0/cert-manager-openshift.yaml
```

## Ingress

Create Secret `cloudflare-apikey-secret`:

```bash
kubectl create secret generic cloudflare-apikey-secret \
    --from-literal "apikey=<API_KEY>" --namespace=cert-manager
```

Create letsencrypt `ClusterIssuer`:

```bash
oc apply -f cluster-issuer.yaml
```

Create a request for a certificate to use for Ingress:

```bash
oc apply -f certificate.yaml
```

Configure the cluster to use the new certificate
([docs](https://docs.openshift.com/container-platform/4.2/networking/ingress-operator.html)):

```bash
oc patch --type=merge --namespace openshift-ingress-operator \
    ingresscontrollers/default --patch \
    '{"spec":{"defaultCertificate":{"name":"metal3-io-tls"}}}'
```
