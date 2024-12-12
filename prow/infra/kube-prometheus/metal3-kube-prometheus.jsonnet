local kp =
  (import 'kube-prometheus/main.libsonnet') +
  // (import 'kube-prometheus/addons/all-namespaces.libsonnet') +
  // Uncomment the following imports to enable its patches
  // (import 'kube-prometheus/addons/anti-affinity.libsonnet') +
  // (import 'kube-prometheus/addons/managed-cluster.libsonnet') +
  // (import 'kube-prometheus/addons/node-ports.libsonnet') +
  // (import 'kube-prometheus/addons/static-etcd.libsonnet') +
  // (import 'kube-prometheus/addons/custom-metrics.libsonnet') +
  // (import 'kube-prometheus/addons/external-metrics.libsonnet') +
  // (import 'kube-prometheus/addons/pyrra.libsonnet') +
  {
    values+:: {
      common+: {
        namespace: 'monitoring',
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
// { 'setup/pyrra-slo-CustomResourceDefinition': kp.pyrra.crd } +
// serviceMonitor and prometheusRule are separated so that they can be created after the CRDs are ready
{ 'prometheus-operator-serviceMonitor': kp.prometheusOperator.serviceMonitor } +
{ 'prometheus-operator-prometheusRule': kp.prometheusOperator.prometheusRule } +
{ 'kube-prometheus-prometheusRule': kp.kubePrometheus.prometheusRule } +
{ ['alertmanager-' + name]: kp.alertmanager[name] for name in std.objectFields(kp.alertmanager) } +
// { ['blackbox-exporter-' + name]: kp.blackboxExporter[name] for name in std.objectFields(kp.blackboxExporter) } +
{ ['grafana-' + name]: kp.grafana[name] for name in std.objectFields(kp.grafana) } +
// { ['pyrra-' + name]: kp.pyrra[name] for name in std.objectFields(kp.pyrra) if name != 'crd' } +
{ ['kube-state-metrics-' + name]: kp.kubeStateMetrics[name] for name in std.objectFields(kp.kubeStateMetrics) } +
{ ['kubernetes-' + name]: kp.kubernetesControlPlane[name] for name in std.objectFields(kp.kubernetesControlPlane) }
{ ['node-exporter-' + name]: kp.nodeExporter[name] for name in std.objectFields(kp.nodeExporter) } +
{ ['prometheus-' + name]: kp.prometheus[name] for name in std.objectFields(kp.prometheus) } +
{ ['prometheus-adapter-' + name]: kp.prometheusAdapter[name] for name in std.objectFields(kp.prometheusAdapter) }
