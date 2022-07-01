local defaults = {
  local defaults = self,
  name: 'nats',
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  images: {
    server: error 'must provide nats server image',
    reloader: error 'must provide nats config reloader image',
    exporter: error 'must provide nats prometheus exporter image',
  },
  imagePullPolicy: 'IfNotPresent',
  replicas: error 'must provide replicas',
  ports: {
    client: 4222,
    cluster: 6222,
    monitor: 8222,
    leafnodes: 7422,
    metrics: 7222,
  },
  resources: {
    requests: {
      cpu: '100m',
      memory: '90Mi',
    },
  },
  serviceMonitor: false,

  commonLabels:: {
    'app.kubernetes.io/name': 'nats',
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/component': 'message-queue',
  },

  podLabelSelector:: {
    [labelName]: defaults.commonLabels[labelName]
    for labelName in std.objectFields(defaults.commonLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version'])
  },
};

function(params) {
  local nats = self,

  // Combine the defaults and the passed params to make the component's config.
  config:: defaults + params,
  // Safety checks for combined config of defaults and params
  assert std.isNumber(nats.config.replicas) && nats.config.replicas >= 0 : 'nats replicas has to be number >= 0',
  assert std.isObject(nats.config.resources),
  assert std.isBoolean(nats.config.serviceMonitor),

  serviceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: nats.config.name,
      namespace: nats.config.namespace,
      labels: nats.config.commonLabels,
    },
  },

  configMap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: nats.config.name,
      namespace: nats.config.namespace,
      labels: nats.config.commonLabels,
    },
    data: {
      'nats.conf': |||
        pid_file: "/var/run/nats/nats.pid"

        http: %(http_port)d

        cluster: {
          port: %(cluster_port)d

          routes: [ %(routes)s ],

          cluster_advertise: $CLUSTER_ADVERTISE
          connect_retries: 30
        }

        leafnodes {
          port: %(leafnodes_port)d
        }
      ||| % {
        http_port: nats.config.ports.monitor,
        cluster_port: nats.config.ports.cluster,
        leafnodes_port: nats.config.ports.leafnodes,
        routes: std.join(' ', [
          'nats://%(name)s-%(replica)d.%(name)s.%(namespace)s.svc:%(port)d' % {
            name: nats.config.name,
            replica: x,
            namespace: nats.config.namespace,
            port: nats.config.ports.cluster,
          },
          for x in std.range(0, nats.config.replicas - 1)
        ])
      },
    },
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: nats.config.name,
      namespace: nats.config.namespace,
      labels: nats.config.commonLabels,
    },
    spec: {
      selector: nats.config.podLabelSelector,
      clusterIP: 'None',
      ports: [
        {
          name: name,
          port: nats.config.ports[name],
        }
        for name in std.objectFields(nats.config.ports)
      ],
    },
  },

  statefulSet: {
    apiVersion: 'apps/v1',
    kind: 'StatefulSet',
    metadata: {
      name: nats.config.name,
      namespace: nats.config.namespace,
      labels: nats.config.commonLabels,
    },
    spec: {
      replicas: nats.config.replicas,
      selector: { matchLabels: nats.config.podLabelSelector },
      serviceName: nats.service.metadata.name,
      template: {
        metadata: { labels: nats.config.commonLabels },
        spec: {
          serviceAccountName: nats.serviceAccount.metadata.name,
          shareProcessNamespace: true,
          terminationGracePeriodSeconds: 60,
          containers: [
            {
              name: 'nats',
              image: nats.config.images.server,
              command: [
                'nats-server',
                '--config',
                '/etc/nats-config/nats.conf',
              ],
              env: [
                {
                  name: 'POD_NAME',
                  valueFrom: { fieldRef: { fieldPath: 'metadata.name' } },
                },
                {
                  name: 'POD_NAMESPACE',
                  valueFrom: { fieldRef: { fieldPath: 'metadata.namespace' } },
                },
                {
                  name: 'CLUSTER_ADVERTISE',
                  value: '$(POD_NAME).nats.$(POD_NAMESPACE).svc',
                },
              ],
              imagePullPolicy: nats.config.imagePullPolicy,
              lifecycle: {
                preStop: { exec: { command: ['/bin/sh', '-c', '/nats-server -sl=ldm=/var/run/nats/nats.pid && /bin/sleep 60'] } },
              },
              livenessProbe: {
                initialDelaySeconds: 10,
                timeoutSeconds: 5,
                httpGet: {
                  path: '/',
                  port: nats.config.ports.monitor,
                },
              },
              readinessProbe: {
                initialDelaySeconds: 10,
                timeoutSeconds: 5,
                httpGet: {
                  path: '/',
                  port: nats.config.ports.monitor,
                },
              },
              ports: [
                { name: name, containerPort: nats.config.ports[name] }
                for name in std.objectFields(nats.config.ports)
                if !std.setMember(name, ['metrics'])
              ],
              resources: if nats.config.resources != {} then nats.config.resources else {},
              volumeMounts: [
                {
                  name: 'config-volume',
                  mountPath: '/etc/nats-config',
                },
                {
                  name: 'pid',
                  mountPath: '/var/run/nats'
                },
              ],
            },
            {
              name: 'reloader',
              image: nats.config.images.reloader,
              command: [
                'nats-server-config-reloader',
                '-pid',
                '/var/run/nats/nats.pid',
                '-config',
                '/etc/nats-config/nats.conf'
              ],
              imagePullPolicy: nats.config.imagePullPolicy,
              volumeMounts: [
                {
                  name: 'config-volume',
                  mountPath: '/etc/nats-config',
                },
                {
                  name: 'pid',
                  mountPath: '/var/run/nats'
                },
              ],
            },
            {
              name: 'metrics',
              image: nats.config.images.exporter,
              args: [
                '-connz',
                '-routz',
                '-subz',
                '-varz',
                '-prefix=nats',
                '-use_internal_server_id',
                '-DV',
                'http://localhost:%d/' % nats.config.ports.monitor,
              ],
              ports: [{
                name: 'metrics',
                containerPort: nats.config.ports.metrics,
              }],
              imagePullPolicy: nats.config.imagePullPolicy,
            },
          ],
          volumes: [
            {
              name: 'config-volume',
              configMap: { name: nats.configMap.metadata.name },
            },
            {
              name: 'pid',
              emptyDir: {},
            },
          ],
        },
      },
    },
  },

  serviceMonitor: if nats.config.serviceMonitor == true then {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: {
      name: nats.config.name,
      namespace: nats.config.namespace,
    },
    spec: {
      selector: {
        matchLabels: nats.config.commonLabels,
      },
      endpoints: [{ port: 'monitor' }],
    },
  },
}
