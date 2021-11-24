// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
variable "base_name" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "subscription_id" {
  type = string
}

variable "region" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "global_resource_group_name" {
  type = string
}

variable "storage_account_id" {
  type = string
}
variable "storage_account_name" {
  type = string
}
variable "storage_account_key" {
  type = string
}

#create the regional admin password
resource "random_string" "admin_password" {
  length      = 15
  special     = true
  upper       = true
  number      = true
  min_special = 1
}

locals {
  safePWD               = random_string.admin_password.result
  ip_configuration_name = format("%s-mm-config", var.base_name)
  vmss_name             = format("%s%s", substr(var.base_name, 0, 5), "vmss")

  mm_security_rules = {
    "Open80In"   = { security_rule_priority = 1000, security_rule_direction = "Inbound", security_rule_access = "Allow", security_rule_protocol = "Tcp", security_rule_source_port_range = "*", security_rule_destination_port_range = "80", security_rule_source_address_prefix = "*", security_rule_destination_address_prefix = "*" },
    "Open3389In" = { security_rule_priority = 1030, security_rule_direction = "Inbound", security_rule_access = "Allow", security_rule_protocol = "Tcp", security_rule_source_port_range = "*", security_rule_destination_port_range = "3389", security_rule_source_address_prefix = "64.223.129.16", security_rule_destination_address_prefix = "*" },
    "Open443In"  = { security_rule_priority = 1040, security_rule_direction = "Inbound", security_rule_access = "Allow", security_rule_protocol = "Tcp", security_rule_source_port_range = "*", security_rule_destination_port_range = "443", security_rule_source_address_prefix = "*", security_rule_destination_address_prefix = "*" },
    "Open80Out"  = { security_rule_priority = 1000, security_rule_direction = "Outbound", security_rule_access = "Allow", security_rule_protocol = "Tcp", security_rule_source_port_range = "*", security_rule_destination_port_range = "80", security_rule_source_address_prefix = "*", security_rule_destination_address_prefix = "*" },
    "Open443Out" = { security_rule_priority = 1060, security_rule_direction = "Outbound", security_rule_access = "Allow", security_rule_protocol = "Tcp", security_rule_source_port_range = "*", security_rule_destination_port_range = "443", security_rule_source_address_prefix = "*", security_rule_destination_address_prefix = "*" }
  }
  be_security_rules = {
    "Open80In"   = { security_rule_priority = 1000, security_rule_direction = "Inbound", security_rule_access = "Allow", security_rule_protocol = "Tcp", security_rule_source_port_range = "*", security_rule_destination_port_range = "80", security_rule_source_address_prefix = "*", security_rule_destination_address_prefix = "*" },
    "Open8888In" = { security_rule_priority = 1040, security_rule_direction = "Inbound", security_rule_access = "Allow", security_rule_protocol = "Tcp", security_rule_source_port_range = "*", security_rule_destination_port_range = "8888", security_rule_source_address_prefix = "*", security_rule_destination_address_prefix = "*" },
    "Open8889In" = { security_rule_priority = 1050, security_rule_direction = "Inbound", security_rule_access = "Allow", security_rule_protocol = "Tcp", security_rule_source_port_range = "*", security_rule_destination_port_range = "8889", security_rule_source_address_prefix = "*", security_rule_destination_address_prefix = "*" }
    "Open3389In" = { security_rule_priority = 1060, security_rule_direction = "Inbound", security_rule_access = "Allow", security_rule_protocol = "Tcp", security_rule_source_port_range = "*", security_rule_destination_port_range = "3389", security_rule_source_address_prefix = "64.223.129.16", security_rule_destination_address_prefix = "*" },
    "Open443In"  = { security_rule_priority = 1070, security_rule_direction = "Inbound", security_rule_access = "Allow", security_rule_protocol = "Tcp", security_rule_source_port_range = "*", security_rule_destination_port_range = "443", security_rule_source_address_prefix = "*", security_rule_destination_address_prefix = "*" },
    "Open8890In" = { security_rule_priority = 1080, security_rule_direction = "Inbound", security_rule_access = "Allow", security_rule_protocol = "Tcp", security_rule_source_port_range = "*", security_rule_destination_port_range = "8890", security_rule_source_address_prefix = "*", security_rule_destination_address_prefix = "*" },
    "Open8891In" = { security_rule_priority = 1090, security_rule_direction = "Inbound", security_rule_access = "Allow", security_rule_protocol = "Tcp", security_rule_source_port_range = "*", security_rule_destination_port_range = "8891", security_rule_source_address_prefix = "*", security_rule_destination_address_prefix = "*" }
  }
}

