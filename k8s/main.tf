terraform {
  cloud {
    organization = "BARAMIO"

    workspaces {
      name = "chainlink-node-ocd--k8s"
    }
  }
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      version = "~> 3.0"
    }
    random = {
      source = "hashicorp/random"
      version = ">= 0.13"
    }
  }
}

variable "network" {}
variable "backup_eth_url" {}
variable "api_user" {}
variable "api_pw" {}
variable "wallet_pw" {}
variable "database_url" {}
variable "chainlink_version" {
  default     = "1.1.0"
  description = "chainlink node client version"
}
variable "cf_email" {}
variable "cf_tunnel_token" {}
variable "cf_acctid" {}
variable "cf_zoneid" {}

provider "kubernetes" {
  config_path    = "baramio-kubeconfig.yaml"
}
provider "cloudflare" {
  email   = var.cf_email
  api_token = var.cf_tunnel_token
}
provider "random" {}


resource "kubernetes_namespace" "chainlink" {
  metadata {
    name = "chainlink"
  }
}

resource "kubernetes_config_map" "chainlink-env" {
  metadata {
    name      = "chainlink-env"
    namespace = "chainlink"
  }

  data = {
    ROOT = "/chainlink"
    LOG_LEVEL = "debug"
    ETH_CHAIN_ID = 4
    CHAINLINK_TLS_PORT = 0
    SECURE_COOKIES = false
    ALLOW_ORIGINS = "*"
    ETH_URL = "wss://${var.network}-ec-ws.baramio-nodes.com"
    ETH_HTTP_URL = "https://${var.network}-ec-rpc.baramio-nodes.com"
    ETH_SECONDARY_URLS = var.backup_eth_url
    DATABASE_URL = var.database_url
#    MIN_OUTGOING_CONFIRMATIONS = 2
#    LINK_CONTRACT_ADDRESS = "0x20fe562d797a42dcb3399062ae9546cd06f63280"
#    CHAINLINK_TLS_PORT = 0
#    ORACLE_CONTRACT_ADDRESS = "0x9f37f5f695cc16bebb1b227502809ad0fb117e08"
#    MINIMUM_CONTRACT_PAYMENT = 100
#    DATABASE_TIMEOUT = 0
  }
}

resource "kubernetes_secret" "api-credentials" {
  metadata {
    name      = "api-credentials"
    namespace = "chainlink"
  }
  data = {
    api = format("%s\n%s",var.api_user, var.api_pw)
  }
}

resource "kubernetes_secret" "password-credentials" {
  metadata {
    name      = "password-credentials"
    namespace = "chainlink"
  }
  data = {
    password = var.wallet_pw
  }
}

resource "kubernetes_deployment" "chainlink-node" {
  metadata {
    name = "chainlink"
    namespace = "chainlink"
    labels = {
      app = "chainlink-node"
    }
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "chainlink-node"
      }
    }
    template {
      metadata {
        labels = {
          app = "chainlink-node"
        }
      }
      spec {
        container {
          image = "smartcontract/chainlink:${var.chainlink_version}"
          name  = "chainlink-node"
          port {
            container_port = 6688
          }
          args = ["local", "n", "-p",  "/chainlink/.password", "-a", "/chainlink/.api"]
          env_from {
            config_map_ref {
              name = "chainlink-env"
            }
          }
          volume_mount {
            name        = "api-volume"
            sub_path    = "api"
            mount_path  = "/chainlink/.api"
          }
          volume_mount {
            name        = "password-volume"
            sub_path    = "password"
            mount_path  = "/chainlink/.password"
          }
        }
        volume {
          name = "api-volume"
          secret {
            secret_name = "api-credentials"
          }
        }
        volume {
          name = "password-volume"
          secret {
            secret_name = "password-credentials"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "chainlink_service" {
  metadata {
    name = "chainlink-node"
    namespace = "chainlink"
  }
  spec {
    selector = {
      app = "chainlink-node"
    }
    type = "NodePort"
    port {
      port = 6688
    }
  }
}

# setup HTTPS connection to the API/GUI using Cloudflare Tunnel and exposing it to a specified baramio-nodes domain
# https://github.com/cloudflare/argo-tunnel-examples/blob/master/named-tunnel-k8s/cloudflared.yaml
# The random_id resource is used to generate a 35 character secret for the tunnel
resource "random_id" "tunnel_secret" {
  byte_length = 35
}
# A Named Tunnel resource called cl_tunnel
resource "cloudflare_argo_tunnel" "cl_tunnel" {
  account_id = var.cf_acctid
  name       = "chainlink-${var.network}-tunnel"
  secret     = random_id.tunnel_secret.b64_std
}

resource "cloudflare_record" "cl_record" {
  zone_id = var.cf_zoneid
  name    = "chainlink-${var.network}"
  value   = "${cloudflare_argo_tunnel.cl_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
}

resource "kubernetes_secret" "cloudflared_creds" {
  metadata {
    name      = "cloudflared_creds"
    namespace = "chainlink"
  }
  data = {
    "cert.json" = <<EOF
{
    "AccountTag"   : "${var.cf_acctid}",
    "TunnelID"     : "${cloudflare_argo_tunnel.cl_tunnel.id}",
    "TunnelName"   : "${cloudflare_argo_tunnel.cl_tunnel.name}",
    "TunnelSecret" : "${random_id.tunnel_secret.b64_std}"
}
    EOF
  }
}

resource "kubernetes_config_map" "cloudflared_config" {
  metadata {
    name      = "cloudflared_config"
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

resource "kubernetes_deployment" "cloudflared" {
  metadata {
    name = "cloudflared"
    namespace = "chainlink"
    labels = {
      app = "cloudflared"
    }
  }
  spec {
    replicas = 2
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
            name       = "cloudflared_config"
            mount_path = "/etc/cloudflared"
            read_only  = true
          }
          volume_mount {
            name       = "cloudflared_creds"
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
          name = "cloudflared_creds"
          secret {
            secret_name = "cloudflared_creds"
          }
        }
        volume {
          name = "cloudflared_config"
          config_map {
            name = "cloudflared_config"
          }
        }
      }
    }
  }
}
