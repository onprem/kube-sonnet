local common = import '../common.libsonnet';

local ro = (import '../../main.libsonnet')(common);

local rf = (import '../../failover.libsonnet')({
  namespace: 'redis',
  images: {
    redis: 'redis:7.0.2-alpine',
    redisExporter: 'quay.io/oliver006/redis_exporter:v1.43.0-alpine',
  },
  version: '7.0.2',
  replicas: {
    redis: 3,
    sentinel: 3,
  },
  serviceMonitor: true,
});

{
  ['redis-operator-' + name]: ro[name]
  for name in std.objectFields(ro)
  if ro[name] != null
} +
{
  ['redis-failover-' + name]: rf[name]
  for name in std.objectFields(rf)
  if rf[name] != null
}
