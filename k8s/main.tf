terraform {
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

resource "kubernetes_namespace" "chainlink-polygon" {
  metadata {
    name = "chainlink-polygon"
  }
}

resource "kubernetes_config_map" "chainlink-polygon-env" {
  metadata {
    name      = "chainlink-polygon-env"
    namespace = "chainlink-polygon"
  }
  data = {
    ROOT = "/chainlink"
    LOG_LEVEL = "debug"
    ETH_CHAIN_ID = 80001
    TLS_CERT_PATH = "/chainlink/tls/server.crt"
    TLS_KEY_PATH = "/chainlink/tls/server.key"
    ALLOW_ORIGINS = "*"
    ETH_URL = "wss://polygon2-${var.network}-ws.baramio-nodes.com"
    ETH_HTTP_URL = "https://polygon2-${var.network}-rpc.baramio-nodes.com"
    FEATURE_WEBHOOK_V2 = true
    ORACLE_CONTRACT_ADDRESS = var.ORACLE_CONTRACT_ADDRESS
    FEATURE_OFFCHAIN_REPORTING = true
    OCR_TRACE_LOGGING = true
    P2P_LISTEN_PORT = 9333
    P2P_ANNOUNCE_IP = kubernetes_service.chainlink-polygon_service_expose.status.0.load_balancer.0.ingress.0.ip
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
  depends_on = [kubernetes_service.chainlink-polygon_service_expose]
}

resource "kubernetes_secret" "chainlink-polygon-db-url" {
  metadata {
    name      = "chainlink-polygon-db-url"
    namespace = "chainlink-polygon"
  }
  data = {
    "db-url" = var.database_url
  }
}

resource "kubernetes_secret" "chainlink-polygon-api-creds" {
  metadata {
    name      = "chainlink-polygon-api-creds"
    namespace = "chainlink-polygon"
  }
  data = {
    ".api" = <<EOF
${var.api_user}
${var.api_pw}
    EOF
  }
}

resource "kubernetes_secret" "chainlink-polygon-pw-creds" {
  metadata {
    name      = "chainlink-polygon-pw-creds"
    namespace = "chainlink-polygon"
  }
  data = {
    ".password" = var.wallet_pw
  }
}

resource "kubernetes_stateful_set" "chainlink-polygon-node" {
  metadata {
    name = "chainlink-polygon"
    namespace = "chainlink-polygon"
    labels = {
      app = "chainlink-polygon-node"
    }
  }
  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "chainlink-polygon-node"
      }
    }
    template {
      metadata {
        labels = {
          app = "chainlink-polygon-node"
        }
      }
      spec {
        init_container {
          name = "init-chainlink-polygon-node"
          image = "smartcontract/chainlink:${var.chainlink_version}"
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
          image = "smartcontract/chainlink:${var.chainlink_version}"
          name  = "chainlink-polygon-node"
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
              name = "chainlink-polygon-env"
            }
          }
          env {
            name = "DATABASE_URL"
            value_from {
              secret_key_ref {
                name = "chainlink-polygon-db-url"
                key = "db-url"
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
            secret_name = "chainlink-polygon-api-creds"
          }
        }
        volume {
          name = "password-volume"
          secret {
            secret_name = "chainlink-polygon-pw-creds"
          }
        }
        volume {
          name = "tls"
          empty_dir {}
        }
      }
    }
    service_name = "chainlink-polygon-node"
  }
  depends_on = [kubernetes_config_map.chainlink-polygon-env]
}

resource "kubernetes_service" "chainlink-polygon_service" {
  metadata {
    name = "chainlink-polygon-node"
    namespace = "chainlink-polygon"
    labels = {
      app = "chainlink-polygon-node"
    }
  }
  spec {
    selector = {
      app = "chainlink-polygon-node"
    }
    cluster_ip = "None"
    port {
      port = 6689
    }
  }
}

resource "kubernetes_service" "chainlink-polygon_service_expose" {
  metadata {
    name = "chainlink-polygon-node-expose"
    namespace = "chainlink-polygon"
    labels = {
      app = "chainlink-polygon-node"
    }
  }
  spec {
    selector = {
      app = "chainlink-polygon-node"
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
