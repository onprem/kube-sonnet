local common = import '../common.libsonnet';

local ingnx = (import '../../main.libsonnet')(common + {
  tcpServices: {
    '9000': {
      name: 'example-go',
      namespace: 'default',
      port: 8080,
    },
  },
});

{
  ['ingress-nginx-' + name]: ingnx[name]
  for name in std.objectFields(ingnx)
  if ingnx[name] != null
}