variable "key_vault_id" {
  type = string
}
data "azurerm_client_config" "regional-current" {}

#put this password in akv
resource "azurerm_key_vault_secret" "pwd_secret" {
  name         = format("%s-%s-password", var.base_name, var.region)
  value        = local.safePWD
  key_vault_id = var.key_vault_id
}

#create regional resource group
resource "azurerm_resource_group" "region-rg" {
  name     = var.resource_group_name
  location = var.region

  tags = {
    "client_id" = data.azurerm_client_config.regional-current.client_id
  }
}

variable "vnet_address_space" {
  type = string
}

variable "subnet_address_prefixes" {
  type = string
}

#create the vnet for the region
resource "azurerm_virtual_network" "vnet" {
  name                = format("%s-vnet-%s", var.base_name, lower(var.region))
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.region-rg.location
  resource_group_name = azurerm_resource_group.region-rg.name
}

#create a subnet in the vnet
resource "azurerm_subnet" "subnet" {
  name                 = format("%s-subnet-%s", var.base_name, lower(var.region))
  resource_group_name  = azurerm_resource_group.region-rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.subnet_address_prefixes]
}

#create matchmaker vm
resource "azurerm_public_ip" "pip" {
  name                = format("%s-%s-%s-pip", var.base_name, "mmvm", var.region)
  location            = azurerm_resource_group.region-rg.location
  resource_group_name = azurerm_resource_group.region-rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = lower(format("%s-%s", "mmvm", var.base_name))
}

resource "azurerm_network_interface" "nic" {
  name                    = format("mm-nic-%s", lower(var.region))
  location                = azurerm_resource_group.region-rg.location
  resource_group_name     = azurerm_resource_group.region-rg.name
  internal_dns_name_label = lower(format("%s-%s-local", "mm", var.base_name))

  ip_configuration {
    name                          = local.ip_configuration_name
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                     = "mm-vm"
  location                 = azurerm_resource_group.region-rg.location
  resource_group_name      = azurerm_resource_group.region-rg.name
  size                     = var.matchmaker_vm_size
  admin_username           = var.matchmaker_admin_username
  admin_password           = local.safePWD
  enable_automatic_updates = true
  provision_vm_agent       = true

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.matchmaker_vm_storage_account_type
  }

  source_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    "solution" = "Unreal Pixel Streaming TF"
  }

  custom_data = filebase64("../scripts/setupMatchMakerVM.ps1")
}

//do a role assignment for the new system identity
data "azurerm_subscription" "primary" {
}

resource "azurerm_role_assignment" "role_assignment" {
  scope                = data.azurerm_subscription.primary.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_windows_virtual_machine.vm.identity[0].principal_id
}

#create a NSG for the MM
resource "azurerm_network_security_group" "mm-nsg" {
  name                = format("%s-mm-nsg", var.base_name)
  location            = azurerm_resource_group.region-rg.location
  resource_group_name = azurerm_resource_group.region-rg.name
}

#create a NSG Association for the MM and NSG
resource "azurerm_network_interface_security_group_association" "mm_nsg_association" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.mm-nsg.id
}

resource "azurerm_network_security_rule" "vm_network_security_rules" {
  for_each                    = local.mm_security_rules
  name                        = each.key
  priority                    = each.value.security_rule_priority
  direction                   = each.value.security_rule_direction
  access                      = each.value.security_rule_access
  protocol                    = each.value.security_rule_protocol
  source_port_range           = each.value.security_rule_source_port_range
  destination_port_range      = each.value.security_rule_destination_port_range
  source_address_prefix       = each.value.security_rule_source_address_prefix
  destination_address_prefix  = each.value.security_rule_destination_address_prefix
  resource_group_name         = azurerm_resource_group.region-rg.name
  network_security_group_name = azurerm_network_security_group.mm-nsg.name
}

