local common = import '../common.libsonnet';

local ingnx = (import '../../main.libsonnet')(common);

{
  ['ingress-nginx-' + name]: ingnx[name]
  for name in std.objectFields(ingnx)
  if ingnx[name] != null
}
