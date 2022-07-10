{
  namespace: 'logging',
  version: '2.6.0',
  image: 'grafana/promtail:2.6.0',
  loki: {
    host: 'loki-write.logging.svc',
    port: 3100,
  },
}
