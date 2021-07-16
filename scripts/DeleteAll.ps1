##Copyright (c) Microsoft Corporation.
## Licensed under the MIT license.
# This script is optional. This script has a variable called “$rootvariable” that should be set with the
# prefix of the environment that you want to destroy. For instance, in the current environment to destroy 
# all assets that variable should be set to the first 5 random characters created in front of the resources 
# to ensure uniqueness per deployment.

Param (
    [Parameter(Mandatory = $True, HelpMessage = "root environment prefix")]
    [String]$rootvariable = ""
)

#variables
#$rootvariable = "jk07k"
$vnetname = "jumpbox-vnet" 
#$vnetname = "jumpbox-fork-vnet" 

#script

#step 1 delete the resource groups
$r1 = $rootvariable + "-eastus-unreal-rg"
az group delete --name $r1 --no-wait --yes

$r2 = $rootvariable + "-westeurope-unreal-rg"
az group delete --name $r2 --no-wait --yes

$r3 = $rootvariable + "-westus-unreal-rg"
az group delete --name $r3 --no-wait --yes

$r4 = $rootvariable + "-southeastasia-unreal-rg"
az group delete --name $r4 --no-wait --yes

$r5 = $rootvariable + "-global-unreal-rg"
az group delete --name $r5 --no-wait --yes

#step 2 delete the resource peerings if they exist
az network vnet peering delete --name LinkVnet1ToVnet2 --resource-group OtherAssets --vnet-name $vnetname
az network vnet peering delete --name LinkVnet1ToVnet3 --resource-group OtherAssets --vnet-name $vnetname
az network vnet peering delete --name LinkVnet1ToVnet4 --resource-group OtherAssets --vnet-name $vnetname
az network vnet peering delete --name LinkVnet1ToVnet5 --resource-group OtherAssets --vnet-name $vnetname