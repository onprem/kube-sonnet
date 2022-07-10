{
  namespace: 'logging',
  version: '2.6.0',
  image: 'grafana/loki:2.6.0',
  replicas: {
    read: 1,
    write: 1,
  },
}
