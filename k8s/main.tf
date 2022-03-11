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
variable "chainlink_version" {}
variable "ORACLE_CONTRACT_ADDRESS" {}
variable "OCR_KEY_BUNDLE_ID" {}
variable "P2P_PEER_ID" {}
variable "OCR_TRANSMITTER_ADDRESS" {}
variable "EXPLORER_ACCESS_KEY" {}
variable "EXPLORER_SECRET" {}
variable "EXPLORER_URL" {}
variable "P2P_BOOTSTRAP_PEERS" {}

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
    TLS_CERT_PATH = "/chainlink/tls/server.crt"
    TLS_KEY_PATH = "/chainlink/tls/server.key"
    ALLOW_ORIGINS = "*"
    ETH_URL = "wss://${var.network}-ec-ws.baramio-nodes.com"
    ETH_HTTP_URL = "https://${var.network}-ec-rpc.baramio-nodes.com"
    FEATURE_WEBHOOK_V2 = true
    ORACLE_CONTRACT_ADDRESS = var.ORACLE_CONTRACT_ADDRESS
    FEATURE_OFFCHAIN_REPORTING = true
    OCR_TRACE_LOGGING = true
    P2P_LISTEN_PORT = 9333
    P2P_ANNOUNCE_IP = kubernetes_service.chainlink_service_expose.status.0.load_balancer.0.ingress.0.ip
    P2P_ANNOUNCE_PORT = 9333
    JSON_CONSOLE = true
    LOG_TO_DISK = false
    OCR_KEY_BUNDLE_ID = var.OCR_KEY_BUNDLE_ID
    P2P_PEER_ID = var.P2P_PEER_ID
    OCR_TRANSMITTER_ADDRESS = var.OCR_TRANSMITTER_ADDRESS
    DATABASE_LOCKING_MODE = "dual"
    EXPLORER_ACCESS_KEY = var.EXPLORER_ACCESS_KEY
    EXPLORER_SECRET = var.EXPLORER_SECRET
    EXPLORER_URL = var.EXPLORER_URL
    P2P_BOOTSTRAP_PEERS = var.P2P_BOOTSTRAP_PEERS
  }
  depends_on = [kubernetes_service.chainlink_service_expose]
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
        init_container {
          name = "init-chainlink-node"
          image = "dextrac/chainlink-olympics:${var.chainlink_version}"
          command = ["bash", "-c", <<EOF
openssl req -x509 -out  /mnt/tls/server.crt  -keyout /mnt/tls/server.key -newkey rsa:2048 -nodes -sha256 -days 365 -subj '/CN=localhost' -extensions EXT -config <(printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")
            EOF
          ]
          volume_mount {
            mount_path = "/mnt/tls"
            name       = "tls"
          }
        }
        container {
          image = "dextrac/chainlink-olympics:${var.chainlink_version}"
          name  = "chainlink-node"
          port {
            container_port = 6688
          }
          port {
            container_port = 6689
          }
          port {
            container_port = 9333
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
          volume_mount {
            mount_path = "/chainlink/tls"
            name       = "tls"
            read_only = true
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
        volume {
          name = "tls"
          empty_dir {}
        }
      }
    }
    service_name = "chainlink-node"
  }
  depends_on = [kubernetes_config_map.chainlink-env]
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
      port = 6689
    }
  }
}

resource "kubernetes_service" "chainlink_service_expose" {
  metadata {
    name = "chainlink-node-expose"
    namespace = "chainlink"
    labels = {
      app = "chainlink-node"
    }
  }
  spec {
    selector = {
      app = "chainlink-node"
    }
    external_traffic_policy = "Local"
    type = "LoadBalancer"
    port {
      port = "9333"
      protocol = "TCP"
      target_port = "9333"
      name = "p2p"
    }
  }
  wait_for_load_balancer = true
}
