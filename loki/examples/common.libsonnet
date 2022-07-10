{
  namespace: 'logging',
  version: '2.7.0',
  image: 'grafana/loki:2.7.0',
  replicas: {
    read: 1,
    write: 1,
  },
}
