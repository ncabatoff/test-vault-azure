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

resource "azurerm_network_interface" "vnic0" {
  name                      = var.vnic_name
  location                  = var.location
  resource_group_name       = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "IPConfiguration"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

resource "azurerm_linux_virtual_machine" "vault" {
  name                          = var.vm_name
  location                      = var.location
  resource_group_name           = azurerm_resource_group.rg.name
  network_interface_ids         = [azurerm_network_interface.vnic0.id]
  admin_username                = "adminuser"
  size                = "Standard_D2s_v3"
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
  disable_password_authentication = true
  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_virtual_machine_extension" "vault_extension" {
  name                  = "vault-extension"
  virtual_machine_id    = azurerm_linux_virtual_machine.vault.id
  publisher             = "Microsoft.Azure.Extensions"
  type                  = "CustomScript"
  type_handler_version  = "2.0"

  settings              = <<SETTINGS
{
  "script": "${base64encode(templatefile("${path.module}/setup-node.sh", {
    subscription_id = data.azurerm_subscription.primary.subscription_id
    connection_string = data.azurerm_storage_account_blob_container_sas.binaries.connection_string
    binary_container = data.azurerm_storage_account_blob_container_sas.binaries.container_name
    binary_blob = var.binary_blob
    vault_version = var.vault_version
    private_ip = azurerm_linux_virtual_machine.vault.private_ip_address
  }))}"
}
SETTINGS
}

data "azurerm_subscription" "primary" {}
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "vault_role" {
  scope                = data.azurerm_subscription.primary.id
  role_definition_name = "Reader"
  principal_id         = lookup(azurerm_linux_virtual_machine.vault.identity[0], "principal_id")
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
