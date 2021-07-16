# Pixel Streaming in Azure

### Everything you need to know about deploying Unreal&#39;s Pixel Streaming in Azure

Important: Before cloning this repo you must install the LFS extension at: https://git-lfs.github.com/ and open a git/console command window and type git lfs install to initialize git-lfs. Then in your cloned folder, you need to run "git lfs install". There are large binaries in the repo, thus we needed to enable Git Large File Storage capabilities. 
 

# Contents

- [Overview](#overview)
  - [Overview of Unreal Engine&#39;s Pixel Streaming](#overview-of-unreal-engines-pixel-streaming)
  - [Additions Added by Microsoft](#additions-added-by-microsoft)
- [Architecture](#architecture)
  - [Matchmaker (Redirects to available servers)](#matchmaker-redirects-to-available-servers)
  - [Signaling Web Server (WebRTC streaming server)](#signaling-web-server-webrtc-streaming-server)
  - [Unreal 3D Pixel Streaming App](#unreal-3d-pixel-streaming-app)
  - [User Flow](#user-flow)
- [Azure SKU Recommendations](#azure-sku-recommendations)
- [Optimizing Pixel Streaming in Azure](#optimizing-pixel-streaming-in-azure)
  - [Performance Optimizations](#performance-optimizations)
  - [Price Optimizations](#price-optimizations)
  - [Recommendations for Further Optimizations](#recommendations-for-further-optimizations)
- [Configurations](#configurations)
  - [Terraform Configuration](#terraform-configuration)
  - [Deployment Script Configurations](#deployment-script-configurations)
  - [Matchmaker Configuration](#matchmaker-configuration)
  - [Signaling Server Configuration](#signaling-server-configuration)
  - [Unreal 3D App](#unreal-3d-app)
  - [Autoscaling Configuration](#autoscaling-configuration)
  - [Player HTML &amp; Custom Event Configuration](#player-html--custom-event-configuration)
- [Deployment](#deployment)
- [Redeploying Updates](#redeploying-updates)
- [Shutting Down and Restarting Later](#shutting-down-and-restarting-later)
  - [Shutting down the core compute](#shutting-down-the-core-compute)
  - [Starting back up the core compute](#starting-back-up-the-core-compute)
- [Monitoring](#monitoring)
- [Supporting the Solution](#supporting-the-solution)
- [Terraform](#terraform)
  - [Folder Structure](#folder-structure)
  - [Contributing](#contributing)
  - [Trademarks](#trademarks)


# Overview

This document goes through an overview on how to deploy Unreal Engine&#39;s Pixel Streaming technology in Azure at scale, which is a technology that Epic Games provides in their Unreal Engine to stream remotely deployed interactive 3D applications through a browser (i.e., computer/mobile) without the need for the connecting client to have GPU hardware. Additionally, this document will describe the customizations Azure Engineering has built on top of the existing Pixel Streaming solution to provide additional resiliency, logging/metrics and autoscaling specifically for production workloads in Azure. The additions built for Azure are being released on GitHub, which consists of an end-to-end solution deployed via Terraform to spin up a multi-region deployment with only a few Terraform commands. The deployment has many configurations to tailor to your requirements such as which Azure region(s) to deploy to, the SKUs for each VM/GPUs, the size of the deployment, HTTP/HTTPs and autoscaling policies (node count &amp; percentage based).

## Overview of Unreal Engine&#39;s Pixel Streaming

Unreal Pixel Streaming allows developers to stream rendered frames and audio from a remote GPU enabled computer (e.g., cloud) to their users through a desktop or mobile web browser, without the need for the users to have special GPU hardware. More than just a stream, Pixel Streaming allows users to interact with the 3D application, as mouse and keyboard inputs are communicated back to the remote server and processed with low latency. This gives the user the experience as if they were using the application right on their own computer or mobile device. Some common use cases for this are for games, simulations, or immersive experiences such as a configuring a new car or walking through a virtual showroom. Applications are developed in Unreal Engine and then exported out as a Windows executable to be placed on a GPU capable server, which then communicates with a local WebRTC NodeJS server to broker the stream and interactions to and from the client&#39;s browser connection.

**Epic Documentation:** [Getting Started](https://docs.unrealengine.com/en-US/Platforms/PixelStreaming/PixelStreamingIntro/index.html), [Architecture/Networking](https://docs.unrealengine.com/en-US/Platforms/PixelStreaming/Hosting/index.html), [Configs](https://docs.unrealengine.com/en-US/Platforms/PixelStreaming/PixelStreamingReference/index.html)

## Additions Added by Microsoft

Microsoft worked with Epic to customize Pixel Streaming for the cloud using Microsoft Azure, which has resulted in many key additions to deploy and monitor a Pixel Streaming solution at scale. Below are the notable additions that have been incorporated into the open-source solution being released in Azure&#39;s GitHub:

- **General**
  - Azure integration scripts, as the current product only exports out AWS scripts
  - End-To-End deployment in Microsoft Azure with Terraform
  - Autoscaling capabilities to enable thresholds for scaling up or scaling back down GPU compute
  - Multi-region deployments in Azure with utility scripts for spin up/down/deployment management
  - GoDaddy CNAME registration for each Matchmaker / Signaling Server node (VMSS) when using HTTPS (can tweak to use alternative registrar REST API)
  - Automated installation of pre-reqs for the VMs (i.e., VC++, DirectX, Node.js, NVIDIA drivers, etc.)
  - Auto startup tasks if the services/3D app close unexpectedly or when starting/restarting the VMs
  - Start of a testing framework to test load the deployment by connecting to multiple streams through multiple browser sessions spun up in VMSS nodes.
- **Matchmaker**
  - Resiliency for recovering from disconnects with the Signaling Server
  - Removed duplication of redirects causing shared sessions
  - HTTPS capabilities for the Matchmaker Node.js service
  - Host and custom application metrics for monitoring in Azure with Application Insights
  - Logging sent into Azure via Log Analytics
  - Configuration file to avoid hard coding ports and config items in the JavaScript code
  - Autoscaling policies based on total and available connections, which trigger scale operations on the Virtual Machine Scale Set that hosts the Signaling Server and 3D application.
  - Added a /ping API to use for Traffic Manager health checks
- **Signaling Service**
  - Resiliency for failed Matchmaker connections
  - Retries when WebSocket failures occur
  - Stderror logging to log any unhandled thrown errors
  - js scripting to restart and bring back up the 3D app when a user session ended (via PowerShell), giving new users a fresh session

## Note:  

When you deploy this template, Microsoft is able to identify the installation of Unreal Engine&#39;s Pixel Streaming technology with the Azure resources that are deployed. Microsoft is able to correlate the Azure resources that are used to support the software. Microsoft collects this information to provide the best experiences with their products and to operate their business. The data is collected and governed by Microsoft's privacy policies, which can be found at [https://www.microsoft.com/trustcenter](https://www.microsoft.com/trustcenter).
  
# Architecture

![alt text](https://unrealbackendfiles.blob.core.windows.net/ourpublicblobs/Github/PixelStreamingArchitecture.png)

The Pixel Streaming architecture customized for Azure is setup to deploy the Pixel Streaming solution to multiple specified regions with a Traffic Manager as the entry point, allowing the user to be directed to the closest deployed region for the lowest latency possible. Though a user in Texas (US) could connect to an Azure region in Washington (US) and still have a good experience, the closer the user is to the deployed region the more snappy the interactivity feels due to expected latency. Each regional deployment of a Pixel Streaming solution is made up of the following key components:

## Matchmaker (Redirects to available servers)

The Matchmaker (MM) is the first core service hit (via Traffic Manager) that determines which streaming servers are available to redirect a user to, and can be thought of as a special load balancer or orchestrator to ensure users can get to an available Pixel Streaming app. Without this service users accessing a pool of Pixel Streaming servers on a Virtual Machine Scale Set (VMSS) would hit the load balancer and be randomly routed to an instance that would likely collide with other user sessions, and people would be sharing sessions and fighting for control of the app.

The Matchmaker is a simple Node.js webapp deployed on a Windows Server (could be any OS that can run Node.js) that listens for connections from an incoming user, and does a browser redirect to the address of an available GPU VM running the Signaling Server and 3D app. Web socket connections are used to communicate with the Signaling Web Servers to track which server instances are available or not. The MM service is generated from the Unreal Engine when exporting a Pixel Streaming application. It&#39;s important for the Matchmaker and the WebRTC Signaling Web Server which is on a separate GPU node to stay in constant communication, which is done via web sockets. As users connect/disconnect from a Signaling Server the communication is sent back to the Matchmaker to let it know that the server is available/unavailable. The Matchmaker will not redirect a user to a Signaling Server if it has not communicated back to the Matchmaker that it is not only connected, but &quot;message.ready == true&quot; to let the Matchmaker know the 3D app on the GPU VM is streaming and ready to be used. The main code for the Matchmaker is here within our GitHub repo:

UnrealEngine\Engine\Source\Programs\PixelStreaming\WebServers\Matchmaker\matchmaker.js

It will run as a console app, and can be manually ran by launch run.bat in the Matchmaker\ path. You can test that it is up by hitting the /ping path on the DNS (i.e., http://\&lt;azure\_subdomain\&gt;.westus.cloudapp.azure.com:90/ping) to validate Node.js is running, or by simply hitting the root on port 90 to be directed to a streaming server. Once the Matchmaker sees that all the available slots for streaming are used, it will show a webpage to the user telling them to wait for an available server, and will do a force refresh every 10 seconds to reevaluate any open servers to send them to. Note that there is no queuing of users so if the available Signaling Servers become full the next user to get the spot is the first user who&#39;s browser refreshed after one becomes available.

## Signaling Web Server (WebRTC streaming server)

The Signaling Server is a Node.js webapp that handles the WebRTC streaming from the Unreal 3D Pixel Streaming application back to the user. Like the Matchmaker, this is generated from the Unreal Engine when exporting a Pixel Streaming application. It is in constant communication with the Matchmaker through sockets, letting the MM know when the server is available/unavailable. The SS is deployed on VMSS GPU VMs (e.g. NV12s\_v3, NVIDIA Tesla M60, Windows 10) alongside the Unreal 3D application, and is running a Node.js web server on Http port 80, communicating back to the Matchmaking via port 9999 over web sockets. The SS takes input from the user via a web browser that the user is viewing the app from, and redirects the mouse and keyboard inputs to the 3D application via a JavaScript interface. The SS uses nvenc to turn the 3D streaming into something efficient to beam back to the user rendered frames at 30-60fps, like watching a video that&#39;s interactive as if you were running the 3D app locally.

The core code for the Signaling Server is located here in the GitHub repo:
 UnrealEngine\Engine\Source\Programs\PixelStreaming\WebServers\ SignallingWebServer\cirrus.js

To run the service manually, you can execute the \runAzure.bat file in the code&#39;s root folder. This can be started before or after the 3D app has started. When the Matchmaker and the 3D app are running, the SS logs should show a connection to the matchmaker on port 9999, and a &quot;Streamer Connected::1&quot; to show the 3D app is connected on the box. You can bypass the MM and hit a VMSS node directly via the VMSS node&#39;s specific DNS or IP via port 80 (default). The SS communicates with the 3D app over web socket port 8888. To run the VMSS and the 3D app together, use the Unreal-Pixel-Streaming-on-Azure\scripts\startVMSS.ps1 script, but remember to kill the node.exe process and the Unreal process, otherwise you will get duplicates running. This is the script that is run on startup/restart as well so if you restart the VMSS nodes you shouldn&#39;t need to do anything to get it running again.

As a user disconnects from the server, the SS calls an Unreal-Pixel-Streaming-on-Azure \scripts\OnClientDisconnected.ps1 script to reset the 3D app and start a fresh view for the next user.

## Unreal 3D Pixel Streaming App

The 3D app that the user will be interacting with is built from Unreal Engine, exported as a special Pixel Streaming executable and through command lines arguments it connects over a specified port (8888) to the Node.js Signaling Server. To run the 3D app manually, you can use a shortcut or call the command line properties manually like so (PS Start-Process or manual cmd.exe calls):

Start-Process-FilePath&quot;C:\Unreal\Unreal\\&lt;PixelStreamingApp\&gt;.exe&quot;-ArgumentList&quot;-AudioMixer -PixelStreamingIP=localhost -PixelStreamingPort=8888 -WinX=0 -WinY=0 -ResX=1920 -ResY=1080 -Windowed -RenderOffScreen -ForceRes&quot;

This is the same code above that starts the process in the scripts\OnClientDisconnected.ps1 which the SS Node.js app calls when the client disconnects from a session (e.g., closes the window). To run this 3D app on a VM it must have DirectX runtime, vcredist2017 and Node.js installed, which is done via Chocolatey in the scripts\setupBackendVMSS.ps1 script on deployment. Please note that the \&lt;PixelStreamingName\&gt;.exe isn&#39;t the only executable run on start, but there is a separate executable that is also run and lives in the \&lt;PixelStreamingName\&gt;\ folder which contains the larger exe size.

See the [Configurations section](#_Unreal_3D_App) for the Unreal App below to learn more about notable configs.

## User Flow

Let&#39;s walk through the general flow of what is showed in the architecture Visio diagram above when a user connects to the service:

1. Clients connect to their closest region (1 .. N regions) via Traffic Manager, which does a DNS redirect to the [Matchmaking service](https://docs.unrealengine.com/en-US/Platforms/PixelStreaming/Hosting/index.html) VM
2. The Matchmaking Service redirects to an available node on the paired VMSS which holds the Signaling Service and Unreal 3D app (doesn&#39;t use the Load Balancer). The VMSS nodes have [public Ips for each](https://docs.microsoft.com/en-us/azure/virtual-machine-scale-sets/virtual-machine-scale-sets-networking#public-ipv4-per-virtual-machine) VM and not a single private LB IP, otherwise the Matchmaking Service won&#39;t be able to redirect to the appropriate VMSS that&#39;s available (i.e., a LB would pick a _random_ one)
3. The Signaling Service streams back the 3D app rendered frames and audio content to the client via WebRTC, brokering any user input back to the 3D app for interactivity.

##

# Azure SKU Recommendations

Below are the recommended compute SKUs for general usage of Pixel Streaming in Azure:

- **Matchmaker** : Standard\_F4s\_v2 or similar should be sufficient. 4 cores with a smaller memory footprint should be fine for most deployments as there is very little CPU/Memory usage due to the instant redirecting users to Signaling Servers.
- **Signaling Server** : Standard\_NV12s\_v3 or Standard\_NV6 might be the best price per performance GPU VMs in Azure for Pixel Streaming, with the newer NV12s\_v3&#39;s providing better CPU performance at a similar price-point to the older NV6s. Both have a NVIDIA Tesla M60 GPU. If Ray Tracing is required in your app you&#39;ll need to look at the NCas T4 v3 series VMs. As GPU SKUs are in high demand, it&#39;s important to work with the capacity team early on to request the needed quota for any event or deployment that will be spinning up a great number of GPU VMs.

It is recommended to first deploy your Pixel Streaming executable and run it on your desired GPU SKU to see the performance characteristics around CPU/Memory/GPU usage to ensure no resources are being pegged.

# Optimizing Pixel Streaming in Azure

There are some performance and pricing optimizations to consider when running Pixel Streaming in Azure, and your deployments will need to weight the risks/rewards for each of options.

## Performance Optimizations

Consider the following performance optimizations for your Pixel Streaming solution:

- **FPS:** Consider reducing the frames per second (FPS) of the Unreal application to reduce the load on the GPU especially, which can be set in the _Engine.ini_ file by adding the following section (e.g., 30 fps):

<PixelStreamingProject\>\Saved\Config\WindowsNoEditor\Engine.ini

[/Script/Engine.Engine]
 bUseFixedFrameRate=True
 FixedFrameRate=30.000000

- **Resolution:** If you don&#39;t set the resolution for the Unreal app in the command line or shortcut property arguments it will use the currently set resolution, so it&#39;s recommended to pick a resolution that is the max acceptable resolution for the application such as 720p or 1080p to reduce the load on the GPU/CPU. Use the following arguments when calling the Unreal executable to set the resolution that the Unreal app should run (from the command line/script or from a shortcut of the .exe):

-WinX=0 -WinY=0 -ResX=1920 -ResY=1080 -Windowed -ForceRes

- **3D Complexity:** Like any 3D app dev, the more you can reduce triangle counts, texture sizes and lighting complexity the less load you will be putting on the GPU. Consider that many users may be viewing your Pixel Streaming app from their mobile phone and there could be ways to reduce the complexity without sacrificing too much noticeable quality. This is assuming you need reduce the GPU load, so first test on your target GPU SKU to see if anything is even being pegged.

## Price Optimizations

One of the challenges with Pixel Streaming when streaming to hundreds or even thousands of users is the cost, especially if each user is taking up a whole VM themselves, or if requirements dictate the need to keep an available pool of servers hot so users don&#39;t have to wait to experience the app. Below are some considerations to explore in order to wrangle costs when using more costly compute like GPU SKUs.

- **More streams per VM** : One of the best ways to optimize costs is to fit more than one 3D app on each GPU VM. Depending on requirements and your apps complexity, using the performance optimizations listed above you could potentially fit 2 - 4 apps per VM (e.g., 30fps, 720p). Currently the Azure deployment in GitHub only configures 1 stream per VM, so this functionality would need to be implemented in the MM, SS and setup scripts. Each instance would require a separately running Signaling Server with a different communication port (i.e., 8888, 8889, etc.), and running the 3D app separately with the respective -PixelStreamingPort for each desired instance.
- **Spot VMs:** Another way to reduce costs greatly is to consider looking at Spot VMs for the GPU SKUs which can provide a 60%+ discount for VMs that are sitting idle in Azure and provides deep incentives to customers. There is a chance that Spot VMs can be evicted and given to another customer willing to pay full-price for a guaranteed VM, but If the project&#39;s requirements allow for that risk this option in conjunction with fitting more stream instances per VM has the lowest cost of running Pixel Streaming in Azure. There could be a hybrid approach where some VMs are Spot and others are regular VMs, and depending on the importance of a customer (i.e., paying or VIP) the Matchmaker could be tailored to redirect specific users to different tiers (i.e., Spot/Regular).
- **Promo VMs:** SomeGPU VMs can be found in certain regions as Promo where large discounts are given, which could also be incorporated as a hybrid approach to regular and spot VMs.

## Recommendations for Further Optimizations

The current customized solution in GitHub has many additions that make deploying Pixel Streaming in Azure at scale easier, and below are even more improvements on those customizations which would make it even better:

- **Use an OS Image:** Instead of the scripts downloading all the code, the 3D App, installing pre-requisites, etc., it would be more efficient to have a Windows image already created with everything loaded in order to make the deployment quicker. This also would improve the autoscaling of the Virtual Machine Scale Sets as it takes a few minutes more to per new VM scaled out to go through all the startup and initialization processes. This could be built into the deployment process to first create an image in Azure with the latest code and 3D app already downloaded, and then use that image to deploy to the VMSS. _[Dev in progress]_
- **Multiple Instances Per GPU VM:** Addingsupport for multiple 3D streams per GPU VM will be key to maximize costs when deploying large pools of Pixel Streaming servers to customers. This will need changes to the MM and setup scripts to duplicate SS and 3D app instances being run, as well as keep track of multiple instances per VM for autoscale policy logic. _[Dev in progress]_
- **Add Queuing to Matchmaker** : Currently when a Matchmaker can&#39;t send a user to any available Signaling Server there is no queuing as users stack up waiting for an available stream, and would be good to put in a queuing system in Matchmaker to allow the user waiting the longest to get the next available server.
- **Matchmaker Database:** In order to have improved resiliency of the MM it could share a common database between one or two MM VMs to keep connection/availability status in case one is restarted/goes down. Currently this connection status and stream availability is not persisted. This could be persisted to a Database like CosmosDB/SQL, or even to the local disk via a simple JSON file.
- **More Config Params** : There are multiple areas of improvement for adding more configurations starting in Terraform and moving down through the MM, SS and setup scripts such as \$gitpath, desired ports, whether or not to restart an app session on user disconnect, etc.
- **Multiple Resolutions for Desktop/Mobile:** For mobile users there might not need to be a higher resolution for those streams, and so having multiple streams with different resolutions could maximize performance/costs to send mobile users to mobile streams (e.g., 720p) and desktop users go to higher resolution streams (i.e., 1080p). Either this could be lower resolution streams packed on certain GPU VMs, or a mix (e.g., 3 streams with 1080p, 720p, 720p).
- **Deploying with Azure DevOps or GitHub Actions:** Currently much of the orchestration of deploying the code is done through PowerShell scripts in the scripts\ folder, but much of this could be moved into deployment workflows such as Azure DevOps or GitHub Actions. These were left out to reduce extra dependencies and complexity for those not familiar with these technologies, but for a production solution it would be recommended to utilize them (e.g., ADO, GitHub Actions, Jenkins, etc.).

# Configurations

Below are notable configurations to consider when deploying the Pixel Streaming solution in Azure.

## Terraform Configuration

To set the Azure region(s) to deploy to, look at altering the [iac\outermain.tf](https://github.com/Azure/Unreal-Pixel-Streaming-on-Azure/blob/main/iac/outermain.tf) file by either adding or uncommenting regions in the following section (only region\_1 in _eastus_ set by default):

module&quot;region\_1&quot; {
 …
 }

module&quot;region\_2&quot; {
 …
 }

…

To change the Matchmaker and Signaling Server SKUs and counts, alter the [iac\stamp\variables.tf](https://github.com/Azure/Unreal-Pixel-Streaming-on-Azure/blob/main/iac/stamp/variables.tf) file:

vmss\_start\_instances – The number of GPU VMs to start out with (Default 2)
vmss\_source\_image\_offer – The OS image for the GPU VMs (Default Windows 10)
vmss\_sku – The Azure VM GPU SKU for the Signaling Server (Default Standard\_NV6). Standard\_NV12s\_v3 is a newer CPU and a better price for perf ratio, though some Azure regions require a ticket for quota so NV6 is default for ease of initial deployment.
matchmaker\_vm\_sku – The Matchmaker VM SKU OS (Default 2019-Datacenter)
matchmaker\_vm\_size – The Azure VM SKU for the Matchmaker (Default Standard\_F4s\_v2)
vm\_count – The number of Matchmaker VMs (Default 1) – will need persistence above 1

See the [Terraform](#_Terraform) section to learn more about the deployment files.

## Deployment Script Configurations

Currently the Git location referenced in the deployment is stored in the deployment scripts (needs to be moved to a Terraform variable), so you will need to change the $gitpath variable in the scripts\setupBackendVMSS.ps1 and scripts\setupMatchMakerVM.ps1. **Important:** You must have read access with a Personal Access Token (PAT) to the specified repository for the deployment to work, since when the VMs are created there is a git clone used to deploy the code to the VMs.

## Matchmaker Configuration

Below are the configurations available to the Matchmaker, which a config.json file was added to the existing Matchmaker code to reduce hard coding in the Matchmaker.js file:

{

// The port clients connect to the Matchmaking service over HTTP

httpPort: 90,

// The Matchmaking port the Signaling Service connects to the matchmaker over sockets

matchmakerPort: 9999,

// Instances deployed per node, to be used in the autoscale policy (i.e., 1 unreal app running per GPU VM) – not yet supported

instancesPerNode: 1,

// Amount of available Signaling Service / App instances to be available before we have to scale up (0 will ignore)

instanceCountBuffer: 5,

// Percentage amount of available Signaling Service / App instances to be available before we have to scale up (0 will ignore)

percentBuffer: 25,

//The amount of minutes of no scaling up activity before we decide we might want to see if we should scale down (i.e., after hours--reduce costs)

minMinutesBetweenScaledowns: 60,

//The amount of nodes Azure should scale down by when scale down is invoked

scaleDownByAmount: 1,

// Min number of available app instances we want to scale down to during an idle period (minMinutesBetweenScaledowns passed with no scaleup)

minInstanceCount: 0,

// The total amount of VMSS nodes that we will approve scaling up to

maxInstanceCount: 500,

// The Azure subscription used for autoscaling policy (set by Terraform)

subscriptionId: &quot;&quot;,

// The Azure Resource Group where the Azure VMSS is located, used for autoscaling (set by Terraform)

resourceGroup: &quot;&quot;,

// The Azure VMSS name used for scaling the Signaling Service / Unreal App compute (set by Terraform)

virtualMachineScaleSet: &quot;&quot;,

// Azure App Insights ID for logging and metrics (set by Terraform)

appInsightsInstrumentationKey: &quot;&quot;

};

## Signaling Server Configuration

Below are configs available to the Signaling Server in their config, some added by Microsoft for Azure:

{

&quot;UseFrontend&quot;: false,

&quot;UseMatchmaker&quot;: true, // Set to true if using Matchmaker

&quot;UseHTTPS&quot;: false,

&quot;UseAuthentication&quot;: false,

&quot;LogToFile&quot;: true,

&quot;HomepageFile&quot;: &quot;player.htm&quot;,

&quot;AdditionalRoutes&quot;: {},

&quot;EnableWebserver&quot;: true,

&quot;matchmakerAddress&quot;: &quot;&quot;,

&quot;matchmakerPort&quot;: &quot;9999&quot;, // The web socket port used to talk to the MM

&quot;publicIp&quot;: &quot;localhost&quot;, // The Public IP of the VM, set by Terraform

&quot;subscriptionId&quot;: &quot;&quot;, // The Azure subscription, set by Terraform

&quot;resourceGroup&quot;: &quot;&quot;, // Azure RG set by Terraform

&quot;virtualMachineScaleSet&quot;: &quot;&quot;, // Azure VMSS set by Terraform

&quot;appInsightsInstrumentationKey&quot;: &quot;&quot; // Azure App Insights ID for logging/metrics set by Terraform

}

## Unreal 3D App

The Unreal 3D app and dependencies reside GitHub (Git-LFS enabled) under the Unreal\ folder. The Unreal\ folder structure aligns with what is exported out of Unreal Engine, and below are the specific files\folders you will want to copy over the existing files provided in the example GitHub repository:

1. Your exported \<ProjectName\>.exe should replace Unreal\PixelStreamingDemo.exe
2. \<ProjectName\>\ folder associated with the \<ProjectName\>.exe should replace the  Unreal\PixelStreaming\ folder
3. Replace your entire \Engine\Binaries\ThirdParty\ folder contents you exported with the repo’s \Unreal\Engine\Binaries\ThirdParty\ contents as these third-party dlls are specific to what was used in your 3D application. The existing ones were just what was used in the example app provided in the repo. Make sure you can click on your \<ProjectName\>.exe to run it locally in your cloned repo folder to ensure all dependencies are copied over. This is the only thing needed to be copied over from your own Engine\ folder to the repo.
4. Nothing more is needed to copy over unless you’ve changed any player.htm or specific customizations to the MM or SS web servers, but must be merged with our special customizations and not replaced over our files to ensure a correct merge.

The Unreal application has some key parameters that can be passed in upon startup.

\<PixelStreamingApp\>.exe -AudioMixer -PixelStreamingIP=localhost -PixelStreamingPort=8888 -WinX=0 -WinY=0 -ResX=1920 -ResY=1080 -Windowed -RenderOffScreen -ForceRes

Notable app arguments to elaborate on (see Unreal [docs](https://docs.unrealengine.com/en-US/SharingAndReleasing/PixelStreaming/PixelStreamingReference/#unrealenginecommand-lineparameters) for others):

- -ForceRes: It is important to make sure this argument is used to force the Azure VM&#39;s display adapter to use the specified resolution (i.e., ResX/ResY).
- -RenderOffScreen: This renders the app in the background of the VM so it won&#39;t be seen if RDP&#39;ing into the box, which ensures that a window won&#39;t be minimized and not stream back to the user.
- -Windowed: If this flag isn&#39;t used the resolution parameters will be ignored (i.e., ResX/ResY).
- -PixelStreamingPort: This needs to be the same port specified in the Signaling Server, which is the port on the VM that the communicates with the 3D Unreal app over web sockets.

## Autoscaling Configuration

Microsoft has added the ability to autoscale the 3D stream instances up and down, which is done from new logic added to the Matchmaker which evaluates a desired scaling policy and then scales the Virtual Machine Scale Set compute accordingly. This requires that the Matchmaker has a System Assigned [Managed Service Identity](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview) (MSI) for the VM with permissions to scale up the assigned VMSS resource, which is setup for you already in the Terraform deployment. This eliminates the need to pass in special credentials to the Matchmaker such as a Service Principal, and the MSI is given Contributor access to the region&#39;s Resource Group that was created in the deployment—please adjust as needed per your security requirements.

Here are the key parameters in the Matchmaker config.json required to configure on autoscaling for the Signaling Server and 3D app (VMSS nodes):

**instanceCountBuffer** : Min amount of available streams before triggering a scale up (0 will ignore this). For instance, if you have 5 it will only trigger a scale up if only 4 or less streams are available.

**percentBuffer** : % of available streams before triggering a scale up (0 will ignore this). For instance, if you have 25 it will trigger a scale up if less than 25% of total connected Signaling Servers are available to stream.

**minMinutesBetweenScaledowns** : How many minutes of no new scale operations before considering a scale down (e.g., scale down after hours)

**scaleDownByAmount** : The amount of nodes Azure should scale down by when scale down is invoked

**minInstanceCount** : The number of VMSS nodes we want during an idle period (e.g., never go below 10 nodes)

**maxInstanceCount** : The max number of VMSS nodes to scale out to (e.g., never scale above 250 VMs)

Keep in mind that scaling up can take minutes not seconds (especially longer if not using a baked OS image).

## Player HTML &amp; Custom Event Configuration

When Unreal Pixel Streaming is packaged from Unreal Engine the solution contains a \Engine\Source\Programs\PixelStreaming\WebServers\SignallingWebServer\player.htm file to customize the experience, along with the ability to customize JavaScript functions to send custom events between the browser and the 3D Unreal application. Please see Epic&#39;s robust [documentation](https://docs.unrealengine.com/en-US/SharingAndReleasing/PixelStreaming/CustomPlayer/index.html) on how to make these extra customizations.

# Deployment

The solution is deployed via Terraform. In the repo there is an iac\ (the root for all Terraform code) and scripts\ folder. **Currently the deployment expects a Windows OS** as it references powershell.exe directly, though a simple symlink of pwsh to powershell.exe on Linux apparently works (will be added in a future release). **Important:** Be sure to first follow the guidance in the [Configurations](#_Configurations) section to setup the git repo location and 3D app download location.

To deploy the solution use the following steps:

- Delete the terraform.tfstate file in the iac\ folder if existing from a previous deployment
- Do a Git sync and grab the latest code
- In the console use these 3 commands (Get a Git PAT if repo is private):
  - terraform init
  - terraform validate
  - terraform apply -var &#39;git-pat= **PUT\_GIT\_PAT\_HERE**&#39; --auto-approve

In the scripts folder there are three files to support the team from a deployment perspective:

- scripts\Fork\_DeleteAll.ps1
  - This script has a variable called &quot;\$rootvariable&quot; that should be set with the prefix of the environment that you want to destroy. For instance, in the current environment to destroy all assets that variable should be set to the first 5 random characters created in front of the resources to ensure uniqueness per deployment.
- scripts\Fork\_CleanInstall.ps1
  - This script takes an input variable called &quot;\$pat&quot; that is an active Personal Access Token from GitHub. Then there is the &quot;\$rootiacfolder&quot; variable that should be set to the location where you did your git pull.
- $rootiacfolder = &quot;I:\dlm\Repos\Unreal-Fork\iac\&quot;
- $statefile = $rootiacfolder + &quot;terraform.tfstate&quot;
- $statebackupfile = $rootiacfolder + &quot;terraform.tfstate.backup&quot;
- scripts\Fork\_SetPeerings.ps1
  - This script is run after a CleanInstall to set the peerings from the OtherAssets virtual network. This is used to enable rdp sessions from the BastionHost or any jumpboxes.
  - A variable called &quot;\$rootvariable&quot; should be set with the prefix of the environment that you want to enable peering. For instance, in the current environment is set to first 5 random characters created in front of the resources to ensure uniqueness per deployment.

Post the deployment there are processes that run on the following solution components in each region:

- MatchMaker VM
  - Script: startMMS.ps1
  - Executable: Node.exe
  - Scheduled Task calling the script on restart: StartMMS
- Backend (Web &amp; Signalling Services) VMSS
  - Script: startVMSS.ps1
  - Executable: Node.exe
  - Executable: \<PixelStreamingApp\>.exe
  - Scheduled Task calling the script on restart: StartVMSS

# Redeploying Updates

The easiest way to redeploy during the solution would be to do the following for each piece:

- **Signaling Servers / 3D app**
  - Scale down the VMSS to 0 in each region, wait for it to finish, then scale back up to the desired count again (pulls down fresh code from Git), restart the Matchmaker VMs in each region, then restarting the VMSS nodes in each region to give a full reset and redeployment.
- **Matchmakers**
  - Without having to redeploy everything from Terraform, the easiest way is to manually log into each of the 4 MM VM&#39;s and copy the code changes over from git – unless there needs to be any terraform transformations and in that case you will need to redeploy it fully from Terraform. If it&#39;s just a JavaScript change, replacing the matchmaker.js file is sufficient. Refer to the Matchmaker section above for the folder location.
- **Full redeployment**
  - Use the following steps to redeploy the solution from Terraform:
    - Delete the terraform.tfstate file in the iac\ folder
    - Do a Git sync and grab the latest updates
    - In the console use these 3 commands (Get a PAT from GItHub):
      - terraform init
      - terraform validate
      - terraform apply -var &#39;git-pat= **PUT\_GIT\_PAT\_HERE**&#39; --auto-approve

# Shutting Down and Restarting Later

If we need to shut down the solution and start it up at a later time, see below for the process. This is just shutting down the compute for the Matchmaker and the Signaling Servers, which are the costlier resources (especially the SS GPU VMs) vs. deleting all the resources and requiring a time consuming redeployment.

## Shutting down the core compute

- **Matchmakers**
  - Go to each regional Resource Group in the Azure Portal (i.e., \*-eastus-unreal-rg) and click on the matchmaker VMs (e.g., \*-mm-vm0). Once entered into the **Overview** page of the VM choose the **Stop** button at the top to turn off the VM and not be charged for any further compute. Do this for all regions that are deployed.
- **Signaling Servers / 3D app**
  - Go to each regional Resource Group in the Azure Portal (i.e., \*-eastus-unreal-rg) and click on the Virtual Machine Scale Set (VMSS) resources (e.g., \*vmss). Once entered into the **Overview** page of the VMSS choose the **Stop** button at the top to turn off the VMSS instances and not be charged for any further compute. Do this for all regions that are deployed. See the Redeploying Updates section to see how to scale down to a specific number of VMSS nodes versus turning them all off.

## Starting back up the core compute

- **Matchmakers**
  - Go to each regional Resource Group in the Azure Portal (i.e., \*-eastus-unreal-rg) and click on the matchmaker VMs (e.g., \*-mm-vm0). Once entered into the **Overview** page of the VM choose the **Start** button at the top to turn on the VM. Do this for all regions that are deployed first before turning on the VMSS nodes so they can connect to the MM cleanly. The MM will come back on and start the MM service from the ScheduledTask _StartMMS_ setup on Windows.
- **Signaling Servers / 3D app**
  - Go to each regional Resource Group in the Azure Portal (i.e., \*-eastus-unreal-rg) and click on the Virtual Machine Scale Set (VMSS) resources (e.g., \*vmss). Once entered into the **Overview** page of the VMSS choose the **Start** button at the top to turn back on the VMSS instances. Do this for all regions that are deployed. Each instance will come back on and start the SS and 3D automatically from the ScheduledTask _StartVMSS_ setup on Windows.

# Monitoring

Currently automated Azure dashboards aren&#39;t built when deploying the solution; however, outside of regular host metrics like CPU/Memory, some key metrics will be important to monitor in Azure Monitor/Application Insights such as:

- SSPlayerConnected – The most key metric to know when a user connected (use Count)
- SSPlayerDisconnected – When a user disconnects from the Signaling Server (use Count)
- AvailableConnections – The amount of available Signaling Servers not being used (use Avg)
- TotalConnectedClients – Amount of Signaling Servers connected to the Matchmaker (use Avg)
- TotalInstances – The total number of VMSS instances—should be same as TotalCC&#39;s (use Avg)
- PercentUtilized – The percentage of Signaling Servers (streams) in use (use Avg)
- MatchmakerErrors – The number of Matchmaker (use Count)

# Supporting the Solution

In supporting the deployed solution it is recommended to do a few key things:

- Monitor the dashboards created using the recommended metrics and make sure no unusually high or low connections exists, to validate if usage is spiking/pegging or unusual traffic is happening like too low (something is wrong?) or too high (a potential bot?).
- Looks for an unusual amount of errors being logged, and potentially ignore any syntax error exceptions that say &quot;Unexpected token \<token\>; in Json&quot; as that appears to be hackers trying to send garbage to the Matchmaker.
- If anything gets broken or out of wack you can follow the guidance in the Updates section above which is to restart the Matchmakers, then restart the VMSS nodes for each region. That should force everything to come back online fresh again. If anything is corrupted, scaling down the VMSS to 0, scaling back up to the desired count, restarting the MM&#39;s then restarting the VMSS nodes will do a full reset and redeploy.

# Terraform

Below are the key files in the Terraform setup to understand when altering the code and tweaking the parameters. There is a README.md file in the iac\ folder to get you started on the Terraform deployment. 

## Folder Structure

1. \iac is the root of all infrastructure for the solution.
  1. Outermain.tf is the primary TF File. This file sets base variables like the 5 character prefix on all assets, takes the optional GitHub PAT for private repos and deploys the Global Resource Group, and &quot;Stamps&quot; which are each of the regional deployments
  2. \iac\stamp is the folder with the files to deploy a region
    1. Main.tf is the TF file that handles deployment of all assets in each regional deployment
    2. Variables.tf is the TF file that has parameters for each of the regional deployments
  3. \iac\compute folder contains compute related modules
    1. \iac\compute\autoscale
    2. \iac\compute\availset
    3. \iac\compute\vm
    4. \iac\compute\vmss
  4. \iac\extensions contains the extension modules. These extend the VM and VMSS instances per region. Each has a main.tf to deploy the extension.
    1. \iac\extensions\mmextension
    2. \iac\extensions\nvidiaext (not in use, done in code)
    3. \iac\extensions\ue4extension
    4. \iac\extensions\vmazurediags (not in use)
    5. \iac\extensions\vmdependencyagent
    6. \iac\extensions\vmmonitoringagent
    7. \iac\extensions\vmssazurediags (not in use)
    8. \iac\extensions\vmssdependencyagent
    9. \iac\extensions\vmssmonitoringagent
    10. \iac\extensions\vmssmanagedidentity (not in use, done in code)
  5. \iac\global
    1. Getobjectid.ps1 is used in the main.tf to get a logged in user&#39;s ID.
    2. Main.tf contains the resources to deploy the Global Resource Group
  6. \iac\mgmt
    1. \iac\mgmt\akv contain the modules to deploy Key Vault
    2. \iac\mgmt\appinsights contain the modules to deploy Application Insights
    3. \iac\mgmt\loganalytics contain the modules to deploy Log Analytics

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft 
trademarks or logos is subject to and must follow 
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.

© 2020, Microsoft Corporation. All rights reserved