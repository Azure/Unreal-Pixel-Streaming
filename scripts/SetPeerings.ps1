# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.

# This script is optional. This enables peering from a resource group called OtherAssets and would 
# be run after a deployment to set the peerings from the OtherAssets virtual network. This is used
# to enable rdp sessions from a BastionHost or a jumpbox that you want to leverage to centrally manage. 
# The variable “$rootvariable” should be set with the prefix of the environment that you want to enable peering. 
# For instance, in the current environment is set to first 5 random characters created in front of the resources
# to ensure uniqueness per deployment.

Param (
    [Parameter(Mandatory = $True, HelpMessage = "root environment prefix")]
    [String]$rootvariable = ""
)

#variables
$jumpboxvnet = "jumpbox-vnet"

#variables
$RG1 = $rootvariable + "-eastus-unreal-rg"
$RG2 = $rootvariable + "-westus-unreal-rg"
$RG3 = $rootvariable + "-westeurope-unreal-rg"
$RG4 = $rootvariable + "-southeastasia-unreal-rg"

$VNET1 = $rootvariable + "-vnet-eastus"
$VNET2 = $rootvariable + "-vnet-westus"
$VNET3 = $rootvariable + "-vnet-westeurope"
$VNET4 = $rootvariable + "-vnet-southeastasia"

#script
$VNet1Id = (az network vnet show --resource-group OtherAssets --name $jumpboxvnet --query id --out tsv)
$VNet2Id = (az network vnet show --resource-group $RG1 --name $VNET1 --query id --out tsv)
$VNet3Id = (az network vnet show --resource-group $RG2 --name $VNET2 --query id --out tsv)
$VNet4Id = (az network vnet show --resource-group $RG3 --name $VNET3 --query id --out tsv)
$VNet5Id = (az network vnet show --resource-group $RG4 --name $VNET4 --query id --out tsv)

az network vnet peering create --name LinkVnet1ToVnet2 --resource-group OtherAssets --vnet-name $jumpboxvnet --remote-vnet $VNet2Id --allow-vnet-access
az network vnet peering create --name LinkVnet2ToVnet1 --resource-group $RG1 --vnet-name $VNET1 --remote-vnet $VNet1Id --allow-vnet-access

az network vnet peering create --name LinkVnet1ToVnet3 --resource-group OtherAssets --vnet-name $jumpboxvnet --remote-vnet $VNet3Id --allow-vnet-access
az network vnet peering create --name LinkVnet3ToVnet1 --resource-group $RG2 --vnet-name $VNET2 --remote-vnet $VNet1Id --allow-vnet-access

az network vnet peering create --name LinkVnet1ToVnet4 --resource-group OtherAssets --vnet-name $jumpboxvnet --remote-vnet $VNet4Id --allow-vnet-access
az network vnet peering create --name LinkVnet4ToVnet1 --resource-group $RG3 --vnet-name $VNET3 --remote-vnet $VNet1Id --allow-vnet-access

az network vnet peering create --name LinkVnet1ToVnet5 --resource-group OtherAssets --vnet-name $jumpboxvnet --remote-vnet $VNet5Id --allow-vnet-access
az network vnet peering create --name LinkVnet5ToVnet1 --resource-group $RG4 --vnet-name $VNET4 --remote-vnet $VNet1Id --allow-vnet-access
