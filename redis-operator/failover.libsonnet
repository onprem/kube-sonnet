local defaults = {
  local defaults = self,
  name: 'redis',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  images: {
    redis: error 'must provide redis image',
    redisExporter: error 'must provide redis_exporter image',
  },
  imagePullPolicy: 'IfNotPresent',
  customConfig: {
    redis: [],
    sentinel: [],
  },
  replicas: {
    redis: error 'must provide redis replicas',
    sentinel: error 'must provide sentinel replicas',
  },
  ports: {
    metrics: 9121,
  },
  resources: {
    redis: {
      requests: {
      cpu: '100m',
      memory: '100Mi',
    },
    limits: {
      cpu: '400m',
      memory: '500Mi',
    },
    },
    sentinel: {
      requests: {
      cpu: '50m',
      memory: '50Mi',
    },
    limits: {
      cpu: '100m',
      memory: '100Mi',
    },
    },
  },
  serviceMonitor: false,

  commonLabels:: {
    'app.kubernetes.io/name': 'redis',
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'kv-store',
  },

  podLabelSelector:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
};

function(params) {
  local rf = self,

  // Combine the defaults and the passed params to make the component's config.
  config:: defaults + params,
  // Safety checks for combined config of defaults and params
  assert std.isNumber(rf.config.replicas.redis) && rf.config.replicas.redis >= 0 : 'redis replicas has to be number >= 0',
  assert std.isNumber(rf.config.replicas.sentinel) && rf.config.replicas.sentinel >= 0 : 'sentinel replicas has to be number >= 0',
  assert std.isObject(rf.config.resources),
  assert std.isBoolean(rf.config.serviceMonitor),

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: rf.config.name,
      namespace: rf.config.namespace,
      labels: rf.config.commonLabels,
    },
  },

  redisFailover: {
    apiVersion: 'databases.spotahome.com/v1',
    kind: 'RedisFailover',
    metadata: {
      name: rf.config.name,
      namespace: rf.config.namespace,
      labels: rf.config.commonLabels,
    },
    spec: {
      sentinel: {
        replicas: rf.config.replicas.sentinel,
        image: rf.config.images.redis,
        imagePullPolicy: rf.config.imagePullPolicy,
        customConfig: if std.length(rf.config.customConfig.sentinel) > 0
          then rf.config.customConfig.sentinel,
        resources: if rf.config.resources.sentinel != {} then rf.config.resources.sentinel else {},
      },
      redis: {
        replicas: rf.config.replicas.redis,
        image: rf.config.images.redis,
        imagePullPolicy: rf.config.imagePullPolicy,
        customConfig: if std.length(rf.config.customConfig.redis) > 0
          then rf.config.customConfig.redis,
        resources: if rf.config.resources.redis != {} then rf.config.resources.redis else {},
        exporter: {
          enabled: rf.config.serviceMonitor,
          image: rf.config.images.redisExporter,
          args: [
            '--web.listen-address',
            '0.0.0.0:%d' % rf.config.ports.metrics,
            '--log-format',
            'json',
            ]
        },
      },
    },
  },

  serviceMonitor: if rf.config.serviceMonitor == true then {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: {
      name: rf.config.name,
      namespace: rf.config.namespace,
    },
    spec: {
      selector: {
        matchLabels: rf.config.podLabelSelector,
      },
      namespaceSelector: {
        matchNames: [rf.config.namespace],
      },
      endpoints: [{ port: rf.config.ports.metrics }],
    },
  },
}
