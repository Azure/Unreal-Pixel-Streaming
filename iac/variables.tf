// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.
variable "base_name" {
  default = "random"
}

#This is the region where the global resource group will be deployed, and global resources like Traffic Manager, etc...
variable "global_region" {
  default = "eastus"
}

#This is the name of the global resource group that has shared resources across regions like Traffic Manager, Azure Key Vault, etc..
variable "base_resource_group_name" {
  default = "global-unreal-rg"
}

#Storage account tier
variable "storage_account_tier" {
  default = "Standard"
}

#Storage account replication type
variable "storage_account_replication_type" {
  default = "LRS"
}

variable "traffic_manager_profile_port" {
  default = 80
}

variable "application_insights_retention_in_days" {
  default = 30
}

variable "keyvault_soft_delete_retention_days" {
  default = 7
}

#set the regional values in the terraform.tfvars
variable "deployment_regions" {
  type = map(object({
    location                = string
    vnet_address_space      = string
    subnet_address_prefixes = string
  }))
}

#Use if you want to create your own pre-reqs image for Windows 10 and not use the MSFT created one in the marketplace
/*
variable "images_resource_group_name" {
  default = "UnrealGalleryRG"
}

variable "images_resource_group_location" {
  default = "eastus"
}

variable "shared_image_gallery" {
  default = "UnrealImageGallery"
}

variable "shared_image_name" {
  default = "PixelStreamingM60NV12sv3"
}
*/
