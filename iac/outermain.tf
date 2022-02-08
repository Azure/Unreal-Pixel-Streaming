// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "2.45.1"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = false
    }
  }
  ##Pixel Streaming on Azure Epic Games attribution
  partner_id = "18a302cf-fbb8-4d50-ae4a-377a95f8048c"
}

##############################################################
## variables
##############################################################
//a Git personal access token to access the repo
variable "git-pat" {
  type        = string
  description = "a Git personal access token to access the repo"
  default     = " "
}

##############################################################
## locals
##############################################################
data "azurerm_subscription" "current" {
}

locals {
  base_name                  = var.base_name == "random" ? random_string.base_id.result : var.base_name
  global_resource_group_name = format("%s-%s", local.base_name, lower(var.base_resource_group_name))
  subscription_id            = data.azurerm_client_config.current.subscription_id
  tenant_id                  = data.azurerm_client_config.current.tenant_id
}

##############################################################
## resources
##############################################################
resource "random_string" "base_id" {
  length  = 5
  special = false
  upper   = false
  number  = true
}

data "azurerm_client_config" "current" {}

#this is to create the Global Resource Group
resource "azurerm_resource_group" "rg_global" {
  name     = local.global_resource_group_name
  location = var.global_region

  tags = {
    "client_id" = data.azurerm_client_config.current.client_id
  }
}

#this is to create the Global AKV
resource "azurerm_key_vault" "akv" {
  name                       = format("akv-%s-%s", local.base_name, lower(var.global_region))
  location                   = var.global_region
  resource_group_name        = azurerm_resource_group.rg_global.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "premium"
  soft_delete_retention_days = var.keyvault_soft_delete_retention_days
  purge_protection_enabled   = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "create",
      "get",
      "list",
      "verify"
    ]

    secret_permissions = [
      "set",
      "get",
      "delete",
      "list",
      "recover"
    ]

    certificate_permissions = [
      "get",
      "delete",
      "list",
      "import",
      "update"
    ]
  }
}

#implement the traffic manager
resource "azurerm_traffic_manager_profile" "traffic_manager_profile" {
  name                   = format("%s-trafficmgr", local.base_name)
  resource_group_name    = azurerm_resource_group.rg_global.name
  traffic_routing_method = "Performance"

  dns_config {
    relative_name = format("%s", local.base_name)
    ttl           = 100
  }

  monitor_config {
    protocol = "TCP"
    port     = var.traffic_manager_profile_port
    path     = ""
  }
}

#implement appinsights
resource "azurerm_application_insights" "appI" {
  name                = format("%s-appinsights-%s", local.base_name, lower(var.global_region))
  resource_group_name = azurerm_resource_group.rg_global.name
  location            = azurerm_resource_group.rg_global.location
  application_type    = "web"
  retention_in_days   = var.application_insights_retention_in_days
}

resource "azurerm_storage_account" "storageaccount" {
  name                     = format("%sstoracct", lower(local.base_name))
  resource_group_name      = azurerm_resource_group.rg_global.name
  location                 = azurerm_resource_group.rg_global.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
}

module "region_deployment" {
  source    = "./region"
  base_name = local.base_name
  for_each  = var.deployment_regions

  resource_group_name = format("%s-%s", local.base_name, each.key)
  region              = each.value.location

  vnet_address_space      = each.value.vnet_address_space
  subnet_address_prefixes = each.value.subnet_address_prefixes

  key_vault_id = azurerm_key_vault.akv.id

  git-pat                      = var.git-pat
  subscription_id              = local.subscription_id
  tenant_id                    = local.tenant_id
  traffic_manager_profile_name = azurerm_traffic_manager_profile.traffic_manager_profile.name
  global_resource_group_name   = azurerm_resource_group.rg_global.name
  instrumentation_key          = azurerm_application_insights.appI.instrumentation_key
  app_id                       = azurerm_application_insights.appI.app_id

  storage_account_id   = azurerm_storage_account.storageaccount.id
  storage_account_name = azurerm_storage_account.storageaccount.name
  storage_account_key  = azurerm_storage_account.storageaccount.primary_access_key
}



