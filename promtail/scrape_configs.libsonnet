# See also https://github.com/grafana/loki/blob/main/production/ksonnet/promtail/scrape_config.libsonnet for reference.

local gen_scrape_config(job_name, pod_uid) = {
  job_name: job_name,
  pipeline_stages: [{ cri: {} }],
  kubernetes_sd_configs: [{
    role: 'pod',
  }],

  relabel_configs: self.prelabel_config + [
    {
      source_labels: ['__meta_kubernetes_pod_node_name'],
      target_label: '__host__',
    },
    {
      source_labels: ['__service__'],
      action: 'drop',
      regex: '',
    },
    {
      action: 'labelmap',
      regex: '__meta_kubernetes_pod_label_(.+)',
    },
    {
      source_labels: ['__meta_kubernetes_namespace', '__service__'],
      action: 'replace',
      separator: '/',
      target_label: 'job',
      replacement: '$1',
    },
    {
      source_labels: ['__meta_kubernetes_namespace'],
      action: 'replace',
      target_label: 'namespace',
    },
    {
      source_labels: ['__meta_kubernetes_pod_name'],
      action: 'replace',
      target_label: 'pod',
    },
    {
      source_labels: ['__meta_kubernetes_pod_container_name'],
      action: 'replace',
      target_label: 'container',
    },
    {
      source_labels: [pod_uid, '__meta_kubernetes_pod_container_name'],
      target_label: '__path__',
      separator: '/',
      replacement: '/var/log/pods/*$1/*.log',
    },
  ],
};

[
  gen_scrape_config('kubernetes-pods-name', '__meta_kubernetes_pod_uid') {
    prelabel_config:: [
      {
        source_labels: ['__meta_kubernetes_pod_label_app_kubernetes_io_name', '__meta_kubernetes_pod_label_name'],
        target_label: '__service__',
      },
    ],
  },
  gen_scrape_config('kubernetes-pods-app', '__meta_kubernetes_pod_uid') {
    prelabel_config:: [
      {
        source_labels: ['__meta_kubernetes_pod_label_app_kubernetes_io_name', '__meta_kubernetes_pod_label_name'],
        action: 'drop',
        regex: '.+',
      },
      {
        source_labels: ['__meta_kubernetes_pod_label_app'],
        target_label: '__service__',
      },
    ],
  },
  gen_scrape_config('kubernetes-pods-direct-controllers', '__meta_kubernetes_pod_uid') {
    prelabel_config:: [
      {
        source_labels: ['__meta_kubernetes_pod_label_app_kubernetes_io_name', '__meta_kubernetes_pod_label_name', '__meta_kubernetes_pod_label_app'],
        separator: '',
        action: 'drop',
        regex: '.+',
      },
      {
        source_labels: ['__meta_kubernetes_pod_controller_name'],
        action: 'drop',
        regex: '[0-9a-z-.]+-[0-9a-f]{8,10}',
      },
      {
        source_labels: ['__meta_kubernetes_pod_controller_name'],
        target_label: '__service__',
      },
    ],
  },
  gen_scrape_config('kubernetes-pods-indirect-controller', '__meta_kubernetes_pod_uid') {
    prelabel_config:: [
      {
        source_labels: ['__meta_kubernetes_pod_label_app_kubernetes_io_name', '__meta_kubernetes_pod_label_name', '__meta_kubernetes_pod_label_app'],
        separator: '',
        action: 'drop',
        regex: '.+',
      },
      {
        source_labels: ['__meta_kubernetes_pod_controller_name'],
        regex: '[0-9a-z-.]+-[0-9a-f]{8,10}',
        action: 'keep',
      },
      {
        source_labels: ['__meta_kubernetes_pod_controller_name'],
        action: 'replace',
        regex: '([0-9a-z-.]+)-[0-9a-f]{8,10}',
        target_label: '__service__',
      },
    ],
  },
  gen_scrape_config('kubernetes-pods-static', '__meta_kubernetes_pod_annotation_kubernetes_io_config_mirror') {
    prelabel_config:: [
      {
        action: 'drop',
        source_labels: ['__meta_kubernetes_pod_annotation_kubernetes_io_config_mirror'],
        regex: '',
      },
      {
        action: 'replace',
        source_labels: ['__meta_kubernetes_pod_label_component'],
        target_label: '__service__',
      },
    ],
  },
]
