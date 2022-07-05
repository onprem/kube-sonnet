local common = import '../common.libsonnet';

local ro = (import '../../main.libsonnet')(common + {
  serviceMonitor: true,
});

{
  ['redis-operator-' + name]: ro[name]
  for name in std.objectFields(ro)
  if ro[name] != null
}
