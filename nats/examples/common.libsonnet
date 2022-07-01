{
  namespace: 'nats',
  version: '2.8.4',
  images: {
    server: 'nats:2.8.4-alpine',
    reloader: 'natsio/nats-server-config-reloader:0.7.0',
    exporter: 'natsio/prometheus-nats-exporter:0.9.3',
  },
  replicas: 1,
}
