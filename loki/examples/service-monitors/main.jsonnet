local common = import '../common.libsonnet';

local loki = (import '../../simple-scalable.libsonnet')(common + {
  serviceMonitor: true,
});

{
  ['loki-' + name]: loki[name]
  for name in std.objectFields(loki)
  if loki[name] != null
}
