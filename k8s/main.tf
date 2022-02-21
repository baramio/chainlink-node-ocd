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
variable "backup_eth_url" {
  sensitive = true
}
variable "api_user" {}
variable "api_pw" {
  sensitive = true
}
variable "wallet_pw" {
  sensitive = true
}
variable "database_url" {
  sensitive = true
}
variable "chainlink_version" {
  default     = "1.1.0"
  description = "chainlink node client version"
}

provider "kubernetes" {
  config_path    = "baramio-kubeconfig.yaml"
}

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
    FEATURE_WEBHOOK_V2 = true
    ORACLE_CONTRACT_ADDRESS = "0x60b282ab5E60cC114014372795E4a5F9727a426D"
#    MIN_OUTGOING_CONFIRMATIONS = 2
#    MINIMUM_CONTRACT_PAYMENT_LINK_JUELS = 100
  }
}

resource "kubernetes_secret" "chainlink-db-url" {
  metadata {
    name      = "chainlink-db-url"
    namespace = "chainlink"
  }
  data = {
    "db-url" = var.database_url
  }
}

resource "kubernetes_secret" "chainlink-eth-backup-url" {
  metadata {
    name      = "chainlink-eth-backup-url"
    namespace = "chainlink"
  }
  data = {
    "eth-backup-url" = var.backup_eth_url
  }
}

resource "kubernetes_secret" "chainlink-api-creds" {
  metadata {
    name      = "chainlink-api-creds"
    namespace = "chainlink"
  }
  data = {
    ".api" = <<EOF
${var.api_user}
${var.api_pw}
    EOF
  }
}

resource "kubernetes_secret" "chainlink-pw-creds" {
  metadata {
    name      = "chainlink-pw-creds"
    namespace = "chainlink"
  }
  data = {
    ".password" = var.wallet_pw
  }
}

resource "kubernetes_stateful_set" "chainlink-node" {
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
          args = ["local", "n", "-p",  "/chainlink/pw/.password", "-a", "/chainlink/api/.api"]
          env_from {
            config_map_ref {
              name = "chainlink-env"
            }
          }
          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = "chainlink-db-url"
                key = "db-url"
              }
            }
          }
          env {
            name = "ETH_SECONDARY_URLS"
            value_from {
              secret_key_ref {
                name = "chainlink-eth-backup-url"
                key = "eth-backup-url"
              }
            }
          }
          volume_mount {
            name        = "api-volume"
            mount_path  = "/chainlink/api"
            read_only  = true
          }
          volume_mount {
            name        = "password-volume"
            mount_path  = "/chainlink/pw"
            read_only  = true
          }
        }
        volume {
          name = "api-volume"
          secret {
            secret_name = "chainlink-api-creds"
          }
        }
        volume {
          name = "password-volume"
          secret {
            secret_name = "chainlink-pw-creds"
          }
        }
      }
    }
    service_name = "chainlink-node"
  }
}

resource "kubernetes_service" "chainlink_service" {
  metadata {
    name = "chainlink-node"
    namespace = "chainlink"
    labels = {
      app = "chainlink-node"
    }
  }
  spec {
    selector = {
      app = "chainlink-node"
    }
    cluster_ip = "None"
    port {
      port = 6688
    }
  }
}

