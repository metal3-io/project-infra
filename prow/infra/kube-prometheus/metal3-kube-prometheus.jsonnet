// addArgs adds the args to the container with matching name
local addArgs(args, name, containers) = std.map(
  function(c) if c.name == name then
    c {
      args+: args,
    }
  else c,
  containers,
);

local kp =
  (import 'kube-prometheus/main.libsonnet') +
  {
    values+:: {
      common+: {
        namespace: 'monitoring',
      },
      grafana+: {
        dashboards+:: {  // use this method to import your dashboards to Grafana
          'jobs.json': (import 'jobs.json'),
        },
        rawDashboards+:: {
          'jobs.json': (importstr 'jobs.json'),
        },
        config+: {
          sections: {
            'auth.anonymous': {
              enabled: true,
              org_role: 'Viewer',
            },
            'auth': {
              disable_login_form: true,
            },
            'auth.basic': {
            enabled: false,
            },
            'security': {
              disable_gravatar: true,
            },
          },
        },
      },
    },
    // Add toleration and node selector to all components
    prometheus+: {
      prometheus+: {
        spec+: {
          tolerations: [
            {
              key: "node-role.kubernetes.io/infra",
              operator: "Exists",
              effect: "NoSchedule",
            },
          ],
          nodeSelector+: {
            'node-role.kubernetes.io/infra': "",
          },
          // If a value isn't specified for 'retention', then by default the '--storage.tsdb.retention=24h' arg will be passed to prometheus by prometheus-operator.
          // The possible values for a prometheus <duration> are:
          //  * https://github.com/prometheus/common/blob/c7de230/model/time.go#L178 specifies "^([0-9]+)(y|w|d|h|m|s|ms)$" (years weeks days hours minutes seconds milliseconds)
          retention: '30d',

          // Reference info: https://github.com/coreos/prometheus-operator/blob/master/Documentation/user-guides/storage.md
          // By default (if the following 'storage.volumeClaimTemplate' isn't created), prometheus will be created with an EmptyDir for the 'prometheus-k8s-db' volume (for the prom tsdb).
          // This 'storage.volumeClaimTemplate' causes the following to be automatically created (via dynamic provisioning) for each prometheus pod:
          //  * PersistentVolumeClaim (and a corresponding PersistentVolume)
          //  * the actual volume (per the StorageClassName specified below)
          storage: {
            volumeClaimTemplate: {
              apiVersion: 'v1',
              kind: 'PersistentVolumeClaim',
              spec: {
                accessModes: ['ReadWriteOnce'],
                resources: { requests: { storage: '100Gi' } },
                storageClassName: 'csi-cinderplugin',
              },
            },
          },
        }
      },
    },
    prometheusOperator+: {
      deployment+: {
        spec+: {
          template+: {
            spec+: {
              tolerations: [
                {
                  key: "node-role.kubernetes.io/infra",
                  operator: "Exists",
                  effect: "NoSchedule",
                },
              ],
              nodeSelector+: {
                "node-role.kubernetes.io/infra": "",
              },
            },
          },
        }
      },
    },
    prometheusAdapter+: {
      deployment+: {
        spec+: {
          template+: {
            spec+: {
              tolerations: [
                {
                  key: "node-role.kubernetes.io/infra",
                  operator: "Exists",
                  effect: "NoSchedule",
                },
              ],
              nodeSelector+: {
                "node-role.kubernetes.io/infra": "",
              },
            },
          },
        }
      },
    },
    alertmanager+: {
      alertmanager+: {
        spec+: {
          tolerations: [
            {
              key: "node-role.kubernetes.io/infra",
              operator: "Exists",
              effect: "NoSchedule",
            },
          ],
          nodeSelector+: {
            "node-role.kubernetes.io/infra": "",
          },
        },
      },
    },
    grafana+: {
      deployment+: {
        spec+: {
          template+: {
            spec+: {
              tolerations: [
                {
                  key: "node-role.kubernetes.io/infra",
                  operator: "Exists",
                  effect: "NoSchedule",
                },
              ],
              nodeSelector+: {
                "node-role.kubernetes.io/infra": "",
              },
            },
          },
        }
      },
    },
    kubeStateMetrics+: {
      deployment+: {
        spec+: {
          template+: {
            spec+: {
              tolerations: [
                {
                  key: "node-role.kubernetes.io/infra",
                  operator: "Exists",
                  effect: "NoSchedule",
                },
              ],
              nodeSelector+: {
                "node-role.kubernetes.io/infra": "",
              },
              // Add allowed labels. We need these labels to keep track of what prowjob each pod belongs to
              containers: addArgs(
                ['--metric-labels-allowlist=pods=[' +
                      'app.kubernetes.io/name,' +
                      'app.kubernetes.io/component,' +
                      'app.kubernetes.io/instance,' +
                      'prow.k8s.io/id,' +
                      'prow.k8s.io/refs.repo,' +
                      'prow.k8s.io/type,' +
                      'prow.k8s.io/job,' +
                      'prow.k8s.io/refs.org],' +
                    'deployments=[' +
                      'app.kubernetes.io/name,' +
                      'app.kubernetes.io/component,' +
                      'app.kubernetes.io/instance]'
                ],
                'kube-state-metrics',
                super.containers
              ),
            },
          },
        }
      },
    },
  };

{ 'setup/0namespace-namespace': kp.kubePrometheus.namespace } +
{
  ['setup/prometheus-operator-' + name]: kp.prometheusOperator[name]
  for name in std.filter((function(name) name != 'serviceMonitor' && name != 'prometheusRule'), std.objectFields(kp.prometheusOperator))
} +
// serviceMonitor and prometheusRule are separated so that they can be created after the CRDs are ready
{ 'prometheus-operator-serviceMonitor': kp.prometheusOperator.serviceMonitor } +
{ 'prometheus-operator-prometheusRule': kp.prometheusOperator.prometheusRule } +
{ 'kube-prometheus-prometheusRule': kp.kubePrometheus.prometheusRule } +
{ ['alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
{ ['grafana-' + name]: kp.grafana[name] for name in std.objectFields(kp.grafana) } +
{ ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
{ ['kubernetes-' + name]: kp.kubernetesControlPlane[name] for name in std.objectFields(kp.kubernetesControlPlane) }
{ ['node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
{ ['prometheus-' + name]: kp.prometheus[name] for name in std.objectFields(kp.prometheus) } +
{ ['prometheus-adapter-' + name]: kp.prometheusAdapter[name] for name in std.objectFields(kp.prometheusAdapter) }
