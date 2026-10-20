# Copyright 2026 Canonical Ltd.
# See LICENSE file for licensing details.

resource "kubernetes_daemon_set_v1" "node_settings" {
  metadata {
    name      = "os-node-settings-${var.opensearch_model}"
    namespace = "kube-system"
  }

  spec {
    selector {
      match_labels = { app = "os-node-settings-${var.opensearch_model}" }
    }

    template {
      metadata {
        labels = { app = "os-node-settings-${var.opensearch_model}" }
      }

      spec {
        node_selector = { "kubernetes.io/os" = "linux" }

        init_container {
          name    = "sysctl"
          image   = "busybox:1.36"
          command = ["sh", "-c", "sysctl -w vm.swappiness=0 && { [ $(sysctl -n vm.max_map_count) -ge 262144 ] || sysctl -w vm.max_map_count=262144; }"]

          security_context {
            privileged = true
          }
        }

        container {
          name  = "pause"
          image = "registry.k8s.io/pause:3.10"
        }
      }
    }
  }
}
