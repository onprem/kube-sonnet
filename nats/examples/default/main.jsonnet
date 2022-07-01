local common = import '../common.libsonnet';

local nats = (import '../../main.libsonnet')(common);

{
  ['nats-' + name]: nats[name]
  for name in std.objectFields(nats)
  if nats[name] != null
}
