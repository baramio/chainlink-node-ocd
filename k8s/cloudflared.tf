
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
resource "random_id" "cl_node_tunnel_secret" {
  byte_length = 35
}

resource "cloudflare_argo_tunnel" "cl_tunnel" {
  account_id = var.cf_acctid
  name       = "chainlink-${var.network}-tunnel"
  secret     = random_id.cl_node_tunnel_secret.b64_std
  depends_on = [random_id.cl_node_tunnel_secret]
}

resource "cloudflare_record" "cl_record" {
  zone_id = var.cf_zoneid
  name    = "chainlink-${var.network}"
  value   = "${cloudflare_argo_tunnel.cl_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  depends_on = [cloudflare_argo_tunnel.cl_tunnel]
}

resource "kubernetes_secret" "cl-cloudflared-creds" {
  metadata {
    name      = "cloudflared-creds"
    namespace = "chainlink-polygon"
  }
  data = {
    "cert.json" = <<EOF
{
    "AccountTag"   : "${var.cf_acctid}",
    "TunnelID"     : "${cloudflare_argo_tunnel.cl_tunnel.id}",
    "TunnelName"   : "${cloudflare_argo_tunnel.cl_tunnel.name}",
    "TunnelSecret" : "${random_id.cl_node_tunnel_secret.b64_std}"
}
    EOF
  }
  depends_on = [kubernetes_namespace.chainlink-polygon, cloudflare_argo_tunnel.cl_tunnel]
}

resource "kubernetes_config_map" "cl-cloudflared-config" {
  metadata {
    name      = "cloudflared-config"
    namespace = "chainlink-polygon"
  }
  data = {
    "config.yaml" = <<EOF
tunnel: ${cloudflare_argo_tunnel.cl_tunnel.id}
credentials-file: /etc/cloudflared/creds/cert.json
metrics: 0.0.0.0:2000
no-autoupdate: true

ingress:
  # route API/GUI requests to 6689
  - hostname: "chainlink-${var.network}.baramio-nodes.com"
    service: http://chainlink-polygon-node:6688
  # everything else is invalid
  - service: http_status:404
    EOF
  }
  depends_on = [kubernetes_namespace.chainlink-polygon, cloudflare_argo_tunnel.cl_tunnel]
}

resource "kubernetes_deployment" "cl-cloudflared" {
  metadata {
    name = "cloudflared"
    namespace = "chainlink-polygon"
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
          image = "cloudflare/cloudflared:2022.3.1"
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
  depends_on = [kubernetes_config_map.cl-cloudflared-config, kubernetes_secret.cl-cloudflared-creds]
}