variable "instrumentation_key" {
  type = string
}

variable "app_id" {
  type = string
}

#create MM extension
variable "git-pat" {
  type = string
}

locals {
  extension_name   = "MM-CS-Extension"
  mm-command       = "powershell -ExecutionPolicy Unrestricted -NoProfile -NonInteractive -command cp c:/AzureData/CustomData.bin c:/AzureData/install.ps1; c:/AzureData/install.ps1 -subscription_id ${var.subscription_id} -resource_group_name ${azurerm_resource_group.region-rg.name} -vmss_name ${local.vmss_name} -application_insights_key ${var.instrumentation_key} -gitpath ${var.gitpath} -pat ${var.git-pat};"
  mm-short_command = "powershell -ExecutionPolicy Unrestricted -NoProfile -NonInteractive -command cp c:/AzureData/CustomData.bin c:/AzureData/install.ps1; c:/AzureData/install.ps1 -subscription_id ${var.subscription_id} -resource_group_name ${azurerm_resource_group.region-rg.name} -vmss_name ${local.vmss_name} -application_insights_key ${var.instrumentation_key} -gitpath ${var.gitpath};"

  #if git-pat is "" then don't add that parameter
  mm-paramstring = var.git-pat != "" ? local.mm-command : local.mm-short_command
}

resource "azurerm_virtual_machine_extension" "mmextension" {
  name                 = local.extension_name
  virtual_machine_id   = azurerm_windows_virtual_machine.vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings           = <<SETTINGS
  {}
  SETTINGS
  protected_settings = <<PROTECTED_SETTINGS
  {
    "commandToExecute": "${local.mm-paramstring}",
    "managedIdentity" : { "objectId": "${azurerm_role_assignment.role_assignment.principal_id}" }
  }
  PROTECTED_SETTINGS
}

#create a NSG for the VMSS
resource "azurerm_network_security_group" "backend-nsg" {
  name                = format("%s-be-nsg", var.base_name)
  location            = azurerm_resource_group.region-rg.location
  resource_group_name = azurerm_resource_group.region-rg.name
}

#create the vmss
resource "azurerm_windows_virtual_machine_scale_set" "vmss" {
  name                = local.vmss_name
  location            = azurerm_resource_group.region-rg.location
  resource_group_name = azurerm_resource_group.region-rg.name

  admin_username = var.backend_admin_username
  admin_password = local.safePWD

  sku       = var.vmss_size
  instances = var.vmss_start_instances

  enable_automatic_updates = true
  upgrade_mode             = "Automatic"

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    storage_account_type = var.backend_vmss_storage_account_type
    caching              = "ReadWrite"
  }

  source_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = "latest"
  }

  network_interface {
    name    = format("vmss-nic-%s", lower(var.region))
    primary = true

    network_security_group_id = azurerm_network_security_group.backend-nsg.id

    ip_configuration {
      name      = "external"
      primary   = true
      subnet_id = azurerm_subnet.subnet.id

      public_ip_address {
        name              = "vmss_public_ip"
        domain_name_label = lower(format("%s-%s", "vmss", var.base_name))
      }
    }
  }

  tags = {
    "solution" = "Unreal Pixel Streaming TF"
  }

  custom_data = filebase64("../scripts/setupBackendVMSS.ps1")
}

resource "azurerm_role_assignment" "vmss_role_assignment" {
  scope                = data.azurerm_subscription.primary.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_windows_virtual_machine_scale_set.vmss.identity[0].principal_id
}

#open inbound and outbound nsgs for the vmss
resource "azurerm_network_security_rule" "vmss_network_security_rules" {
  for_each                    = local.be_security_rules
  name                        = each.key
  priority                    = each.value.security_rule_priority
  direction                   = each.value.security_rule_direction
  access                      = each.value.security_rule_access
  protocol                    = each.value.security_rule_protocol
  source_port_range           = each.value.security_rule_source_port_range
  destination_port_range      = each.value.security_rule_destination_port_range
  source_address_prefix       = each.value.security_rule_source_address_prefix
  destination_address_prefix  = each.value.security_rule_destination_address_prefix
  resource_group_name         = azurerm_resource_group.region-rg.name
  network_security_group_name = azurerm_network_security_group.backend-nsg.name
}

