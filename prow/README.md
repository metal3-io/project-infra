# Prow

Metal3 Prow dashboard: https://prow.apps.test.metal3.io

## Access Controls

* To merge, patches must have `/approve` and `/lgtm`, which apply the `approved` and `lgtm` labels

* The use of `/approve` and `/lgtm` is controlled by the `OWNERS` file in each repository.
  See the [OWNERS spec](https://go.k8s.io/owners) for more details about how
  to manage access to all or part of a repo with this file.

* Tests will run automatically for PRs authored by **public** members of the
  `metal3-io` github organization.  Members of the github org can run
  `/ok-to-test` for PRs authored by those not in the github org.

See the [Prow command help](https://prow.apps.test.metal3.io/command-help) for
more information about who can run each prow command.

## GCS bucket

Google Cloud Storage (GCS) is required to store job artifacts. Follow the docs to set
up GCS and create a bucket with enough permissions.

1. Create a [bucket](https://cloud.google.com/storage/docs/creating-buckets)
1. Create a [service account](https://cloud.google.com/iam/docs/creating-managing-service-accounts)
1. On the created bucket, grant `storage.objects.create` access for the service account and `storage.objectViewer`
   permission to `allUser`.

## Setup

Prow was set up by following these instructions: https://github.com/kubernetes/test-infra/blob/master/prow/getting_started_deploy.md

1. Create DNS record(s) to point to your cluster.

1. Prow components are running on `default` namespace, while `test-pods` namespace
   is used by pods running the actual CI jobs.

1. [ghProxy](https://github.com/kubernetes/test-infra/tree/master/ghproxy) is a reverse proxy,
   and is meant to reduce API token usage. We need persistent volume for ghProxy, and for that
   purpose we rely on `hostPath` type of `PersistentVolume` in our cluster due to the limitation
   in the underlying infrastructure. Ideally, you should use a dynamic storage provisioner.

   Create a /mnt/prow directory to store the persistent volume data:

     ```shell
     $ sudo mkdir /mnt/prow
     ```

     Create the PersistentVolume:

     ```shell
     $ kubectl apply -f persistent_volume.yaml
     ```

1. Grant a user `cluster-admin` role in all namespaces to create cluster resources.

    ```shell
    $ kubectl create clusterrolebinding cluster-admin-binding-"${USER}" \
      --clusterrole=cluster-admin --user="${USER}"
    ```

1. Create HMAC token for webhook validation and generate a secret out of it. Don't forget to add this token
   on GitHub webhook configuration.

    ```shell
    $ openssl rand -hex 20 > /path/hmac-token
    $ kubectl create secret generic hmac-token --from-file=hmac=/path/hmac-token
    ```

1. Create a personal access token for the GitHub
   bot account. This should be done from [metal3-io-bot](https://github.com/metal3-io-bot)
   GitHub bot account. You can follow this [link](https://github.com/settings/tokens)
   to create the token. When generating the token, make sure you have only the following scopes checked in.

   - `repo` scope for full control of private repositories
   - `admin:org_hook` for a github org


   ![token-scopes](images/token-scopes.png)

    Create a secret out of that token:
    ```shell
    $ kubectl create secret generic github-token --from-file=token=/path/github-token
    ```

1. Create a secret with the GCS credentials

   ```shell
   $ kubectl create secret generic gcs-credentials --from-file=service-account.json=service-account.json
   ```

1. While applying prow manifests, we are going to create an Ingress object to redirect traffic to the deck and hook services.
   We are installing [NGINX Ingress controller](https://kubernetes.github.io/ingress-nginx/deploy/) with helm, but you can
   install your preferred one.

   ```shell
   helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
   helm install ingress-nginx/ingress-nginx --set controller.hostNetwork=true,controller.service.type="",controller.kind=DaemonSet --generate-name
   helm repo update
   ```

1. Apply Prow manifests

   ```shell
   kubectl apply -f manifests/*
   ```

   This will create a couple of Deployments, Services, ServiceAccounts, Roles, RoleBindings and Ingress resources.

## Secure Ingress with Cert-Manager and Let's Encrypt

1. Install [cert-manager](https://github.com/jetstack/cert-manager)

   ```
   $ helm repo add jetstack https://charts.jetstack.io
   $ helm repo update
   $ helm install \
   cert-manager jetstack/cert-manager \
   --namespace cert-manager \
   --create-namespace \
   --version v1.3.1 \
   --set installCRDs=true
   ```

   Verify that you have the following pods running
   ```shell
   $ kubectl get pods --namespace cert-manager

     NAME                                       READY   STATUS    RESTARTS   AGE
     cert-manager-5c6866597-zw7kh               1/1     Running   0          2m
     cert-manager-cainjector-577f6d9fd7-tr77l   1/1     Running   0          2m
     cert-manager-webhook-787858fcdb-nlzsq      1/1     Running   0          2m
   ```

1. Create a secret containing your Cloudflare API token.

   ```shell
   $ kubectl create secret generic cloudflare-api-token-secret --from-literal "apikey=<API_KEY>" --namespace=cert-manager
   ```

   metal3.io domain DNS configurations are managed via Cloudflare. We use [DNS-01 challenge](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge) in our [`ClusterIssuer`](https://cert-manager.io/docs/concepts/issuer/)
   to prove that we own metal3.io domain. As such, we need to provide Cloudflare api key so
   that validation of the domain with DNS-01 challange passes. Cloudflare api key is stored
   as K8S secret, and the only thing you need to do is - add the name of the secret in
   cluster-issuer solvers configuration.

   ```shell
   apiKeySecretRef:
      name: cloudflare-api-token # name of the secret
      key: apikey
   ```

1. Create a ClusterIssuer that contacts [Let’s Encrypt](https://letsencrypt.org/) in order to issue certificates.

   ```shell
   $ kubectl apply -f ssl/cluster_issuer.yaml
   ```

1. Update the Ingress to include tls

   You need to annotate the Ingress with `cert-manager.io/cluster-issuer: letsencrypt-prod` to trigger certificats to be automatically created. See the list of available annotations [here](https://cert-manager.io/docs/usage/ingress/#supported-annotations)

   ```shell
   $ kubectl annotate ingress prow cert-manager.io/cluster-issuer=letsencrypt-prod
   ```

   Edit the ingress to add the following under the spec

   ```
   spec:
      tls:
      - hosts:
         - prow.apps.test.metal3.io
        secretName: metal3-io-tls
   ```

## GitHub webhook configuration

GitHub webhook needs to be configured with a payload URL pointing to the hook service. For that you need
1. HMAC token generated earlier
2. https://PROW_URL/hook, in our case it is https://prow.apps.test.metal3.io/hook

Add the URL and token as below. Select **"Send me everything"**, and for Content ype: **application/json**.

![webhook](images/webhook.png)

## Enabling Metal3 prow for new org/repo

Metal3 prow is currently working with two Github organizations(orgs): `metal3-io` and `Nordix`. For `Nordix` we have enabled prow only for two repositories, namely: metal3-dev-tools and metal3-clusterapi-docs. We don't foresee enabling Metal3 prow for any other Github org, however we might need to enable prow in other repositories in existing Github orgs for example. In any case we should follow the steps below to enable prow:

1. Add/check `metal3-io-bot` user in the Github org with `admin` access. Check the image 

![](images/metal3-io-bot.png)

2. Enable prow webhook as described in [GitHub webhook configuration](#github-webhook-configuration) section. For `metal3-io` the webhook is enabled in org level. For the two repositories in `Nordix` org we have enabled them on individual repositories. Keep in mind that the HMAC token and hook URL are the same as described in [GitHub webhook configuration](#github-webhook-configuration). The webhook should look happy (green tick) as shown in the image below once you have configured it correctly and communication has been established between Github and prow hook. 

![](images/green_webhook.png)

3. Check the general settings and branch protection settings of Github repository and make sure the settings are correct. Take any existing repository which has prow enabled as example (i.e. `Nordix/metal3-dev-tools`).

4. Add the `OWNERS` file in the repository. 

5. Add the repository entry and related configurations in the files `prow/config/config.yaml` and `prow/config/plugins.yaml` in `metal3-io/project-infra` repository. An example PR is [here](https://github.com/metal3-io/project-infra/pull/473/). 

6. One small tweak might still be needed. We have experienced the default `merge_method` of prow which is `merge` didn't work for Nordix repos. The other two options for `merge_method` are: `rebase` and `squash`. We have enabled `rebase` for Nordix repos but kept `merge` for metal3-io org. An example is shown in this [PR](https://github.com/metal3-io/project-infra/pull/476/).

7. At this point you should see the prow tests you have configured as presubmits for the repository, running on open PRs and tide is enabled and waiting for appropriate labels. 