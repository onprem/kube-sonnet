// These are the defaults for this components configuration.
// When calling the function to generate the component's manifest,
// you can pass an object structured like the default to overwrite default values.
local defaults = {
  local defaults = self,
  name: 'ingress-nginx',
  admName: defaults.name + '-admission',
  controllerName: defaults.name + '-controller',
  ingressClassName: 'nginx',
  controllerClass: 'k8s.io/ingress-nginx',
  electionId: 'ingress-controller-leader',
  serviceAnnotations: {},
  namespace: error 'must provide namespace',
  version: error 'must provide version',
  images: {
    controller: error 'must provide controller image',
    kubeWebhookCertgen: error 'must provide kubeWebhookCertgen image',
  },
  imagePullPolicy: 'IfNotPresent',
  replicas: error 'must provide replicas',
  ports: {
    http: 80,
    https: 443,
    webhook: 8443,
  },
  resources: {
    requests: {
      cpu: '100m',
      memory: '90Mi',
    },
  },
  serviceMonitor: false,

  commonLabels:: {
    'app.kubernetes.io/name': 'ingress-nginx',
    'app.kubernetes.io/instance': defaults.name,
    'app.kubernetes.io/version': defaults.version,
    'app.kubernetes.io/part-of': 'ingress-nginx',
  },

  commonControllerLabels:: defaults.commonLabels + {
    'app.kubernetes.io/component': 'controller',
  },

  podLabelSelector:: {
    [labelName]: defaults.commonControllerLabels[labelName]
    for labelName in std.objectFields(defaults.commonControllerLabels)
    if !std.setMember(labelName, ['app.kubernetes.io/version', 'app.kubernetes.io/part-of'])
  },

  commonAdmWebhookLabels:: defaults.commonLabels + {
    'app.kubernetes.io/component': 'admission-webhook',
  },
};

