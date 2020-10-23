provider "azurerm" {
  version = "=2.33.0"
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = var.vnet_name
  location            = var.location
  address_space       = [var.vnet_address_space]
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                      = var.subnet_name
  virtual_network_name      = azurerm_virtual_network.vnet.name
  resource_group_name       = var.resource_group_name
  address_prefixes            = [var.subnet_address_prefix]
}

resource "azurerm_network_security_group" "security_group" {
  name                = var.security_group_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_network_security_rule" "security_rule_ssh" {
  name                        = "ssh"
  priority                    = 101
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.security_group.name
}

resource "azurerm_subnet_network_security_group_association" "security_group_association" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.security_group.id
}

resource "azurerm_public_ip" "public_ip" {
  name                = var.public_ip_name
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
  domain_name_label   = "${var.resource_group_name}-ssh"
}

resource "azurerm_public_ip_prefix" "vault" {
  name                = "vaultpfx"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  prefix_length = 28
}

resource "azurerm_linux_virtual_machine_scale_set" "vault" {
  name = var.cluster_name
  location = var.location
  resource_group_name = azurerm_resource_group.rg.name
  sku = "Standard_D2s_v3"
  instances = 3
  admin_username = "adminuser"

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/ncabatoff-test1_key.pem.pub")
  }
  os_disk {
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interface {
    name    = "nic"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.subnet.id
      public_ip_address {
        name = "pubip"
        public_ip_prefix_id = azurerm_public_ip_prefix.vault.id
      }
    }
  }

  identity {
    type = "SystemAssigned"
  }

  custom_data = base64encode(templatefile("${path.module}/setup-node.sh", {
    subscription_id = data.azurerm_subscription.primary.subscription_id
    connection_string = data.azurerm_storage_account_blob_container_sas.binaries.connection_string
    binary_container = data.azurerm_storage_account_blob_container_sas.binaries.container_name
    binary_blob = var.binary_blob
    vault_version = var.vault_version
    resource_group = azurerm_resource_group.rg.name
    scale_set = var.cluster_name
  }))

  tags = {
    scaleSetName = var.cluster_name
  }
}

data "azurerm_subscription" "primary" {}
data "azurerm_client_config" "current" {}

resource "azurerm_role_definition" "stateset-read" {
  name               = "go-discover"
  scope              = data.azurerm_subscription.primary.id

  permissions {
    actions     = ["Microsoft.Compute/virtualMachineScaleSets/*/read"]
  }

  assignable_scopes = [
    data.azurerm_subscription.primary.id,
  ]
}

resource "azurerm_role_assignment" "vault_role" {
  scope                = data.azurerm_subscription.primary.id
  role_definition_id   = azurerm_role_definition.stateset-read.role_definition_resource_id
  principal_id         = azurerm_linux_virtual_machine_scale_set.vault.identity[0].principal_id
}

resource "azurerm_storage_account" "storage" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "binaries" {
  name                  = var.binary_bucket
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "vault_binary" {
  name                   = var.binary_blob
  storage_account_name   = var.storage_account_name
  storage_container_name = azurerm_storage_container.binaries.name
  type                   = "Block"
  source                 = var.binary_source
}

data "azurerm_storage_account_blob_container_sas" "binaries" {
  connection_string = azurerm_storage_account.storage.primary_connection_string
  container_name    = azurerm_storage_container.binaries.name

  start  = "2020-10-01"
  expiry = "2020-11-01"

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = true
  }
}

output "sas_url_query_string" {
  value = data.azurerm_storage_account_blob_container_sas.binaries.connection_string
}

output "vault_public_ip" {
  description = "public IP address of the Vault server"
  value       = azurerm_public_ip.public_ip.ip_address
}
