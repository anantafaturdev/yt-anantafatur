terraform {
  required_version = ">= 1.3.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# ==================================================
# Azure Provider Configuration
# ==================================================
provider "azurerm" {
  features {}
}

# ==================================================
# Resource Group
# Centralized container for all POC resources
# ==================================================
resource "azurerm_resource_group" "rg" {
  name     = "rg-vm-backup-poc"
  location = "Southeast Asia"
}

# ==================================================
# Virtual Network & Subnet
# Network layer for VM connectivity
# ==================================================
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-poc"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "snet-poc"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# ==================================================
# Network Interface & Public IP
# Provides external access to the VM
# ==================================================
resource "azurerm_public_ip" "pip" {
  name                = "pip-vm-poc"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Dynamic"
  sku                 = "Basic"
}

resource "azurerm_network_interface" "nic" {
  name                = "nic-vm-poc"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# ==================================================
# Linux Virtual Machine
# Lightweight VM used for disk backup demonstration
# ==================================================
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-poc-backup"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  # Burstable VM size for cost-efficient POC usage
  size                = "Standard_B1ls"

  admin_username      = "adminuser"
  admin_password      = "P@ssw0rd1234!"
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
}

# ==================================================
# Managed Data Disk
# Dedicated disk used as backup source
# ==================================================
resource "azurerm_managed_disk" "data_disk" {
  name                 = "datadisk-vm-poc"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 1
}

resource "azurerm_virtual_machine_data_disk_attachment" "data_disk_attach" {
  managed_disk_id    = azurerm_managed_disk.data_disk.id
  virtual_machine_id = azurerm_linux_virtual_machine.vm.id
  lun                = 10
  caching            = "ReadWrite"
}

# ==================================================
# Storage Account
# Destination for VM disk backup artifacts
# ==================================================
resource "azurerm_storage_account" "backup_sa" {
  name                     = "stgbackuppoc${substr(md5(azurerm_resource_group.rg.name), 0, 8)}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  min_tls_version          = "TLS1_2"

  public_network_access_enabled = true
  allow_nested_items_to_be_public = false

  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
}

# ==================================================
# Blob Container
# Logical container for VM disk backup files
# ==================================================
resource "azurerm_storage_container" "backup_container" {
  name                  = "vm-disk-backups"
  storage_account_name  = azurerm_storage_account.backup_sa.name
  container_access_type = "private"

  depends_on = [azurerm_storage_account.backup_sa]
}

# ==================================================
# Role Assignment
# Grants Blob Data access to the current principal
# ==================================================
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "storage_contributor" {
  scope                = azurerm_storage_account.backup_sa.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ==================================================
# Outputs
# Useful information for operational access
# ==================================================

output "storage_account_name" {
  value       = azurerm_storage_account.backup_sa.name
  description = "Storage Account name used for VM disk backups"
}

output "storage_account_connection_string" {
  value       = azurerm_storage_account.backup_sa.primary_connection_string
  sensitive   = true
  description = "Primary connection string for the backup storage account"
}

output "resource_group_name" {
  value       = azurerm_resource_group.rg.name
  description = "Resource Group containing all POC resources"
}

output "backup_container_name" {
  value       = azurerm_storage_container.backup_container.name
  description = "Blob container name for VM disk backup artifacts"
}

output "vm_admin_username" {
  value       = azurerm_linux_virtual_machine.vm.admin_username
  description = "Administrator username for the Linux virtual machine"
}
