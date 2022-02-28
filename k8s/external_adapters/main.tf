terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
  }
}

provider "kubernetes" {
  config_path    = "../baramio-kubeconfig.yaml"
}

resource "kubernetes_service" "ea1_service" {
  metadata {
    name = "ea1"
    namespace = "chainlink"
    labels = {
      app = "cl-ea1"
    }
  }
  spec {
    selector = {
      app = "cl-ea1"
    }
    port {
      port = 8080
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "cl-ea1" {
  metadata {
    name = "cl-ea1"
    namespace = "chainlink"
    labels = {
      app = "cl-ea1"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "cl-ea1"
      }
    }
    template {
      metadata {
        labels = {
          app = "cl-ea1"
        }
      }
      spec {
        container {
          image = "public.ecr.aws/chainlink/adapters/nop-olympics-adapter:latest"
          name  = "cl-ea1"
          env {
            name = "API_ENDPOINT"
            value = "https://k6yjih2ut8.execute-api.us-west-2.amazonaws.com/default/NOP_Olympics_DP1"
          }
          env {
            name = "CACHE_ENABLED"
            value = "true"
          }
          env {
            name = "CACHE_MAX_AGE"
            value = "60000"
          }
          port {
            container_port = 8080
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "ea2_service" {
  metadata {
    name = "ea2"
    namespace = "chainlink"
    labels = {
      app = "cl-ea2"
    }
  }
  spec {
    selector = {
      app = "cl-ea2"
    }
    port {
      port = 8080
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "cl-ea2" {
  metadata {
    name = "cl-ea2"
    namespace = "chainlink"
    labels = {
      app = "cl-ea2"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "cl-ea2"
      }
    }
    template {
      metadata {
        labels = {
          app = "cl-ea2"
        }
      }
      spec {
        container {
          image = "public.ecr.aws/chainlink/adapters/nop-olympics-adapter:latest"
          name  = "cl-ea2"
          env {
            name = "API_ENDPOINT"
            value = "https://k6yjih2ut8.execute-api.us-west-2.amazonaws.com/default/NOP_Olympics_DP2"
          }
          env {
            name = "CACHE_ENABLED"
            value = "true"
          }
          env {
            name = "CACHE_MAX_AGE"
            value = "60000"
          }
          port {
            container_port = 8080
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "ea3_service" {
  metadata {
    name = "ea3"
    namespace = "chainlink"
    labels = {
      app = "cl-ea3"
    }
  }
  spec {
    selector = {
      app = "cl-ea3"
    }
    port {
      port = 8080
    }
    type = "ClusterIP"
  }
}

resource "kubernetes_deployment" "cl-ea3" {
  metadata {
    name = "cl-ea3"
    namespace = "chainlink"
    labels = {
      app = "cl-ea3"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "cl-ea3"
      }
    }
    template {
      metadata {
        labels = {
          app = "cl-ea3"
        }
      }
      spec {
        container {
          image = "public.ecr.aws/chainlink/adapters/nop-olympics-adapter:latest"
          name  = "cl-ea3"
          env {
            name = "API_ENDPOINT"
            value = "https://k6yjih2ut8.execute-api.us-west-2.amazonaws.com/default/NOP_Olympics_DP3"
          }
          env {
            name = "CACHE_ENABLED"
            value = "true"
          }
          env {
            name = "CACHE_MAX_AGE"
            value = "60000"
          }
          port {
            container_port = 8080
          }
        }
      }
    }
  }
}