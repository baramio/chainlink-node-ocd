
variable "cf_email" {}
variable "cf_tunnel_token" {
  sensitive = true
}
variable "cf_acctid" {}
variable "cf_zoneid" {}


provider "cloudflare" {
  email   = var.cf_email
  api_token = var.cf_tunnel_token
}
provider "random" {}


# setup HTTPS connection to the API/GUI using Cloudflare Tunnel and exposing it to a specified baramio-nodes domain
# https://github.com/cloudflare/argo-tunnel-examples/blob/master/named-tunnel-k8s/cloudflared.yaml
resource "random_id" "cl_tunnel_secret" {
  byte_length = 35
}

resource "cloudflare_argo_tunnel" "cl_tunnel" {
  account_id = var.cf_acctid
  name       = "chainlink-${var.network}-tunnel"
  secret     = random_id.cl_tunnel_secret.b64_std
}

resource "cloudflare_record" "cl_record" {
  zone_id = var.cf_zoneid
  name    = "chainlink-${var.network}"
  value   = "${cloudflare_argo_tunnel.cl_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

resource "kubernetes_secret" "cl-cloudflared-creds" {
  metadata {
    name      = "cloudflared-creds"
    namespace = "chainlink"
  }
  data = {
    "cert.json" = <<EOF
{
    "AccountTag"   : "${var.cf_acctid}",
    "TunnelID"     : "${cloudflare_argo_tunnel.cl_tunnel.id}",
    "TunnelName"   : "${cloudflare_argo_tunnel.cl_tunnel.name}",
    "TunnelSecret" : "${random_id.cl_tunnel_secret.b64_std}"
}
    EOF
  }
}

resource "kubernetes_config_map" "cl-cloudflared-config" {
  metadata {
    name      = "cloudflared-config"
    namespace = "chainlink"
  }
  data = {
    "config.yaml" = <<EOF
tunnel: ${cloudflare_argo_tunnel.cl_tunnel.id}
credentials-file: /etc/cloudflared/creds/cert.json
metrics: 0.0.0.0:2000
no-autoupdate: true

ingress:
  # route API/GUI requests to 6688
  - hostname: "chainlink-${var.network}.baramio-nodes.com"
    service: http://chainlink-node:6688
  # everything else is invalid
  - service: http_status:404
    EOF
  }
}

resource "kubernetes_deployment" "cl-cloudflared" {
  metadata {
    name = "cloudflared"
    namespace = "chainlink"
    labels = {
      app = "cloudflared"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "cloudflared"
      }
    }
    template {
      metadata {
        labels = {
          app = "cloudflared"
        }
      }
      spec {
        container {
          image = "cloudflare/cloudflared:2022.2.0"
          name  = "cloudflared"
          args  = ["tunnel", "--config", "/etc/cloudflared/config.yaml",  "run"]
          volume_mount {
            name       = "cloudflared-config"
            mount_path = "/etc/cloudflared"
            read_only  = true
          }
          volume_mount {
            name       = "cloudflared-creds"
            mount_path = "/etc/cloudflared/creds"
            read_only  = true
          }
          liveness_probe {
            http_get {
              path = "/ready"
              port = 2000
            }
            failure_threshold     = 1
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }
        volume {
          name = "cloudflared-creds"
          secret {
            secret_name = "cloudflared-creds"
          }
        }
        volume {
          name = "cloudflared-config"
          config_map {
            name = "cloudflared-config"
          }
        }
      }
    }
  }
}

resource "random_id" "prometheus_tunnel_secret" {
  byte_length = 35
}

resource "cloudflare_argo_tunnel" "prometheus_tunnel" {
  account_id = var.cf_acctid
  name       = "chainlink-${var.network}-prometheus-tunnel"
  secret     = random_id.prometheus_tunnel_secret.b64_std
}

resource "cloudflare_record" "grafana_record" {
  zone_id = var.cf_zoneid
  name    = "chainlink-${var.network}-grafana"
  value   = "${cloudflare_argo_tunnel.prometheus_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_record" "prometheus_record" {
  zone_id = var.cf_zoneid
  name    = "chainlink-${var.network}-prometheus"
  value   = "${cloudflare_argo_tunnel.prometheus_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

resource "kubernetes_secret" "prometheus-cloudflared-creds" {
  metadata {
    name      = "cloudflared-creds"
    namespace = "kube-prometheus-stack"
  }
  data = {
    "cert.json" = <<EOF
{
    "AccountTag"   : "${var.cf_acctid}",
    "TunnelID"     : "${cloudflare_argo_tunnel.prometheus_tunnel.id}",
    "TunnelName"   : "${cloudflare_argo_tunnel.prometheus_tunnel.name}",
    "TunnelSecret" : "${random_id.prometheus_tunnel_secret.b64_std}"
}
    EOF
  }
}

resource "kubernetes_config_map" "monitoring-cloudflared-config" {
  metadata {
    name      = "cloudflared-config"
    namespace = "kube-prometheus-stack"
  }
  data = {
    "config.yaml" = <<EOF
tunnel: ${cloudflare_argo_tunnel.prometheus_tunnel.id}
credentials-file: /etc/cloudflared/creds/cert.json
metrics: 0.0.0.0:2000
no-autoupdate: true

ingress:
  # route grafana requests to 3000
  - hostname: "chainlink-${var.network}-grafana.baramio-nodes.com"
    service: http://kube-prometheus-stack-grafana:80
  # route grafana requests to 9090
  - hostname: "chainlink-${var.network}-prometheus.baramio-nodes.com"
    service: http://kube-prometheus-stack-prometheus:9090
  # everything else is invalid
  - service: http_status:404
    EOF
  }
}

resource "kubernetes_deployment" "monitoring-cloudflared" {
  metadata {
    name = "cloudflared"
    namespace = "kube-prometheus-stack"
    labels = {
      app = "cloudflared"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "cloudflared"
      }
    }
    template {
      metadata {
        labels = {
          app = "cloudflared"
        }
      }
      spec {
        container {
          image = "cloudflare/cloudflared:2022.2.0"
          name  = "cloudflared"
          args  = ["tunnel", "--config", "/etc/cloudflared/config.yaml",  "run"]
          volume_mount {
            name       = "cloudflared-config"
            mount_path = "/etc/cloudflared"
            read_only  = true
          }
          volume_mount {
            name       = "cloudflared-creds"
            mount_path = "/etc/cloudflared/creds"
            read_only  = true
          }
          liveness_probe {
            http_get {
              path = "/ready"
              port = 2000
            }
            failure_threshold     = 1
            initial_delay_seconds = 10
            period_seconds        = 10
          }
        }
        volume {
          name = "cloudflared-creds"
          secret {
            secret_name = "cloudflared-creds"
          }
        }
        volume {
          name = "cloudflared-config"
          config_map {
            name = "cloudflared-config"
          }
        }
      }
    }
  }
}
