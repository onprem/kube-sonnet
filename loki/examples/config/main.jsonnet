local common = import '../common.libsonnet';

local loki = (import '../../simple-scalable.libsonnet')(common + {
  config: {
    server+: {
      log_level: 'debug',
    },
    common+: {
      storage+: {
        s3+: {
          s3: 's3://loki:supersecret@minio.minio.svc:9000/loki-data'
        },
      },
    },
  },
  storage+: {
    read: '5Gi',
  },
  resources+: {
    requests+: {
      memory: '100Mi',
    },
    limits: {
      cpu: '200m',
      memory: '200Mi',
    },
  },
});

{
  ['loki-' + name]: loki[name]
  for name in std.objectFields(loki)
  if loki[name] != null
}
