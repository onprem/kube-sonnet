{
  namespace: 'ingress-nginx',
  version: '1.2.1',
  images: {
    controller: 'registry.k8s.io/ingress-nginx/controller:v1.2.1@sha256:5516d103a9c2ecc4f026efbd4b40662ce22dc1f824fb129ed121460aaa5c47f8',
    kubeWebhookCertgen: 'registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.1.1@sha256:64d8c73dca984af206adf9d6d7e46aa550362b1d7a01f3a0a91b20cc67868660',
  },
  replicas: 1,
}