function(params) {
  local ingnx = self,

  // Combine the defaults and the passed params to make the component's config.
  config:: defaults + params,
  // Safety checks for combined config of defaults and params
  assert std.isNumber(ingnx.config.replicas) && ingnx.config.replicas >= 0 : 'controller replicas has to be number >= 0',
  assert std.isObject(ingnx.config.resources),
  assert std.isObject(ingnx.config.serviceAnnotations),
  assert std.isBoolean(ingnx.config.serviceMonitor),

  controllerServiceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    automountServiceAccountToken: true,
    metadata: {
      name: ingnx.config.name,
      namespace: ingnx.config.namespace,
      labels: ingnx.config.commonControllerLabels,
    },
  },

  admWebhookServiceAccount: {
    apiVersion: 'v1',
    kind: 'ServiceAccount',
    metadata: {
      name: ingnx.config.admName,
      namespace: ingnx.config.namespace,
      labels: ingnx.config.commonAdmWebhookLabels,
    },
  },

  controllerRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'Role',
    metadata: {
      name: ingnx.config.name,
      namespace: ingnx.config.namespace,
      labels: ingnx.config.commonControllerLabels,
    },
    rules: [
      {
        apiGroups: [''],
        resources: ['namespaces'],
        verbs: ['get'],
      },
      {
        apiGroups: [''],
        resources: ['configmaps', 'pods', 'secrets', 'endpoints'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: [''],
        resources: ['services'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: ['networking.k8s.io'],
        resources: ['ingresses'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: ['networking.k8s.io'],
        resources: ['ingresses/status'],
        verbs: ['update'],
      },
      {
        apiGroups: ['networking.k8s.io'],
        resources: ['ingressclasses'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: [''],
        resources: ['configmaps'],
        resourceNames: [ingnx.config.electionId],
        verbs: ['get', 'update'],
      },
      {
        apiGroups: [''],
        resources: ['configmaps'],
        verbs: ['create'],
      },
      {
        apiGroups: [''],
        resources: ['events'],
        verbs: ['create', 'patch'],
      },
    ],
  },

  admWebhookRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'Role',
    metadata: {
      name: ingnx.config.admName,
      namespace: ingnx.config.namespace,
      labels: ingnx.config.commonAdmWebhookLabels,
    },
    rules: [
      {
        apiGroups: [''],
        resources: ['secrets'],
        verbs: ['get', 'create'],
      },
    ],
  },

  controllerClusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      name: ingnx.config.name,
      labels: ingnx.config.commonAdmWebhookLabels,
    },
    rules: [
      {
        apiGroups: [''],
        resources: ['configmaps', 'endpoints', 'nodes', 'pods', 'secrets', 'namespaces'],
        verbs: ['list', 'watch'],
      },
      {
        apiGroups: [''],
        resources: ['nodes'],
        verbs: ['get'],
      },
      {
        apiGroups: [''],
        resources: ['services'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: ['networking.k8s.io'],
        resources: ['ingresses'],
        verbs: ['get', 'list', 'watch'],
      },
      {
        apiGroups: [''],
        resources: ['events'],
        verbs: ['create', 'patch'],
      },
      {
        apiGroups: ['networking.k8s.io'],
        resources: ['ingresses/status'],
        verbs: ['update'],
      },
      {
        apiGroups: ['networking.k8s.io'],
        resources: ['ingressclasses'],
        verbs: ['get', 'list', 'watch'],
      },
    ],
  },

  admWebhookClusterRole: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRole',
    metadata: {
      name: ingnx.config.admName,
      labels: ingnx.config.commonAdmWebhookLabels,
    },
    rules: [
      {
        apiGroups: ['admissionregistration.k8s.io'],
        resources: ['validatingwebhookconfigurations'],
        verbs: ['get', 'update'],
      },
    ],
  },

  controllerRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'RoleBinding',
    metadata: {
      name: ingnx.config.name,
      namespace: ingnx.config.namespace,
      labels: ingnx.config.commonControllerLabels,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'Role',
      name: ingnx.controllerRole.metadata.name,
    },
    subjects: [{
      kind: 'ServiceAccount',
      name: ingnx.controllerServiceAccount.metadata.name,
      namespace: ingnx.controllerServiceAccount.metadata.namespace,
    }],
  },

  admWebhookRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'RoleBinding',
    metadata: {
      name: ingnx.config.admName,
      namespace: ingnx.config.namespace,
      labels: ingnx.config.commonAdmWebhookLabels,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'Role',
      name: ingnx.admWebhookRole.metadata.name,
    },
    subjects: [{
      kind: 'ServiceAccount',
      name: ingnx.admWebhookServiceAccount.metadata.name,
      namespace: ingnx.admWebhookServiceAccount.metadata.namespace,
    }],
  },

  controllerClusterRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      name: ingnx.config.name,
      labels: ingnx.config.commonControllerLabels,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: ingnx.controllerClusterRole.metadata.name,
    },
    subjects: [{
      kind: 'ServiceAccount',
      name: ingnx.controllerServiceAccount.metadata.name,
      namespace: ingnx.controllerServiceAccount.metadata.namespace,
    }],
  },

  admWebhookClusterRoleBinding: {
    apiVersion: 'rbac.authorization.k8s.io/v1',
    kind: 'ClusterRoleBinding',
    metadata: {
      name: ingnx.config.admName,
      labels: ingnx.config.commonAdmWebhookLabels,
    },
    roleRef: {
      apiGroup: 'rbac.authorization.k8s.io',
      kind: 'ClusterRole',
      name: ingnx.admWebhookClusterRole.metadata.name,
    },
    subjects: [{
      kind: 'ServiceAccount',
      name: ingnx.admWebhookServiceAccount.metadata.name,
      namespace: ingnx.admWebhookServiceAccount.metadata.namespace,
    }],
  },

  configMap: {
    apiVersion: 'v1',
    kind: 'ConfigMap',
    metadata: {
      name: ingnx.config.controllerName,
      namespace: ingnx.config.namespace,
      labels: ingnx.config.commonControllerLabels,
    },
    data: {
      'allow-snippet-annotations': 'true',
    },
  },

  service: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: ingnx.config.controllerName,
      namespace: ingnx.config.namespace,
      labels: ingnx.config.commonControllerLabels,
      annotations: ingnx.config.serviceAnnotations,
    },
    spec: {
      externalTrafficPolicy: 'Local',
      selector: ingnx.config.podLabelSelector,
      ports: [
        {
          appProtocol: name,
          name: name,
          port: ingnx.config.ports[name],
          protocol: 'TCP',
          targetPort: name,
        }
        for name in std.objectFields(ingnx.config.ports)
        if !std.setMember(name, ['webhook'])
      ],
      type: 'LoadBalancer',
    },
  },

  webhookService: {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: {
      name: ingnx.config.controllerName + '-admission',
      namespace: ingnx.config.namespace,
      labels: ingnx.config.commonControllerLabels,
    },
    spec: {
      selector: ingnx.config.podLabelSelector,
      ports: [
        {
          appProtocol: 'https',
          name: 'https-webhook',
          port: 443,
          targetPort: 'webhook',
        }
      ],
      type: 'ClusterIP',
    },
  },

  deployment: {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: {
      name: ingnx.config.controllerName,
      namespace: ingnx.config.namespace,
      labels: ingnx.config.commonControllerLabels,
    },
    spec: {
      replicas: ingnx.config.replicas,
      minReadySeconds: 0,
      revisionHistoryLimit: 10,
      selector: { matchLabels: ingnx.config.podLabelSelector },
      strategy: {
        rollingUpdate: {
          maxSurge: 0,
          maxUnavailable: 1,
        },
      },
      template: {
        metadata: { labels: ingnx.config.commonControllerLabels },
        spec: {
          serviceAccountName: ingnx.controllerServiceAccount.metadata.name,
          containers: [
            {
              name: 'controller',
              image: ingnx.config.images.controller,
              args: [
                '/nginx-ingress-controller',
                '--publish-service=$(POD_NAMESPACE)/%s' % ingnx.config.controllerName,
                '--election-id=%s' % ingnx.config.electionId,
                '--controller-class=%s' % ingnx.config.controllerClass,
                '--ingress-class=%s' % ingnx.config.ingressClassName,
                '--configmap=$(POD_NAMESPACE)/%s' % ingnx.configMap.metadata.name,
                '--validating-webhook=:%d' % ingnx.config.ports.webhook,
                '--validating-webhook-certificate=/usr/local/certificates/cert',
                '--validating-webhook-key=/usr/local/certificates/key',
              ],
              env: [
                {
                  name: 'POD_NAME',
                  valueFrom: { fieldRef: { fieldPath: 'metadata.name' }},
                },
                {
                  name: 'POD_NAMESPACE',
                  valueFrom: { fieldRef: { fieldPath: 'metadata.namespace' }},
                },
                {
                  name: 'LD_PRELOAD',
                  value: '/usr/local/lib/libmimalloc.so',
                },
              ],
              imagePullPolicy: ingnx.config.imagePullPolicy,
              lifecycle: {
                prestop: { exec: { command: ['/wait-shutdown'] }},
              },
              livenessProbe: {
                failureThreshold: 5,
                initialDelaySeconds: 10,
                periodSeconds: 10,
                successThreshold: 1,
                timeoutSeconds: 1,
                httpGet: {
                  path: '/healthz',
                  port: 10254,
                  scheme: 'HTTP',
                },
              },
              readinessProbe: {
                failureThreshold: 3,
                initialDelaySeconds: 10,
                periodSeconds: 10,
                successThreshold: 1,
                timeoutSeconds: 1,
                httpGet: {
                  path: '/healthz',
                  port: 10254,
                  scheme: 'HTTP',
                },
              },
              ports: [
                { name: name, containerPort: ingnx.config.ports[name], protocol: 'TCP' }
                for name in std.objectFields(ingnx.config.ports)
              ],
              resources: if ingnx.config.resources != {} then ingnx.config.resources else {},
              securityContext: {
                allowPrivilegeEscalation: true,
                capabilities: {
                  add: ['NET_BIND_SERVICE'],
                  drop: ['ALL'],
                },
                runAsUser: 101,
              },
              volumeMounts: [{
                name: 'webhook-cert',
                mountPath: '/usr/local/certificates/',
                readOnly: true,
              }],
            },
          ],
          dnsPolicy: 'ClusterFirst',
          nodeSelector: {
            'kubernetes.io/os': 'linux',
          },
          terminationGracePeriodSeconds: 300,
          volumes: [{
            name: 'webhook-cert',
            secret: { secretName: ingnx.config.admName },
          }],
        },
      },
    },
  },

  admissionCreateJob: {
    apiVersion: 'batch/v1',
    kind: 'Job',
    metadata: {
      name: ingnx.config.admName + '-create',
      namespace: ingnx.config.namespace,
      labels: ingnx.config.commonAdmWebhookLabels,
    },
    spec: {
      template: {
        metadata: {
          name: ingnx.config.admName + '-create',
          labels: ingnx.config.commonAdmWebhookLabels,
        },
        spec: {
          containers: [
            {
              args: [
                'create',
                '--host=%(svc)s,%(svc)s.$(POD_NAMESPACE).svc' % {svc: ingnx.webhookService.metadata.name},
                '--namespace=$(POD_NAMESPACE)',
                '--secret-name=%s' % ingnx.config.admName,
              ],
              env: [
                {
                  name: 'POD_NAMESPACE',
                  valueFrom: { fieldRef: { fieldPath: 'metadata.namespace' }},
                },
              ],
              image: ingnx.config.images.kubeWebhookCertgen,
              imagePullPolicy: ingnx.config.imagePullPolicy,
              name: 'create',
              securityContext: {
                allowPrivilegeEscalation: false,
              },
            },
          ],
          nodeSelector: {
            'kubernetes.io/os': 'linux',
          },
          restartPolicy: 'OnFailure',
          securityContext: {
            fsGroup: 2000,
            runAsNonRoot: true,
            runAsUser: 2000,
          },
          serviceAccountName: ingnx.admWebhookServiceAccount.metadata.name,
        },
      },
    },
  },

  admissionPatchJob: {
    apiVersion: 'batch/v1',
    kind: 'Job',
    metadata: {
      name: ingnx.config.admName + '-patch',
      namespace: ingnx.config.namespace,
      labels: ingnx.config.commonAdmWebhookLabels,
    },
    spec: {
      template: {
        metadata: {
          name: ingnx.config.admName + '-patch',
          labels: ingnx.config.commonAdmWebhookLabels,
        },
        spec: {
          containers: [
            {
              args: [
                'patch',
                '--webhook-name=%s' % ingnx.config.admName,
                '--namespace=$(POD_NAMESPACE)',
                '--patch-mutating=false',
                '--secret-name=%s' % ingnx.config.admName,
                '--patch-failure-policy=Fail',
              ],
              env: [
                {
                  name: 'POD_NAMESPACE',
                  valueFrom: { fieldRef: { fieldPath: 'metadata.namespace' }},
                },
              ],
              image: ingnx.config.images.kubeWebhookCertgen,
              imagePullPolicy: ingnx.config.imagePullPolicy,
              name: 'patch',
              securityContext: {
                allowPrivilegeEscalation: false,
              },
            },
          ],
          nodeSelector: {
            'kubernetes.io/os': 'linux',
          },
          restartPolicy: 'OnFailure',
          securityContext: {
            fsGroup: 2000,
            runAsNonRoot: true,
            runAsUser: 2000,
          },
          serviceAccountName: ingnx.admWebhookServiceAccount.metadata.name,
        },
      },
    },
  },

  ingressClass: {
    apiVersion: 'networking.k8s.io/v1',
    kind: 'IngressClass',
    metadata: {
      name: ingnx.config.ingressClassName,
      labels: ingnx.config.commonControllerLabels,
    },
    spec: {
      controller: ingnx.config.controllerClass,
    },
  },

  validatingWebhookConfiguration: {
    apiVersion: 'admissionregistration.k8s.io/v1',
    kind: 'ValidatingWebhookConfiguration',
    metadata+: {
      name: ingnx.config.admName,
      labels: ingnx.config.commonAdmWebhookLabels,
    },
    webhooks: [
      {
        admissionReviewVersions: ['v1'],
        clientConfig: {
          service: {
            name: ingnx.webhookService.metadata.name,
            namespace: ingnx.webhookService.metadata.namespace,
            path: '/networking/v1/ingresses',
          },
        },
        failurePolicy: 'Fail',
        matchPolicy: 'Equivalent',
        name: 'validate.nginx.ingress.kubernetes.io',
        rules: [
          {
            apiGroups: ['networking.k8s.io'],
            apiVersions: ['v1'],
            operations: ['CREATE', 'UPDATE'],
            resources: ['ingresses'],
          },
        ],
        sideEffects: 'None',
      },
    ],
  },

  serviceMonitor: if ingnx.config.serviceMonitor == true then {
    apiVersion: 'monitoring.coreos.com/v1',
    kind: 'ServiceMonitor',
    metadata+: {
      name: ingnx.config.controllerName,
      namespace: ingnx.config.namespace,
    },
    spec: {
      selector: {
        matchLabels: ingnx.config.commonLabels,
      },
      endpoints: [{ port: 10254 }],
    },
  },
}