#now I have the vmss_principal_id that I need to give rights to for AKV
#certificates list permission
resource "azurerm_key_vault_access_policy" "vmss-identity-ap" {
  key_vault_id = var.key_vault_id
  tenant_id    = var.tenant_id
  object_id    = azurerm_windows_virtual_machine_scale_set.vmss.identity[0].principal_id

  certificate_permissions = [
    "get",
    "list",
  ]
}


#implement the vmss custom extension
locals {
  internal_fqdn          = format("%s.%s", azurerm_network_interface.nic.internal_dns_name_label, azurerm_network_interface.nic.internal_domain_name_suffix)
  backend_extension_name = "BE-CS-Extension"
  be_command             = "powershell -ExecutionPolicy Unrestricted -NoProfile -NonInteractive -command cp c:/AzureData/CustomData.bin c:/AzureData/install.ps1; c:/AzureData/install.ps1 -subscription_id ${var.subscription_id} -resource_group_name ${azurerm_resource_group.region-rg.name} -vmss_name ${local.vmss_name} -application_insights_key ${var.instrumentation_key} -mm_lb_fqdn ${local.internal_fqdn} -instancesPerNode ${var.instancesPerNode} -streamingPort ${var.streamingPort} -resolutionWidth ${var.resolutionWidth} -resolutionHeight ${var.resolutionHeight} -pixel_stream_application_name ${var.pixel_stream_application_name} -fps ${var.fps} -gitpath ${var.gitpath} -pat ${var.git-pat};"
  be_short_command       = "powershell -ExecutionPolicy Unrestricted -NoProfile -NonInteractive -command cp c:/AzureData/CustomData.bin c:/AzureData/install.ps1; c:/AzureData/install.ps1 -subscription_id ${var.subscription_id} -resource_group_name ${azurerm_resource_group.region-rg.name} -vmss_name ${local.vmss_name} -application_insights_key ${var.instrumentation_key} -mm_lb_fqdn ${local.internal_fqdn} -instancesPerNode ${var.instancesPerNode} -streamingPort ${var.streamingPort} -resolutionWidth ${var.resolutionWidth} -resolutionHeight ${var.resolutionHeight} -pixel_stream_application_name ${var.pixel_stream_application_name} -fps ${var.fps} -gitpath ${var.gitpath};"
  #azurerm_public_ip.pip.fqdn

  #if git-pat is "" then don't add that parameter
  be-paramstring = var.git-pat != "" ? local.be_command : local.be_short_command
}

resource "azurerm_virtual_machine_scale_set_extension" "ue4extension" {
  name                         = local.backend_extension_name
  virtual_machine_scale_set_id = azurerm_windows_virtual_machine_scale_set.vmss.id
  publisher                    = "Microsoft.Compute"
  type                         = "CustomScriptExtension"
  type_handler_version         = "1.10"

  settings           = <<SETTINGS
  {}
  SETTINGS
  protected_settings = <<PROTECTED_SETTINGS
  {
    "commandToExecute": "${local.be-paramstring}",
    "managedIdentity" : { "objectId": "${azurerm_role_assignment.vmss_role_assignment.principal_id}" }
  }
  PROTECTED_SETTINGS
}

variable "traffic_manager_profile_name" {
  type = string
}

#associate the MM to the TM
resource "azurerm_traffic_manager_endpoint" "traffic_manager_endpoint" {
  name                = format("%s-trafficmgr-%s", var.base_name, var.region)
  resource_group_name = var.global_resource_group_name
  profile_name        = var.traffic_manager_profile_name

  #adding target for the pip fqdn
  target            = azurerm_public_ip.pip.fqdn
  endpoint_location = azurerm_resource_group.region-rg.location
  type              = "externalEndpoints"
}
