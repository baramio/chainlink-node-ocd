terraform {
  required_version = ">= 1.0.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

variable "ssh_public_key" {}
variable "network" {}
variable "api_user" {}
variable "api_pw" {}
variable "wallet_pw" {}
variable "db_conn_str" {}
variable "backup_eth_url" {}
variable "region1" {}
variable "ig1_private_ip" {}
variable "vpc1_uuid" {}
variable "instance_size_1" {}
variable "cl1_name" {
  default     = "aeolus"
  description = "name of the first node"
}
variable "cl2_name" {
  default     = "boreas"
  description = "name of the first node"
}
variable "chainlink_version" {}

provider "digitalocean" {}


resource "digitalocean_droplet" "chainlink_node1" {
  image      = "ubuntu-20-04-x64"
  name       = "chainlink-${var.network}-${var.cl1_name}"
  region     = var.region1
  size       = var.instance_size_1
  tags       = ["chainlink"]
  monitoring = true
  vpc_uuid   = var.vpc1_uuid
  user_data  = templatefile("cl_setup.yaml", {
    ssh_public_key     = var.ssh_public_key,
    gateway_private_ip = var.ig1_private_ip,
    network            = var.network,
    cl_client_version  = var.chainlink_version,
    api_user           = var.api_user,
    api_pw             = var.api_pw,
    wallet_pw          = var.wallet_pw,
    backup_eth_url     = var.backup_eth_url,
    db_conn_str        = var.db_conn_str
  })
}

resource "digitalocean_droplet" "chainlink_node2" {
  image      = "ubuntu-20-04-x64"
  name       = "chainlink-${var.network}-${var.cl2_name}"
  region     = var.region1
  size       = var.instance_size_1
  tags       = ["chainlink"]
  monitoring = true
  vpc_uuid   = var.vpc1_uuid
  user_data  = templatefile("cl_setup.yaml", {
    ssh_public_key     = var.ssh_public_key,
    gateway_private_ip = var.ig1_private_ip,
    network            = var.network,
    cl_client_version  = var.chainlink_version,
    api_user           = var.api_user,
    api_pw             = var.api_pw,
    wallet_pw          = var.wallet_pw,
    backup_eth_url     = var.backup_eth_url,
    db_conn_str        = var.db_conn_str
  })
}
