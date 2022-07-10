local defaults = {
  local defaults = self,
  name: 'promtail',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide promtail image',
  imagePullPolicy: 'IfNotPresent',
  ports: {
    http: 3101,
  },
  loki: {
    host: error 'loki.host is required',
    port: error 'loki.port is required',
  },
  config: {},
  resources: {
    requests: {
      cpu: '100m',
      memory: '100Mi',
    },
  },
  extraArgs: [],
  serviceMonitor: false,

  podSecurityContext: {
    runAsUser: 0,
    runAsGroup: 0,
  },

  containerSecurityContext: {
    readOnlyRootFilesystem: true,
    capabilities: {
      drop: ['ALL'],
    },
    allowPrivilegeEscalation: false,
  },

  tolerations: [
    {
      key: 'node-role.kubernetes.io/master',
      operator: 'Exists',
      effect: 'NoSchedule',
    },
    {
      key: 'node-role.kubernetes.io/control-plane',
      operator: 'Exists',
      effect: 'NoSchedule',
    },
  ],

  commonLabels:: {
    'app.kubernetes.io/name': 'promtail',
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'logging',
    'app.kubernetes.io/part-of': 'loki',
  },

  podLabelSelector:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
};

function(params) {
  local pt = self,

  // Combine the defaults and the passed params to make the component's config.
  config:: defaults + params,
  // Safety checks for combined config of defaults and params
  assert std.isObject(pt.config.resources),
  assert std.isBoolean(pt.config.serviceMonitor),

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    automountServiceAccountToken: false,
    metadata: {
      name: pt.config.name,
      namespace: pt.config.namespace,
      labels: pt.config.commonLabels,
    },
  },

  clusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      name: pt.config.name,
      labels: pt.config.commonLabels,
    },
    rules: [
      {
        apiGroups: [''],
        resources: ['nodes', 'nodes/proxy', 'services', 'endpoints', 'pods',],
        verbs: ['get', 'list', 'watch'],
      },
    ],
  },

  clusterRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      name: pt.config.name,
      labels: pt.config.commonLabels,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: pt.clusterRole.metadata.name,
    },
    subjects: [{
      kind: 'ServiceAccount',
      name: pt.serviceAccount.metadata.name,
      namespace: pt.serviceAccount.metadata.namespace,
    }],
  },

  local promtailConfig = {
    server: {
      http_listen_port: pt.config.ports.http,
    },
    clients: [
      { url: 'http://%(host)s:%(port)d/loki/api/v1/push' % pt.config.loki },
    ],
    positions: {
      filename: '/run/promtail/positions.yaml',
    },
    scrape_configs: import './scrape_configs.libsonnet',
  } + pt.config.config,

  configMap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: pt.config.name,
      namespace: pt.config.namespace,
      labels: pt.config.commonLabels,
    },
    data: {
      'config.yaml': std.manifestYamlDoc(promtailConfig, indent_array_in_object=true, quote_keys=false),
    },
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: pt.config.name,
      namespace: pt.config.namespace,
      labels: pt.config.commonLabels,
    },
    spec: {
      clusterIP: 'None',
      selector: pt.config.podLabelSelector,
      ports: [
        {
          name: name,
          port: pt.config.ports[name],
          protocol: 'TCP',
          targetPort: name,
        }
        for name in std.objectFields(pt.config.ports)
      ],
    },
  },

  daemonSet: {
    apiVersion: 'apps/v1',
    kind: 'DaemonSet',
    metadata: {
      name: pt.config.name,
      namespace: pt.config.namespace,
      labels: pt.config.commonLabels,
      annotations: {
        config_hash: std.md5(std.toString(promtailConfig)),
      },
    },
    spec: {
      selector: { matchLabels: pt.config.podLabelSelector },
      template: {
        metadata: {
          labels: pt.config.commonLabels,
          annotations: { config_hash: std.md5(std.toString(promtailConfig)) },
        },
        spec: {
          serviceAccountName: pt.serviceAccount.metadata.name,
          containers: [
            {
              name: 'promtail',
              image: pt.config.image,
              args: [
                '-config.file=/etc/promtail/config.yaml',
              ] + pt.config.extraArgs,
              env: [{
                name: 'HOSTNAME',
                valueFrom: { fieldRef: { fieldPath: 'spec.nodeName' } },
              }],
              imagePullPolicy: pt.config.imagePullPolicy,
              readinessProbe: {
                initialDelaySeconds: 10,
                periodSeconds: 10,
                successThreshold: 1,
                failureThreshold: 5,
                timeoutSeconds: 1,
                httpGet: {
                  path: '/ready',
                  port: 'http',
                },
              },
              ports: [
                { name: name, containerPort: pt.config.ports[name] }
                for name in std.objectFields(pt.config.ports)
              ],
              resources: pt.config.resources,
              securityContext: pt.config.containerSecurityContext,
              volumeMounts: [
                {
                  name: 'config',
                  mountPath: '/etc/promtail',
                },
                {
                  name: 'run',
                  mountPath: '/run/promtail',
                },
                {
                  name: 'containers',
                  mountPath: '/var/lib/docker/containers',
                  readOnly: true,
                },
                {
                  name: 'pods',
                  mountPath: '/var/log/pods',
                  readOnly: true,
                },
              ],
            },
          ],
          securityContext: pt.config.podSecurityContext,
          tolerations: pt.config.tolerations,
          volumes: [
            {
              name: 'config',
              configMap: { name: pt.configMap.metadata.name },
            },
            {
              name: 'run',
              hostPath: { path: '/run/promtail' },
            },
            {
              name: 'containers',
              hostPath: { path: '/var/lib/docker/containers' },
            },
            {
              name: 'pods',
              hostPath: { path: '/var/log/pods' },
            },
          ],
        },
      },
    },
  },

  serviceMonitor: if pt.config.serviceMonitor == true then {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: {
      name: pt.config.name,
      namespace: pt.config.namespace,
      labels: pt.config.commonLabels,
    },
    spec: {
      selector: {
        matchLabels: pt.config.podLabelSelector,
      },
      endpoints: [{ port: 'http' }],
    },
  },
}
