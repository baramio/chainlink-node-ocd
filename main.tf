terraform {
  required_version = ">= 1.0.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

variable "ssh_public_key" {
  default     = 1
  description = "ssh public key to access droplets"
}
variable "network" {
  default     = "goerli"
  description = "network the chainlink node should be pointed to"
}

variable "cl1_name" {
  default     = "aeolus"
  description = "name of the first node"
}

variable "region1" {
  default     = "nyc1"
  description = "region 1"
}

variable "instance_size_1" {
  default     = "s-1vcpu-1gb"
  description = "instance size"
}

variable "vpc_network_prefix1" {
  default     = "10.3.3.0/24"
  description = "vpc network prefix for vpc 1"
}

variable "chainlink_version" {
  default     = ""
  description = ""
}

variable "api_user" {
  default     = ""
  description = ""
}

variable "api_pw" {
  default     = ""
  description = ""
}

variable "wallet_pw" {
  default     = ""
  description = ""
}

variable "db_conn_str" {
  default     = ""
  description = ""
}

provider "digitalocean" {}

resource "digitalocean_vpc" "vpc1" {
  name     = "chainlink-${var.region1}-vpc"
  region   = var.region1
  ip_range = var.vpc_network_prefix1
}

resource "digitalocean_droplet" "internet_gateway1" {
  image      = "ubuntu-20-04-x64"
  name       = "${var.network}-${var.cl1_name}"
  region     = var.region1
  size       = "s-1vcpu-1gb"
  tags       = ["internet_gateway"]
  monitoring = true
  vpc_uuid   = digitalocean_vpc.vpc1.id
  user_data  = templatefile("ig_setup.yaml", {
    ssh_public_key = var.ssh_public_key,
    vpc_network_prefix = var.vpc_network_prefix1,

  })
}

resource "digitalocean_droplet" "chainlink_node1" {
  image      = "ubuntu-20-04-x64"
  name       = "chainlink-${var.network}-${var.cl1_name}"
  region     = var.region1
  size       = var.instance_size_1
  tags       = ["chainlink"]
  monitoring = true
  vpc_uuid   = digitalocean_vpc.vpc1.id
  user_data  = templatefile("cl_setup.yaml", {
    ssh_public_key     = var.ssh_public_key,
    gateway_private_ip = digitalocean_droplet.internet_gateway1.ipv4_address_private,
    network            = var.network,
    cl_client_version  = var.chainlink_version,
    api_user           = var.api_user,
    api_pw             = var.api_pw,
    wallet_pw          = var.wallet_pw,
    db_conn_str        = var.db_conn_str
  })
}
