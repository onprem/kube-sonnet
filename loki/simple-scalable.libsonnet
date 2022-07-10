local defaults = {
  local defaults = self,
  name: 'loki',
  readName: defaults.name + '-read',
  writeName: defaults.name + '-write',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  image: error 'must provide loki image',
  imagePullPolicy: 'IfNotPresent',
  replicas: {
    read: error 'must provide read replicas',
    write: error 'must provide write replicas',
  },
  ports: {
    http: 3100,
    grpc: 9095,
    memberlist: 7946,
  },
  config: {},
  resources: {
    requests: {
      cpu: '100m',
      memory: '90Mi',
    },
  },
  storage: {
    read: '10Gi',
    write: '10Gi',
  },
  extraArgs: {
    read: [],
    write: [],
  },
  serviceMonitor: false,

  podSecurityContext: {
    fsGroup: 10001,
    runAsGroup: 10001,
    runAsNonRoot: true,
    runAsUser: 10001,
  },

  containerSecurityContext: {
    readOnlyRootFilesystem: true,
    capabilities: {
      drop: ['ALL'],
    },
    allowPrivilegeEscalation: false,
  },

  commonLabels:: {
    'app.kubernetes.io/name': 'loki',
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'logging',
    'app.kubernetes.io/part-of': 'loki',
  },

  commonReadLabels:: defaults.commonLabels {
    'app.kubernetes.io/name': defaults.readName,
  },

  commonWriteLabels:: defaults.commonLabels {
    'app.kubernetes.io/name': defaults.writeName,
  },

  readPodLabelSelector:: {
    [labelName]: defaults.commonReadLabels[labelName]
    for labelName in std.objectFields(defaults.commonReadLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },

  writePodLabelSelector:: {
    [labelName]: defaults.commonWriteLabels[labelName]
    for labelName in std.objectFields(defaults.commonWriteLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },

  podLabelSelector:: {
    [labelName]: defaults.readPodLabelSelector[labelName]
    for labelName in std.objectFields(defaults.readPodLabelSelector)
    if !std.setMember(labelName, ['app.kubernetes.io/name'])
  },
};

function(params) {
  local loki = self,

  // Combine the defaults and the passed params to make the component's config.
  config:: defaults + params,
  // Safety checks for combined config of defaults and params
  assert std.isNumber(loki.config.replicas.read) && loki.config.replicas.read >= 0 : 'read replicas has to be number >= 0',
  assert std.isNumber(loki.config.replicas.write) && loki.config.replicas.write >= 0 : 'write replicas has to be number >= 0',
  assert std.isObject(loki.config.resources),
  assert std.isBoolean(loki.config.serviceMonitor),

  readServiceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    automountServiceAccountToken: false,
    metadata: {
      name: loki.config.readName,
      namespace: loki.config.namespace,
      labels: loki.config.commonReadLabels,
    },
  },

  writeServiceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    automountServiceAccountToken: false,
    metadata: {
      name: loki.config.writeName,
      namespace: loki.config.namespace,
      labels: loki.config.commonWriteLabels,
    },
  },

  local lokiConfig = {
    auth_enabled: false,
    server: {
      http_listen_port: loki.config.ports.http,
      grpc_listen_port: loki.config.ports.grpc,
    },
    memberlist: {
      join_members: [
        '%s.%s.svc.cluster.local:%d' % [loki.memberlistService.metadata.name, loki.config.namespace, loki.config.ports.memberlist],
      ],
      bind_port: loki.config.ports.memberlist,
    },
    common: {
      path_prefix: '/data/loki',
      replication_factor: 1,
      storage: {
        s3: {
          s3: 'inmemory:///',
          s3forcepathstyle: true,
        },
      },
    },
    limits_config: {
      enforce_metric_name: false,
      reject_old_samples_max_age: '168h',  // 1 week.
      max_global_streams_per_user: 60000,
      ingestion_rate_mb: 75,
      ingestion_burst_size_mb: 100,
    },
    schema_config: {
      configs: [{
        from: '2021-09-12',
        store: 'boltdb-shipper',
        object_store: 's3',
        schema: 'v12',
        index: {
          prefix: '%s_index_' % loki.config.namespace,
          period: '24h',
        },
      }],
    },
  } + loki.config.config,

  configMap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: loki.config.name,
      namespace: loki.config.namespace,
      labels: loki.config.commonLabels,
    },
    data: {
      'config.yaml': std.manifestYamlDoc(lokiConfig, indent_array_in_object=true, quote_keys=false),
    },
  },

  memberlistService: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: loki.config.name + '-memberlist',
      namespace: loki.config.namespace,
      labels: loki.config.commonLabels,
    },
    spec: {
      clusterIP: 'None',
      publishNotReadyAddresses: true,
      selector: loki.config.podLabelSelector,
      ports: [
        {
          name: 'memberlist',
          port: loki.config.ports.memberlist,
          protocol: 'TCP',
          targetPort: 'memberlist',
        },
      ],
    },
  },

  readService: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: loki.config.readName,
      namespace: loki.config.namespace,
      labels: loki.config.commonReadLabels,
    },
    spec: {
      type: 'ClusterIP',
      selector: loki.config.readPodLabelSelector,
      ports: [
        {
          name: name,
          port: loki.config.ports[name],
          protocol: 'TCP',
          targetPort: name,
        }
        for name in std.objectFields(loki.config.ports)
      ],
    },
  },

  readStatefulSet: {
    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: {
      name: loki.config.readName,
      namespace: loki.config.namespace,
      labels: loki.config.commonReadLabels,
      annotations: {
        config_hash: std.md5(std.toString(lokiConfig)),
      },
    },
    spec: {
      replicas: loki.config.replicas.read,
      selector: { matchLabels: loki.config.readPodLabelSelector },
      serviceName: loki.readService.metadata.name,
      podManagementPolicy: 'Parallel',
      persistentVolumeClaimRetentionPolicy: {
        whenDeleted: 'Delete',
        whenScaled: 'Delete',
      },
      template: {
        metadata: {
          labels: loki.config.commonReadLabels,
          annotations: { config_hash: std.md5(std.toString(lokiConfig)) },
        },
        spec: {
          serviceAccountName: loki.readServiceAccount.metadata.name,
          terminationGracePeriodSeconds: 4800,
          containers: [
            {
              name: 'read',
              image: loki.config.image,
              args: [
                '-target=read',
                '-config.file=/etc/loki/config.yaml',
              ] + loki.config.extraArgs.read,
              imagePullPolicy: loki.config.imagePullPolicy,
              readinessProbe: {
                initialDelaySeconds: 15,
                timeoutSeconds: 1,
                httpGet: {
                  path: '/ready',
                  port: loki.config.ports.http,
                },
              },
              ports: [
                { name: name, containerPort: loki.config.ports[name] }
                for name in std.objectFields(loki.config.ports)
              ],
              resources: loki.config.resources,
              securityContext: loki.config.containerSecurityContext,
              volumeMounts: [
                {
                  name: loki.config.readName,
                  mountPath: '/data',
                },
                {
                  name: 'config',
                  mountPath: '/etc/loki',
                },
              ],
            },
          ],
          securityContext: loki.config.podSecurityContext,
          volumes: [
            {
              name: 'config',
              configMap: { name: loki.configMap.metadata.name },
            },
          ],
        },
      },
      volumeClaimTemplates: [{
        metadata: {
          name: loki.config.readName,
          namespace: loki.config.namespace,
          labels: loki.config.commonReadLabels,
        },
        spec: {
          accessModes: ['ReadWriteOnce'],
          resources: {
            requests: {
              storage: loki.config.storage.read,
            },
          },
        },
      }],
    },
  },

  writeService: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: loki.config.writeName,
      namespace: loki.config.namespace,
      labels: loki.config.commonWriteLabels,
    },
    spec: {
      type: 'ClusterIP',
      selector: loki.config.writePodLabelSelector,
      ports: [
        {
          name: name,
          port: loki.config.ports[name],
          protocol: 'TCP',
          targetPort: name,
        }
        for name in std.objectFields(loki.config.ports)
      ],
    },
  },

  writeStatefulSet: {
    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: {
      name: loki.config.writeName,
      namespace: loki.config.namespace,
      labels: loki.config.commonWriteLabels,
      annotations: {
        config_hash: std.md5(std.toString(lokiConfig)),
      },
    },
    spec: {
      replicas: loki.config.replicas.write,
      selector: { matchLabels: loki.config.writePodLabelSelector },
      serviceName: loki.writeService.metadata.name,
      podManagementPolicy: 'Parallel',
      template: {
        metadata: {
          labels: loki.config.commonWriteLabels,
          annotations: { config_hash: std.md5(std.toString(lokiConfig)) },
        },
        spec: {
          serviceAccountName: loki.writeServiceAccount.metadata.name,
          terminationGracePeriodSeconds: 4800,
          containers: [
            {
              name: 'write',
              image: loki.config.image,
              args: [
                '-target=write',
                '-config.file=/etc/loki/config.yaml',
              ] + loki.config.extraArgs.write,
              imagePullPolicy: loki.config.imagePullPolicy,
              readinessProbe: {
                initialDelaySeconds: 15,
                timeoutSeconds: 1,
                httpGet: {
                  path: '/ready',
                  port: loki.config.ports.http,
                },
              },
              ports: [
                { name: name, containerPort: loki.config.ports[name] }
                for name in std.objectFields(loki.config.ports)
              ],
              resources: loki.config.resources,
              securityContext: loki.config.containerSecurityContext,
              volumeMounts: [
                {
                  name: loki.config.writeName,
                  mountPath: '/data',
                },
                {
                  name: 'config',
                  mountPath: '/etc/loki',
                },
              ],
            },
          ],
          securityContext: loki.config.podSecurityContext,
          volumes: [
            {
              name: 'config',
              configMap: { name: loki.configMap.metadata.name },
            },
          ],
        },
      },
      volumeClaimTemplates: [{
        metadata: {
          name: loki.config.writeName,
          namespace: loki.config.namespace,
          labels: loki.config.commonWriteLabels,
        },
        spec: {
          accessModes: ['ReadWriteOnce'],
          resources: {
            requests: {
              storage: loki.config.storage.write,
            },
          },
        },
      }],
    },
  },

  readServiceMonitor: if loki.config.serviceMonitor == true then {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: {
      name: loki.config.readName,
      namespace: loki.config.namespace,
      labels: loki.config.commonReadLabels,
    },
    spec: {
      selector: {
        matchLabels: loki.config.readPodLabelSelector,
      },
      endpoints: [{ port: 'http' }],
    },
  },

  writeServiceMonitor: if loki.config.serviceMonitor == true then {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: {
      name: loki.config.writeName,
      namespace: loki.config.namespace,
      labels: loki.config.commonWriteLabels,
    },
    spec: {
      selector: {
        matchLabels: loki.config.writePodLabelSelector,
      },
      endpoints: [{ port: 'http' }],
    },
  },
}
