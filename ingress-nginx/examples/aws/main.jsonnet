local common = import '../common.libsonnet';

local ingnx = (import '../../main.libsonnet')(common + {
  setDefaultIngress: true,
  serviceAnnotations+: {
    'service.beta.kubernetes.io/aws-load-balancer-backend-protocol': 'tcp',
    'service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled': 'true',
    'service.beta.kubernetes.io/aws-load-balancer-type': 'nlb',
  },
});

{
  ['ingress-nginx-' + name]: ingnx[name]
  for name in std.objectFields(ingnx)
  if ingnx[name] != null
}
