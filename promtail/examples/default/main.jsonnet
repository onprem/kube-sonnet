local common = import '../common.libsonnet';

local promtail = (import '../../main.libsonnet')(common);

{
  ['promtail-' + name]: promtail[name]
  for name in std.objectFields(promtail)
  if promtail[name] != null
}
