variable "location" {
  default = ""
}

variable "resource_group_name" {
  default = "vault"
}

variable "vnet_name" {
  default = "vault"
}

variable "vnet_address_space" {
  default = "10.0.0.0/8"
}

variable "subnet_name" {
  default = "vault"
}

variable "subnet_address_prefix" {
  default = "10.1.1.0/24"
}

variable "security_group_name" {
  default = "vault"
}

variable "vnic_name" {
  default = "vault-vnic0"
}

variable "public_ip_name" {
  default = "vault"
}

variable "cluster_name" {
  default = "vault"
}

variable "vault_version" {
  default = "1.5.5"
}

variable "storage_account_name" {
}

variable "binary_bucket" {
  default = "vault-binaries"
}

variable "binary_blob" {
  default = "vault.gz"
}

variable "binary_source" {
}
