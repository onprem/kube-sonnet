local defaults = {
  local defaults = self,
  name: 'redis-operator',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide redis-operator image',
  imagePullPolicy: 'IfNotPresent',
  replicas: error 'must provide replicas',
  ports: {
    metrics: 9710,
  },
  resources: {
    requests: {
      cpu: '10m',
      memory: '50Mi',
    },
    limits: {
      cpu: '100m',
      memory: '90Mi',
    },
  },
  serviceMonitor: false,

  commonLabels:: {
    'app.kubernetes.io/name': 'redis-operator',
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'controller',
  },

  podLabelSelector:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
};

function(params) {
  local ro = self,

  // Combine the defaults and the passed params to make the component's config.
  config:: defaults + params,
  // Safety checks for combined config of defaults and params
  assert std.isNumber(ro.config.replicas) && ro.config.replicas >= 0 : 'redis-operator replicas has to be number >= 0',
  assert std.isObject(ro.config.resources),
  assert std.isBoolean(ro.config.serviceMonitor),

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: ro.config.name,
      namespace: ro.config.namespace,
      labels: ro.config.commonLabels,
    },
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: ro.config.name,
      namespace: ro.config.namespace,
      labels: ro.config.commonLabels,
    },
    spec: {
      selector: ro.config.podLabelSelector,
      ports: [
        {
          name: name,
          port: ro.config.ports[name],
        }
        for name in std.objectFields(ro.config.ports)
      ],
    },
  },

  deployment: {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: {
      name: ro.config.name,
      namespace: ro.config.namespace,
      labels: ro.config.commonLabels,
    },
    spec: {
      replicas: ro.config.replicas,
      selector: { matchLabels: ro.config.podLabelSelector },
      strategy: {
        rollingUpdate: {
          maxSurge: 0,
          maxUnavailable: 1,
        },
      },
      template: {
        metadata: { labels: ro.config.commonLabels },
        spec: {
          serviceAccountName: ro.serviceAccount.metadata.name,
          restartPolicy: 'Always',
          containers: [
            {
              name: 'controller',
              image: ro.config.image,
              imagePullPolicy: ro.config.imagePullPolicy,
              livenessProbe: {
                initialDelaySeconds: 30,
                periodSeconds: 5,
                timeoutSeconds: 5,
                failureThreshold: 6,
                successThreshold: 1,
                tcpSocket: {
                  port: ro.config.ports.metrics,
                },
              },
              readinessProbe: {
                initialDelaySeconds: 10,
                periodSeconds: 3,
                timeoutSeconds: 3,
                tcpSocket: {
                  port: ro.config.ports.metrics,
                },
              },
              ports: [
                { name: name, containerPort: ro.config.ports[name], protocol: 'TCP' }
                for name in std.objectFields(ro.config.ports)
              ],
              securityContext: {
                readOnlyRootFilesystem: true,
                runAsNonRoot: true,
                runAsUser: 1000,
              },
              resources: if ro.config.resources != {} then ro.config.resources else {},
            },
          ],
        },
      },
    },
  },

  clusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      name: ro.config.name,
      labels: ro.config.commonLabels,
    },
    rules: [
      {
        apiGroups: ['databases.spotahome.com'],
        resources: ['redisfailovers', 'redisfailovers/finalizers'],
        verbs: ['*'],
      },
      {
        apiGroups: ['apiextensions.k8s.io'],
        resources: ['customresourcedefinitions'],
        verbs: ['*'],
      },
      {
        apiGroups: [''],
        resources: ['pods', 'services', 'endpoints', 'events', 'configmaps', 'persistentvolumeclaims', 'persistentvolumeclaims/finalizers'],
        verbs: ['*'],
      },
      {
        apiGroups: [''],
        resources: ['secrets'],
        verbs: ['get'],
      },
      {
        apiGroups: ['apps'],
        resources: ['deployments', 'statefulsets'],
        verbs: ['*'],
      },
      {
        apiGroups: ['policy'],
        resources: ['poddisruptionbudgets'],
        verbs: ['*'],
      },
    ],
  },

  clusterRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      name: ro.config.name,
      labels: ro.config.commonLabels,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: ro.clusterRole.metadata.name,
    },
    subjects: [{
      kind: 'ServiceAccount',
      name: ro.serviceAccount.metadata.name,
      namespace: ro.serviceAccount.metadata.namespace,
    }],
  },

  serviceMonitor: if ro.config.serviceMonitor == true then {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: {
      name: ro.config.name,
      namespace: ro.config.namespace,
    },
    spec: {
      selector: {
        matchLabels: ro.config.podLabelSelector,
      },
      namespaceSelector: {
        matchNames: [ro.config.namespace],
      },
      endpoints: [{ port: 'metrics' }],
    },
  },
}
