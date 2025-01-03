# Monitoring of K8s cluster and Prow resources

This is a wip that provides insight into how to monitor k8s
cluster resources and prow services.

The k8s is based on the kubernetes mixins that can found here:
[k8s-mixin](https://github.com/kubernetes-monitoring/kubernetes-mixin)

The steps to set this up is the following and is tested to work in minikube.
In our case we need to integrate this to the granfana.yaml here.

The main detail is the generation of the resources and deciding if we want
to generate these dynamically or if we take a static snapshot of the yaml
and use that. Currently there is static snapshot in grafana-dashboard-definitions.

Also the kustomize.yaml resource needs to be created it should be able
to automate the process of creating a configmap out of grafana-dashboard-definitions

Further for the alertmanager to automate the alerts the slackwebhook needs to be created as
a secret. This can be done the sameway as the secrets in
`project-infra/prow/manifests/overlays/metal3`

## Deploying Grafana with Kubernetes-mixins


### Step 1: Install Prometheus and Grafana using Helm

NOTE: We will most likely not use helm but kustomize, only used helm for a quick poc

First, add the Helm repositories for Prometheus and Grafana:

```kubectl
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

Now, install Prometheus and Grafana:

```kubectl
helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
```

This command installs the Prometheus stack, which includes Prometheus, Alertmanager, and Grafana.

### Step 2: Access Grafana

Expose the Grafana service using `kubectl port-forward`:

```kubectl
kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
```

You can now access Grafana at `http://localhost:3000`. The default login is:

- **Username:** `admin`
- **Password:** `prom-operator`

### Step 3: Generate and Create a ConfigMap for Grafana Dashboards

Assuming you have cloned the kubernetes-mixin You can manually generate the
alerts, dashboards and rules files, but first you must install some tools:

```
$ go install github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@latest
$ brew install jsonnet
```

Then, grab the mixin and its dependencies:

```
$ git clone https://github.com/kubernetes-monitoring/kubernetes-mixin
$ cd kubernetes-mixin
$ jb install
```

Finally, build the mixin:

```
$ make prometheus_alerts.yaml
$ make prometheus_rules.yaml
$ make dashboards_out
```
1. To apply the rules and alerts you need to add the following to the files

    So add the following header and replace the groups with whatever was generated
   
   ```yaml
    apiVersion: monitoring.coreos.com/v1
    kind: PrometheusRule
    metadata:
    name: kubernetes-mixin-alerts
    namespace: monitoring
    spec:
        "groups":
            ...
   ```

2. Create a ConfigMap with the Grafana dashboards:

    ```kubectl
    kubectl create configmap grafana-dashboards --from-file=dashboards_out/ -n monitoring
    ```

    This command creates a ConfigMap named `grafana-dashboards` in the
    `monitoring` namespace, containing all the JSON files in the
    `dashboards_out/` directory. This needs to be mounted to grafana
    in the following steps

### Step 4: Configure Grafana to Load Dashboards from the ConfigMap

Patch the Grafana deployment:

1. **Edit the Grafana deployment:**

    ```kubectl
    kubectl edit deployment prometheus-grafana -n monitoring
    ```

2. **Add the following under `spec` > `volumes`:**

    ```yaml
    volumes:
      - name: grafana-dashboards
        configMap:
          name: grafana-dashboards
    ```

3. **Mount the volume under `containers` > `volumeMounts`:**

    ```yaml
    volumeMounts:
      - name: grafana-dashboards
        mountPath: /var/lib/grafana/dashboards
    ```

4. **Ensure Grafana is configured to load dashboards:**

    Ensure that Grafana is set up to load dashboards from the specified directory:

    ```yaml
    env:
      - name: GF_DASHBOARDS_JSON_ENABLED
        value: "true"
      - name: GF_DASHBOARDS_JSON_PATH
        value: "/var/lib/grafana/dashboards"
    ```

### Step 5: Verify the Dashboards in Grafana

After applying the changes, Grafana should automatically load the dashboards from the ConfigMap.

1. Access Grafana at `http://localhost:3000`.
2. Navigate to "Dashboards" > "Manage" and you should see the dashboards listed and ready to use.


