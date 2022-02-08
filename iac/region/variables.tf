// Copyright (c) Microsoft Corporation.
// Licensed under the MIT license.

#This file is the most critical variables to set and validate for your project needs. This decides what settings are deployed
#to each Matchmaker and Signalling Server nodes. IMPORTANT: Set the gitpath to your forked version and the pixel_stream_application_name
#in order for the deployment to work for your customizations. Be sure to checking and PUSH all GitHub changes as the deployment pulls from Git.

#CHANGE: Set your forked path here for your GitHub repo (and be sure to check in changes as scripts pull resources from GitHub)
variable "gitpath" {
  default = "https://github.com/Azure/Unreal-Pixel-Streaming/"
}

#The name of the Unreal 3D App, (i.e., PixelStreamingDemo.exe without the .exe at the end)
variable "pixel_stream_application_name" {
  default = "PixelStreamingDemo"
}

#Resolution width and height for the 3D App to run (smaller resolutions can fit more streams per GPU and/or a higher FPS)
variable "resolutionWidth" {
  default = 1920
}
variable "resolutionHeight" {
  default = 1080
}

#Frames Per Second desired for the 3D app (-1 means default 60 fps limit. Use 30, 60, etc..)
variable "fps" {
  default = -1
}

#Number of Virtual Machine Scale Set nodes scaled out on the VMSS cluster (1 stream per GPU VM by default)
variable "vmss_start_instances" {
  default = 1
}

#How many instances per node you want to run on each GPU (test with lower FPS and resolution to squeeze more on)
#Try to test manually on a single GPU VM in Azure to validate if more than 1 3D instance can even run for your app. (check GPU/CPU/Mem)
variable "instancesPerNode" {
  default = 1
}

#The default port that Unreal uses to talk to the 3D app from the Signaling Server (WebRTC streaming service)
variable "streamingPort" {
  default = 8888
}

#matchmaker vm size
variable "matchmaker_vm_size" {
  default = "Standard_F4s_v2"
}

#Matchmaker VM login name
variable "matchmaker_admin_username" {
  default = "azureadmin"
}

#Matchmaker uses Locally Redundant Storage by default
variable "matchmaker_vm_storage_account_type" {
  default = "Standard_LRS"
}

#Signaling Server SKU for the VMSS cluster. NV6 have the NVidia GPUs and are more widely available,
#but increase your quota in your Azure portal for NV12s_v3's and use those below as they have a newer, more 
#powerful CPU for similar price. NV6 was the default chosen below to avoid quota errors when using this for the first time.
variable "vmss_size" {
  default = "Standard_NV6"
  #default = "Standard_NV12s_v3"
}

#MSFT created an image in the marketplace that has all the pre-reqs install on Windows 10 for the MM and SS VMs.
#Publisher for the MSFT created Windows 10 VM that both the Matchmaker and Signaling Server use
variable "image_publisher" {
  default = "microsoft-agci-gaming"
}

#Offer for the MSFT created Windows 10 VM that both the Matchmaker and Signaling Server use
variable "image_offer" {
  default = "msftpixelstreaming"
}

#Image SKU for the MSFT created Windows 10 VM that both the Matchmaker and Signaling Server use
variable "image_sku" {
  default = "pixelstreaming_prereqs_nvidia"
}

#Matchmaker VM login name
variable "backend_admin_username" {
  default = "azureadmin"
}

#Signaling Servers use Locally Redundant Storage by default
variable "backend_vmss_storage_account_type" {
  default = "Standard_LRS"
}